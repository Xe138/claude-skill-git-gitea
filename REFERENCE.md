# Gitea API Reference

Extended API reference for Gitea instances.

Base URL: `${GITEA_URL}/api/v1` (configured via setup script)

## Authentication Header

All authenticated requests require:
```
Authorization: token YOUR_TOKEN_HERE
```

## Repository Endpoints

### List repositories
```
GET /user/repos
GET /orgs/{org}/repos
GET /repos/search?q={query}
```

### Repository CRUD
```
POST   /user/repos                    # Create repo
GET    /repos/{owner}/{repo}          # Get repo info
PATCH  /repos/{owner}/{repo}          # Update repo
DELETE /repos/{owner}/{repo}          # Delete repo
```

### Repository operations
```
POST /repos/{owner}/{repo}/forks      # Fork repository
POST /repos/{owner}/{repo}/mirror-sync # Sync mirror
POST /repos/{owner}/{repo}/transfer   # Transfer ownership
```

## Branch Operations

```
GET    /repos/{owner}/{repo}/branches              # List branches
GET    /repos/{owner}/{repo}/branches/{branch}     # Get branch
DELETE /repos/{owner}/{repo}/branches/{branch}     # Delete branch
```

## Issues & Pull Requests

### Issues
```
GET  /repos/{owner}/{repo}/issues                  # List issues
POST /repos/{owner}/{repo}/issues                  # Create issue
GET  /repos/{owner}/{repo}/issues/{index}          # Get issue
PATCH /repos/{owner}/{repo}/issues/{index}         # Update issue
```

### Pull Requests
```
GET  /repos/{owner}/{repo}/pulls                   # List PRs
POST /repos/{owner}/{repo}/pulls                   # Create PR
GET  /repos/{owner}/{repo}/pulls/{index}           # Get PR
PATCH /repos/{owner}/{repo}/pulls/{index}          # Update PR
POST /repos/{owner}/{repo}/pulls/{index}/merge     # Merge PR
```

## Releases

```
GET  /repos/{owner}/{repo}/releases                # List releases
POST /repos/{owner}/{repo}/releases                # Create release
GET  /repos/{owner}/{repo}/releases/{id}           # Get release
DELETE /repos/{owner}/{repo}/releases/{id}         # Delete release
```

## User Management

```
GET /user                   # Get authenticated user
GET /users/{username}       # Get user profile
GET /user/repos             # List user repos
GET /user/orgs              # List user organizations
```

## Organization Operations

```
GET  /orgs/{org}            # Get organization
GET  /orgs/{org}/repos      # List org repos
POST /orgs/{org}/repos      # Create org repo
GET  /orgs/{org}/members    # List members
```

## Webhooks

```
GET    /repos/{owner}/{repo}/hooks              # List hooks
POST   /repos/{owner}/{repo}/hooks              # Create hook
GET    /repos/{owner}/{repo}/hooks/{id}         # Get hook
PATCH  /repos/{owner}/{repo}/hooks/{id}         # Update hook
DELETE /repos/{owner}/{repo}/hooks/{id}         # Delete hook
```

## Token Scopes

### Required Scopes for This Skill

| Scope | Required | Purpose |
|-------|----------|---------|
| `write:user` | **Yes** | Create personal repositories via API |
| `write:repository` | **Yes** | Repository operations (settings, branches) |
| `read:user` | **Yes** | Verify token, retrieve user info |
| `delete_repo` | Optional | Delete repositories via API |
| `write:issue` | Optional | Create/manage issues and pull requests |
| `write:organization` | Optional | Create/manage organization repositories |

### All Available Scopes

| Scope | Description |
|-------|-------------|
| `write:user` | Create repos, manage user settings |
| `read:user` | Read user profile |
| `write:repository` | Full control of repositories |
| `read:repository` | Read repository data |
| `write:organization` | Manage organizations |
| `read:organization` | Read org membership |
| `write:issue` | Create/edit issues and PRs |
| `read:issue` | Read issues |
| `write:package` | Manage packages |
| `read:package` | Read packages |
| `write:admin` | Admin operations |
| `read:admin` | Read admin data |
| `write:notification` | Manage notifications |
| `read:notification` | Read notifications |
| `delete_repo` | Delete repositories |

## Example: Create Repository with Full Options

```bash
# Load configuration
source ~/.config/gitea/config
TOKEN=$(cat ~/.config/gitea/token)

curl -X POST "${GITEA_URL}/api/v1/user/repos" \
  -H "Authorization: token ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-project",
    "description": "Project description",
    "private": true,
    "auto_init": true,
    "default_branch": "main",
    "gitignores": "Python",
    "license": "MIT",
    "readme": "Default",
    "trust_model": "default"
  }'
```

## Interactive API Documentation

Full Swagger documentation available at your instance:
`${GITEA_URL}/api/swagger`
