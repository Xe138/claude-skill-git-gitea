---
name: git-gitea
description: Manage local git repositories and remote Gitea instances. Use when creating repositories, configuring git, pushing code, managing remotes, or working with Gitea API. Triggers on git setup, repo creation, Gitea management, repository operations.
---

# Git & Gitea Repository Management Skill

Manage local git repositories and remote Gitea instances.

## Initial Setup

Find and run the setup script:

```bash
# Find skill location (may vary by installation)
SKILL_DIR=$(dirname "$(find ~/.claude/skills -name 'gitea-helper.sh' 2>/dev/null | head -1)")
${SKILL_DIR}/setup.sh
```

The setup wizard will prompt for:
- **Gitea URL** - Your Gitea instance (e.g., https://git.example.com)
- **Git username** - Name for commits
- **Git email** - Email for commits
- **API token** - For repository management via API (see required scopes below)
- **Gitea login/password** - For git push/pull operations

### Required API Token Scopes

Create your token at `<your-gitea-url>/user/settings/applications` with these scopes:

| Scope | Required | Purpose |
|-------|----------|---------|
| `write:user` | **Yes** | Create personal repositories |
| `write:repository` | **Yes** | Repository operations (settings, branches) |
| `read:user` | **Yes** | Verify token, get user info |
| `delete_repo` | Optional | Delete repositories via API |
| `write:issue` | **Yes** (for PRs) | Manage issues and pull requests |
| `write:organization` | Optional | Create/manage organization repos |

Configuration is stored in:
- `~/.config/gitea/config` - Instance and identity settings
- `~/.config/gitea/token` - API token (chmod 600)
- `~/.git-credentials` - Git credentials for IDE/CLI operations

## Authentication Architecture

Two separate authentication systems work together:

| Context | Purpose | Method | Storage |
|---------|---------|--------|---------|
| **Git push/pull** | Clone, push, pull via CLI or IDE | credential.helper store | ~/.git-credentials |
| **Gitea API** | Create/delete repos, manage settings | API Token (HTTP header) | ~/.config/gitea/token |

This design ensures:
- IDEs (VS Code, JetBrains, etc.) work seamlessly with git operations
- API operations use scoped, revocable tokens
- Credentials and tokens are stored separately with proper permissions

## Using the Helper Functions

Source the helper script (auto-detects paths):
```bash
source "$(find ~/.claude/skills -name 'gitea-helper.sh' 2>/dev/null | head -1)"
```

Or if you know the skill directory:
```bash
source ~/.claude/skills/claude-skill-git-gitea/scripts/gitea-helper.sh
```

### Available Functions

**Configuration:**
- `gitea_config` - Show current configuration
- `gitea_check_config` - Verify configuration is complete
- `gitea_configure_git` - Apply git config from settings
- `gitea_verify_token` - Test API token

**Repository Management:**
- `gitea_create_repo NAME [DESC] [PRIVATE]` - Create new repository
- `gitea_list_repos` - List all your repositories
- `gitea_repo_info [OWNER] REPO` - Get repository details
- `gitea_delete_repo [OWNER] REPO` - Delete a repository
- `gitea_init_project NAME [DESC]` - Create repo & configure local git
- `gitea_clone REPO [OWNER]` - Clone a repository

**IMPORTANT - Repository Visibility:** When creating a new repository, ALWAYS ask the user whether it should be **private** or **public** if not explicitly specified. Never assume visibility - prompt with options like "Should this repository be private or public?"

**Pull Request Management:**
- `gitea_list_prs [OWNER] REPO [STATE]` - List pull requests (state: open/closed/all)
- `gitea_get_pr [OWNER] REPO INDEX` - Get PR details (JSON)
- `gitea_pr_diff [OWNER] REPO INDEX` - Show PR diff
- `gitea_merge_pr [OWNER] REPO INDEX [TYPE]` - Merge a pull request (type: merge/rebase/squash)
- `gitea_close_pr [OWNER] REPO INDEX` - Close PR without merging
- `gitea_list_renovate_prs [OWNER]` - List all open Renovate bot PRs across repos

## Direct API Usage

If needed, make API calls directly using the stored token:

```bash
# Read token
TOKEN=$(cat ~/.config/gitea/token)

# Load config for URL
source ~/.config/gitea/config

# Make API call
curl -s "${GITEA_URL}/api/v1/user/repos" \
  -H "Authorization: token ${TOKEN}"
```

## Common Workflows

### Create and Push New Project
```bash
source "$(find ~/.claude/skills -name 'gitea-helper.sh' 2>/dev/null | head -1)"
gitea_init_project my-new-project "Project description"
git add .
git commit -m "Initial commit"
git push -u origin main
```

### Clone Existing Repository
```bash
source "$(find ~/.claude/skills -name 'gitea-helper.sh' 2>/dev/null | head -1)"
gitea_clone existing-repo
```

### List All Repositories
```bash
source "$(find ~/.claude/skills -name 'gitea-helper.sh' 2>/dev/null | head -1)"
gitea_list_repos
```

### Renovate PR Workflow

Process Renovate bot PRs that update Docker image versions across repositories.

**1. List all pending Renovate PRs:**
```bash
source "$(find ~/.claude/skills -name 'gitea-helper.sh' 2>/dev/null | head -1)"
gitea_list_renovate_prs
```

**2. Review a specific PR diff:**
```bash
gitea_pr_diff Bill Grafana-docker 45
```

**3. Merge an approved PR:**
```bash
gitea_merge_pr Bill Grafana-docker 45
```
Branches are automatically deleted after merge. Renovate recreates them as needed.

**4. Deploy to the target host:**
For deploying merged changes to Docker stacks on inkling/shellington, see the docker-compose-config skill's "Deploying Updates from Merged PRs" section.

**Environment variable:** Set `RENOVATE_USER` to override the default bot username (`renovate-bot`).

## Reconfiguring

To change any settings, re-run the setup script (or source the helper and run `gitea_help` to see the path):
```bash
# After sourcing helper, the path is shown in output
# Or find it directly:
$(dirname "$(find ~/.claude/skills -name 'gitea-helper.sh' 2>/dev/null | head -1)")/setup.sh
```

Existing values are shown as defaults - press Enter to keep them.

## Security Best Practices

1. **Token file permissions** - Setup script sets chmod 600 automatically
2. **Use minimal token scopes** - Only request permissions you need
3. **Rotate tokens periodically** - Regenerate API tokens every 90 days
4. **Separate concerns** - API token for management, git credentials for push/pull
5. **Never commit tokens** - Token files are in ~/.config, not in repos

## Troubleshooting

- **401 Unauthorized on API**: Token invalid or expired - regenerate in Gitea settings
- **403 Forbidden**: Token lacks required scope - check token permissions
- **Push authentication fails**: Run setup again to update git credentials
- **IDE can't push**: Ensure credential.helper store is configured

For detailed API reference, see [REFERENCE.md](REFERENCE.md).
