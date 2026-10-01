# 121XML Deployment Notes

## Overview

121XML deployment automation handles the distribution of XML schemas, documentation, and related content to HostArmada hosting (172.241.29.6, user: xml).

## Environment Details

### Target Host
- **Hostname**: 172.241.29.6 (HostArmada)
- **Port**: 19199 (custom SSH port)
- **User**: xml
- **SSH Key**: `C:\Users\Owner\.ssh\121connect_deploy`

### Deployment Paths
- **Staging**: `/home/xml/staging.121xml.com`
- **Production**: `/home/xml/public_html`
- **Backups**: `/home/xml/xml_backups/` (on server)

### URLs
- **Staging**: https://staging.121xml.com
- **Production**: https://121xml.com

## Deployment Workflow

### 1. Local Development

Create/update content in `./content/` directory:
```
content/
├── index.html
├── index.xml
├── api/
│   └── schemas/
│       ├── v1/
│       ├── v2/
│       └── v3/
├── docs/
│   ├── guide.html
│   ├── api-reference.md
│   └── examples/
└── feeds/
    ├── news.xml
    ├── updates.rss
    └── changelog.xml
```

### 2. Staging Deployment

**Automatic on push to main**:
```
git commit -m "Update content for v1.0.1"
git push origin main
    ↓
GitHub Actions workflow triggered
    ↓
Validate XML syntax
    ↓
Create backup of staging
    ↓
Deploy to /home/xml/staging.121xml.com
    ↓
Run smoke tests
```

**Manual deployment** (Windows):
```powershell
cd F:\AI\.claudeInternal\121XML_Deploy\121XML
.\xml.ps1 deploy staging
```

Expected output:
```
== Deploying to staging...
✓ SSH connection verified
== Backing up staging...
✓ Backup saved: backups\staging-backup-20261001-143022.tar.gz (1.24 MB)
== Running smoke test on https://staging.121xml.com...
✓ OK 200 /
✓ OK 200 /sitemap.xml
✓ OK 200 /robots.txt
✓ All smoke tests passed
```

### 3. Production Deployment

**Requirements**:
1. Approval file: `APPROVALS/v<VERSION>.md`
2. Approval from QA + RK (written in file)
3. Commit message contains `[deploy:prod]`

**Manual deployment** (GitHub Actions only):
1. Go to https://github.com/rashadkhan121/121XML/actions
2. Select "Deploy 121XML" workflow
3. Click "Run workflow"
4. Select "production" as target
5. Select "deploy" as action
6. Click "Run workflow"

**Commit-based deployment**:
```bash
git tag -a v1.0.1 -m "Release 1.0.1"
git commit --allow-empty -m "Trigger production deployment [deploy:prod]"
git push origin main
```

Expected flow:
```
Approval check
    ↓
SSH connection verified
    ↓
Backup current production
    ↓
Deploy new content to /home/xml/public_html
    ↓
Set permissions (755 dirs, 644 files)
    ↓
Run smoke tests
    ↓
Success notification
```

## Backup Strategy

### Automatic Backups
Every deployment creates a backup automatically:
- Timestamp: `YYYYMMDD-HHMMSS`
- Format: tar.gz
- Location on server: `/home/xml/xml_backups/`
- Local cache: `./backups/`

### Backup Naming
- `staging-backup-20261001-143022.tar.gz` - Staging backup
- `prod-backup-20261001-150000.tar.gz` - Production backup

### Manual Backup
```powershell
.\xml.ps1 backup staging
.\xml.ps1 backup production
```

### Backup Size Estimates
- Typical XML content: 5-50 MB
- With documentation: 50-200 MB
- Historical backups: Keep ~10 recent backups

## Rollback Procedures

### Immediate Rollback
If production deployment goes wrong:

```powershell
.\xml.ps1 rollback production
```

Automatically restores the most recent backup.

### Specific Backup Rollback
```powershell
.\xml.ps1 rollback production backups\prod-backup-20261001-140000.tar.gz
```

### Remote Rollback (via SSH)
```bash
ssh -i ~/.ssh/121connect_deploy -p 19199 xml@172.241.29.6
cd /home/xml/xml_backups
ls -lth prod-backup-*.tar.gz | head -5
tar -xzf prod-backup-20261001-140000.tar.gz -C /home/xml/public_html
```

## Smoke Testing

### What Gets Tested
```
GET https://121xml.com/
GET https://121xml.com/sitemap.xml
GET https://121xml.com/robots.txt
```

### Expected Results
- All requests return HTTP 200
- Response time < 5 seconds
- Content is served (non-empty body)

### Manual Smoke Test
```powershell
.\xml.ps1 smoke production
```

### Full Health Check
```bash
curl -v https://121xml.com/
curl -I https://staging.121xml.com/
curl https://121xml.com/api/v1/status
```

## Version Management

### VERSION File
Located at repository root: `./VERSION`
- Format: `X.Y.Z` (semantic versioning)
- Current: `1.0.0`
- Update before production deployments

### Release Tagging
```bash
# After updating VERSION file
git add VERSION
git commit -m "Bump version to 1.0.1"
git tag -a v1.0.1 -m "Release 1.0.1 - Update schemas"
git push origin main --tags
```

### Approval File Naming
Must match version:
- `APPROVALS/v1.0.1.md` for version 1.0.1
- Contains approval signatures and deployment details

## GitHub Secrets Setup

### Adding the SSH Key to GitHub

1. **Encode SSH key**:
   ```powershell
   $key = Get-Content "C:\Users\Owner\.ssh\121connect_deploy" -Raw
   $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($key))
   Set-Clipboard -Value $encoded
   ```

2. **Add to GitHub**:
   - Go to https://github.com/rashadkhan121/121XML
   - Settings → Secrets and variables → Actions
   - New repository secret
   - Name: `XML_DEPLOY_KEY`
   - Value: Paste encoded key

3. **Verify**:
   - GitHub Actions will use the secret automatically
   - Key is never logged or displayed
   - Expires only when changed

## Troubleshooting

### Common Issues

#### "SSH key not found"
```powershell
# Check key path
Test-Path "C:\Users\Owner\.ssh\121connect_deploy"

# Check key format
Get-Content "C:\Users\Owner\.ssh\121connect_deploy" | Select-Object -First 1
# Should output: -----BEGIN RSA PRIVATE KEY-----
```

#### "SSH connection refused"
```powershell
# Verify host is reachable
Test-NetConnection -ComputerName 172.241.29.6 -Port 19199

# Verify key is authorized on server
ssh -i "C:\Users\Owner\.ssh\121connect_deploy" -p 19199 xml@172.241.29.6 "cat ~/.ssh/authorized_keys | wc -l"
```

#### "Deployment timeout"
- Check network connectivity
- Verify remote disk has space: `ssh ... "df -h /home/xml"`
- Check backup size: if >500MB, may be slow

#### "GitHub Actions secret not working"
- Verify secret exists: Settings → Secrets → XML_DEPLOY_KEY
- Regenerate SSH key and update secret
- Re-run workflow after update

### Debug Mode

Enable verbose logging:

**PowerShell**:
```powershell
$VerbosePreference = "Continue"
.\xml.ps1 deploy staging -Verbose
```

**GitHub Actions**:
Add to workflow to enable debug logging:
```yaml
env:
  ACTIONS_STEP_DEBUG: true
```

## Security Considerations

### SSH Key Management
- Private key stored locally: `C:\Users\Owner\.ssh\121connect_deploy`
- Public key authorized on HostArmada
- Never commit private key to Git
- Key in `.gitignore` by default
- GitHub Secret is base64-encoded copy

### Access Control
- Only authorized users can deploy
- GitHub branch protection requires PR reviews
- Production deployments require explicit approval file
- All deployments logged with timestamps

### Data Protection
- All backups stored with restricted permissions (700)
- Backups kept locally for 30 days
- Remote backups kept on HostArmada (maintenance: @James)
- All SSH connections use port 19199 (non-standard)

## Performance & Limits

### Typical Deployment Times
- Staging: 10-20 seconds
- Production: 15-30 seconds
- Backup: 5-15 seconds
- Smoke tests: 5-10 seconds

### Size Limits
- Content max size: 1 GB (practical: 100 MB)
- Single file max: 500 MB
- Backup retention: ~10 files local, unlimited remote

### Network Requirements
- Stable internet connection (uploads 1-5 Mbps)
- SSH port 19199 must be accessible
- HTTPS for smoke tests must be enabled

## Monitoring & Maintenance

### Weekly Checks
- `git log --oneline -10` - Recent deployments
- GitHub Actions status - All workflows passing
- `.\xml.ps1 smoke production` - Live site health

### Monthly Maintenance
- Verify SSH key is still authorized
- Check backup storage usage: `ssh ... "du -sh ~/xml_backups"`
- Review DEPLOY_LOG.md for any issues
- Clean up old backups (keep last 10)

### Quarterly Review
- Update documentation
- Test full rollback procedure
- Verify approval gate process
- Update version numbers for releases

## References

- **Deployment repo**: https://github.com/rashadkhan121/121XML
- **SSH key path**: `C:\Users\Owner\.ssh\121connect_deploy`
- **HostArmada**: 172.241.29.6:19199
- **Staging URL**: https://staging.121xml.com
- **Production URL**: https://121xml.com
- **GitHub Secrets**: XML_DEPLOY_KEY
- **Approval files**: APPROVALS/v*.md

## Support & Escalation

- **Script issues**: vCIO (Jim) - PowerShell script debugging
- **SSH/host issues**: @James (DevOps) - HostArmada access
- **Content validation**: @PM (Product) - XML schema validation
- **Approvals**: RK (CEO) - Production deployment authorization

---

**Document Version**: 1.0
**Last Updated**: 2026-10-01
**Owner**: vCIO (Jim)
**Status**: Active
