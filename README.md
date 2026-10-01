# 121XML Deployment Automation

Automated deployment pipeline for 121XML content to HostArmada (172.241.29.6).

## Quick Start

### 1. Setup

```bash
# Clone the repo
git clone https://github.com/rashadkhan121/121XML.git
cd 121XML

# Copy environment template
cp .env.example .env

# Edit .env with your HostArmada credentials
# - XML_SSH_KEY: path to your SSH private key (e.g., C:\Users\Owner\.ssh\121connect_deploy)
# - XML_SSH_HOST, XML_SSH_PORT, XML_SSH_USER: connection details
```

### 2. Deployment via PowerShell (Windows)

```powershell
# Test SSH connection
Test-Path C:\Users\Owner\.ssh\121connect_deploy

# Deploy to staging
.\xml.ps1 deploy staging

# Deploy to production (requires approval)
.\xml.ps1 deploy production

# Create backup
.\xml.ps1 backup staging

# Rollback to previous version
.\xml.ps1 rollback production

# Run smoke test
.\xml.ps1 smoke staging
```

### 3. GitHub Actions CI/CD

#### Automatic deployments:
- **Staging**: Automatically deploys on every push to `main`
- **Production**: Requires:
  1. Explicit approval file at `APPROVALS/v<VERSION>.md`
  2. Commit message containing `[deploy:prod]`

#### Manual deployments:
Use GitHub Actions "Run workflow" to manually:
- Deploy to staging or production
- Create backups
- Run smoke tests
- Rollback to previous version

## File Structure

```
121XML/
├── content/              # Website/XML content to deploy
├── .github/
│   └── workflows/
│       └── deploy.yml    # GitHub Actions CI/CD pipeline
├── APPROVALS/           # Deployment approval gates (for production)
│   └── v*.md            # Approval files (RK + QA sign-off required)
├── backups/             # Local backup snapshots
├── xml.ps1              # Main deployment script (PowerShell)
├── .env.example         # Environment configuration template
├── README.md            # This file
├── VERSION              # Current version number
└── DEPLOY_NOTES.md      # Detailed deployment documentation
```

## SSH Configuration

The deployment uses SSH key authentication (no passwords):

1. **SSH Key Location**: `C:\Users\Owner\.ssh\121connect_deploy` (Windows)
2. **HostArmada Accounts**:
   - Host: `172.241.29.6`
   - Port: `19199`
   - User: `xml` (for 121XML)
3. **Public Key**: Must be authorized in cPanel > SSH Access

### Troubleshooting SSH

```powershell
# Test SSH connection manually
ssh -i C:\Users\Owner\.ssh\121connect_deploy -p 19199 xml@172.241.29.6 "echo 'Connected'"

# Check key permissions
ls -la C:\Users\Owner\.ssh\121connect_deploy
```

## Deployment Flow

### Staging Deployment (Automatic on push)

```
Push to main
    ↓
GitHub Actions triggered
    ↓
Validate content (XML syntax, required files)
    ↓
Create backup of current staging
    ↓
Sync new content to staging
    ↓
Run smoke tests
    ↓
Email notifications
```

### Production Deployment (Manual with approval)

```
Request production deployment
    ↓
Check approval gate (APPROVALS/v*.md required)
    ↓
GitHub Actions validates approval
    ↓
Create backup of current production
    ↓
Sync new content to production
    ↓
Run smoke tests
    ↓
Email notifications
```

## Approval Gate (Production Only)

Before production deployment, create `APPROVALS/v<VERSION>.md`:

```markdown
# Approval for 121XML v1.2.3

## Where
HostArmada public_html 121xml.com

## When
2026-10-01T14:30:00Z

## Who
- QA: Sarah Chen (signed off 2026-10-01)
- RK: Rashad Khan (approval verified)

## What Changed
- Updated XML schemas for 2026 spec
- Fixed encoding issues in UTF-8 content
- Added new financial transaction types

## Risk Assessment
- Low risk: content-only changes
- No schema breaking changes
- Tested on staging for 5 days
```

**Required**: Both QA sign-off and RK approval in the file before production deploy.

## Backup & Rollback

### Automatic Backups
- Every deployment creates a backup before syncing
- Backups stored on HostArmada: `/home/xml/xml_backups/`
- Local cache in `./backups/` after download

### Rollback
```powershell
# Rollback to most recent backup
.\xml.ps1 rollback production

# Rollback to specific backup
.\xml.ps1 rollback production backups\prod-backup-20261001-143000.tar.gz
```

### Manual Backup
```powershell
# Create a backup without deploying
.\xml.ps1 backup staging
.\xml.ps1 backup production
```

## Smoke Tests

Automated tests run after every deployment to verify:
- Homepage responds with HTTP 200
- XML files are accessible
- Core URLs are reachable
- No 404 or 500 errors

### Manual Smoke Test
```powershell
.\xml.ps1 smoke staging
.\xml.ps1 smoke production
```

## GitHub Secrets Configuration

The following secrets must be configured in GitHub for CI/CD:

1. **`XML_DEPLOY_KEY`** - SSH private key (base64 encoded)
   ```bash
   # Encode the key for GitHub Secrets
   cat C:\Users\Owner\.ssh\121connect_deploy | base64 | clip
   # Paste into GitHub Secrets UI
   ```

2. In GitHub repo settings:
   - Settings → Secrets and variables → Actions
   - Add secret `XML_DEPLOY_KEY` with base64-encoded SSH private key

## Commands Reference

| Command | Usage | Effect |
|---------|-------|--------|
| `deploy staging` | Manual or automatic | Deploy content to staging environment |
| `deploy production` | Manual only (requires approval) | Deploy content to production |
| `backup staging` | Manual | Backup staging environment |
| `backup production` | Manual | Backup production environment |
| `smoke staging` | Manual | Test staging site health |
| `smoke production` | Manual | Test production site health |
| `rollback staging` | Manual | Restore most recent staging backup |
| `rollback production` | Manual | Restore most recent production backup |

## Monitoring & Logs

### GitHub Actions
- View deployment logs: https://github.com/rashadkhan121/121XML/actions
- Each workflow run shows:
  - Test results
  - SSH connection status
  - Backup timestamps
  - Deployment status
  - Smoke test results

### Remote Logs
Logs on HostArmada:
```bash
# SSH into HostArmada
ssh -i ~/.ssh/121connect_deploy -p 19199 xml@172.241.29.6

# Check deployment log
cat /home/xml/public_html/.deploy-log
cat /home/xml/staging.121xml.com/.deploy-log
```

## Troubleshooting

### SSH Connection Fails
```powershell
# 1. Check key file exists
Test-Path C:\Users\Owner\.ssh\121connect_deploy

# 2. Check key is not encrypted (should start with -----BEGIN RSA PRIVATE KEY-----)
Get-Content C:\Users\Owner\.ssh\121connect_deploy | head -1

# 3. Verify key is authorized on server
ssh -i C:\Users\Owner\.ssh\121connect_deploy -p 19199 xml@172.241.29.6 "cat ~/.ssh/authorized_keys"

# 4. Check port is correct
Test-NetConnection -ComputerName 172.241.29.6 -Port 19199
```

### Deployment Stuck or Failed
```powershell
# Check remote disk space
ssh -i C:\Users\Owner\.ssh\121connect_deploy -p 19199 xml@172.241.29.6 "df -h /home/xml"

# Check if paths exist
ssh -i C:\Users\Owner\.ssh\121connect_deploy -p 19199 xml@172.241.29.6 "ls -la /home/xml/"

# Check latest deployment timestamp
ssh -i C:\Users\Owner\.ssh\121connect_deploy -p 19199 xml@172.241.29.6 "tail -20 /home/xml/public_html/.deploy-log"
```

### GitHub Actions Secrets Not Working
1. Regenerate SSH key pair
2. Authorize new public key in cPanel > SSH Access
3. Encode new private key and update `XML_DEPLOY_KEY` secret
4. Re-run workflow

## References

- **HostArmada Control Panel**: cPanel username `xml`
- **SSH Key Management**: `C:\Users\Owner\.ssh\121connect_deploy`
- **GitHub Org**: https://github.com/rashadkhan121
- **121 Group Infrastructure**: https://github.com/rashadkhan121/121-GitHub-Infra

## Support

For issues, contact:
- **Deployment Questions**: @James (DevOps)
- **Content Questions**: @PM (Product)
- **Architecture**: vCTO (Jim)
- **Approvals**: RK (CEO)

---

**Last Updated**: 2026-10-01
**Version**: 1.0.0
**Status**: Production Ready
