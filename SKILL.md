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

## Quick Reference

Source the helper first, then use these commands:

```bash
source ~/.claude/skills/claude-skill-git-gitea/scripts/gitea-helper.sh
```

| Task | Command |
|------|---------|
| List open PRs | `gitea_list_prs [OWNER] REPO` |
| Review PR diff | `gitea_pr_diff OWNER REPO INDEX` |
| Merge PR | `gitea_merge_pr OWNER REPO INDEX` |
| Tick rebase-check on PR | `gitea_pr_check_rebase OWNER REPO INDEX` |
| All Renovate PRs | `gitea_list_renovate_prs` |
| List repos | `gitea_list_repos` |
| Create repo | `gitea_create_repo NAME [DESC] [PRIVATE]` |
| Clone repo | `gitea_clone REPO [OWNER]` |
| PR details (JSON) | `gitea_get_pr [OWNER] REPO INDEX` |
| **Check instance health** | `gitea_health [OWNER/REPO]` |
| **Audit repo visibility + secrets** | `gitea_audit_visibility` |

## Important: Always Source the Helper First

When performing ANY Gitea operation, ALWAYS source the helper script as your first step rather than making raw curl/API calls. The helper functions handle authentication, JSON parsing (via jq/node with fallbacks), pagination, and formatted output.

Raw curl + manual JSON parsing is error-prone — especially on NixOS where shell quoting with nix-shell and inline Python/jq causes escaping issues.

**Anti-pattern (DO NOT DO THIS):**
```bash
# Wrong: raw curl + manual parsing = quoting nightmares
TOKEN=$(cat ~/.config/gitea/token)
curl -s -H "Authorization: token $TOKEN" ".../pulls" | python3 -c "..."
```

**Correct pattern:**
```bash
# Right: one-liner with full formatting
source ~/.claude/skills/claude-skill-git-gitea/scripts/gitea-helper.sh
gitea_list_prs Bill HomeAssistant-compose
```

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

**Instance Health & Audit:**
- `gitea_health [OWNER/REPO]` - Verify the instance is actually **serving**, not merely alive
- `gitea_audit_visibility` - List public vs private repos and scan public ones for secret-shaped files

## Checking Instance Health

**Do not trust the container healthcheck or `/api/healthz`.** On 2026-08-11 this
instance reported `(healthy)`, passed `/api/healthz` (both DB and cache pings), and had
three weeks of uptime — while **100% of HTTP git clones had been failing for 30 hours**.
A poisoned global `uploadpack.packObjectsHook` broke every `git upload-pack`; nothing in
the liveness surface reflected it. Renovate kept authenticating and failing, unnoticed.

Liveness probes test whether the process is running. They do not test whether it can do
its job. `gitea_health` performs a **real clone** — the only check that catches this class
of failure — plus verifies the private API is not exposed:

```bash
gitea_health                 # auto-picks a repo
gitea_health Bill/AI-Trader  # test a specific one
```

Returns non-zero if any check fails. When investigating a failure, get the server-side
error *rate* (an absolute count of zero proves health; a green healthcheck does not):

```bash
ssh <docker-host> "docker logs gitea --since 1h 2>&1 | grep -ciE '\[E\]|fatal'"
```

## Auditing Repository Visibility

```bash
gitea_audit_visibility
```

Catches two distinct problems: **visibility drift** (a repo you believe is private but
isn't — this found `Bill/phone-setup` public while it was documented as private) and
**secret-shaped files reachable without authentication**.

Filename matches are candidates, not confirmed leaks — inspect them. Two known-benign
examples on this instance: `Bill/actual/.env` (a comment saying no vars are needed) and
`Bill/obsidian-mcp-server/.npmrc` (`tag-version-prefix=""`).

It scans the **default branch only**. A secret committed and later deleted still lives in
history; check a clone with
`git log --all --diff-filter=A --name-only --pretty=format: | sort -u`.

**Pull Request Management:**
- `gitea_list_prs [OWNER] REPO [STATE]` - List pull requests (state: open/closed/all)
- `gitea_get_pr [OWNER] REPO INDEX` - Get PR details (JSON)
- `gitea_pr_diff [OWNER] REPO INDEX` - Show PR diff
- `gitea_merge_pr [OWNER] REPO INDEX [TYPE]` - Merge a pull request (type: merge/rebase/squash)
- `gitea_close_pr [OWNER] REPO INDEX` - Close PR without merging
- `gitea_pr_check_rebase [OWNER] REPO INDEX` - Tick the Renovate rebase-check checkbox (drives rebase/retry; use for superseded PRs instead of closing)
- `gitea_list_renovate_prs [OWNER]` - List all open Renovate bot PRs across repos

## Direct API Usage (Advanced - Prefer Helper Functions)

Only use direct API calls when the helper functions don't cover your use case:

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

### Renovate PR Review Rules

When reviewing a repo's Renovate PRs, sequence merges as follows:

1. **Version bump beats pin/digest re-pin.** If two PRs touch the same image and one
   bumps the version while another only re-pins the *old* version's digest, merge the
   version bump and **rebase-check** the re-pin (it's superseded). Do not merge it; do
   not close it.
2. **Minor/patch before major.** Within the same image, order lower-risk updates first.
   Major bumps and DB-engine major bumps (e.g. Postgres `pg_upgrade`) are hard warnings —
   surface them and get explicit acknowledgement before merging.
3. **Independent images** (different services) merge in any order.

**Superseded/remaining PRs:** tick the rebase-check box with `gitea_pr_check_rebase`.
Renovate reconciles or closes them on its next run. (Auto-mode blocks closing PRs the
agent didn't create, so closing is the wrong tool anyway.)

**Stale-`mergeable` quirk:** after merging a PR, Gitea may briefly report the next PR as
`mergeable:false` or return `{"message":"Please try again later"}` while it recomputes
the base. This is **not** a real conflict. Re-verify the target image line on the default
branch (`raw/docker-compose.yml`); if the line still matches the PR's "from" value, wait
a few seconds and retry the merge. Only treat it as a real conflict if the line diverged.

## Secrets in a repo (SOPS/age)

Standard way to keep credentials in any git repo without committing plaintext — and
the simplest way to hand an **AI agent a credential inside a git-controlled workspace**
(Cloudflare token, API key, DB password). Secrets are encrypted with SOPS + age; the
encrypted file is committed; any agent on a host whose age key is a recipient decrypts
it transparently.

Use the helper (operates on the current repo):
```bash
S=~/.claude/skills/claude-skill-git-gitea/scripts/sops-secrets.sh
"$S" init                              # once per repo: writes .sops.yaml + secrets/
"$S" add cloudflare CLOUDFLARE_API_TOKEN   # prompts for value; -> secrets/cloudflare.sops.yaml
"$S" view cloudflare                   # print decrypted
"$S" edit cloudflare                   # $EDITOR round-trip
"$S" rekey                             # re-encrypt all after editing .sops.yaml
git add .sops.yaml secrets/ && git commit -m "Add cloudflare credentials (encrypted)"
```

**Recipients — the multi-recipient standard, NEVER a single key:**
- **`bill`** (`age1ethpg…`) — Bill's user key: in his password manager and in soos's
  `keys.txt`, so an agent's plain `sops -d` on soos works with no setup. Always a
  recovery path.
- **the host(s) where agents run** — the `soos` host key, plus any other host the repo
  deploys to, so each self-decrypts with its own key.
- **one recovery host** (`inkling`) so no single host loss orphans the secret.

`init` defaults to `bill soos inkling`; pass aliases to change the set, e.g.
`sops-secrets.sh init bill inkling shellington` for a repo whose agents run on inkling.
Canonical pubkeys live in the script's `AGE_RECIPIENTS` table.

**How an agent reads a secret:** on any recipient host the private key is at
`~/.config/sops/age/keys.txt` (or the host SSH key), so
`sops -d secrets/foo.sops.yaml` — or `sops -d --extract '["KEY"]' secrets/foo.sops.yaml`
for one field — returns plaintext with no extra setup. Reference it from scripts;
never copy plaintext into the repo.

**Rules:**
- A secrets file MUST list ≥2 independent keys (`bill` + ≥1 host). A single-recipient
  file is one lost key away from being permanently undecryptable.
- SOPS-encrypted files are safe to commit, but keep repos holding secrets **private**;
  `gitea_audit_visibility` flags secret-shaped files exposed in public repos.
- To change the fleet recipient set, edit `AGE_RECIPIENTS` / `.sops.yaml`, then `rekey`.

## Reconfiguring

To change any settings, re-run the setup script (or source the helper and run `gitea_help` to see the path):
```bash
# After sourcing helper, the path is shown in output
# Or find it directly:
$(dirname "$(find ~/.claude/skills -name 'gitea-helper.sh' 2>/dev/null | head -1)")/setup.sh
```

Existing values are shown as defaults - press Enter to keep them.

## Security Best Practices

### Client-side (your tokens)

1. **Token file permissions** - Setup script sets chmod 600 automatically
2. **Use minimal token scopes** - Only request permissions you need
3. **Rotate tokens periodically** - Regenerate API tokens every 90 days
4. **Separate concerns** - API token for management, git credentials for push/pull
5. **Never commit tokens** - Token files are in ~/.config, not in repos

### Server-side (the instance's own secrets)

The items above protect *your user account*. They are not the secrets that get an
instance compromised. On 2026-08-11 an attacker used a valid **`INTERNAL_TOKEN`** to
reach `POST /api/internal/manager/add-logger`, turning Gitea's file-mode logger into an
arbitrary file write, poisoning `uploadpack.packObjectsHook`, and attempting RCE on the
next clone. That token was the install-time original — **never rotated in 3.4 years**.

1. **Never expose `/api/internal` through the reverse proxy.** Gitea calls these routes
   on itself via `LOCAL_ROOT_URL` (`localhost:3000`) and over the container network; they
   never legitimately traverse a public proxy. Deny the whole prefix at the edge. In
   nginx the deny must use `^~` so it outranks any `~ /api...` regex location:
   ```nginx
   location ^~ /api/internal { return 403; }
   ```
   `gitea_health` asserts this — it fails if `/api/internal/dummy` returns 200.

2. **Rotate `INTERNAL_TOKEN` on any suspicion, and on a schedule.** It is a bearer
   credential compared verbatim, sent in the **`X-Gitea-Internal-Auth`** header (not
   `Authorization`). Rotation is cheap and lossless — no data is encrypted with it:
   ```bash
   docker exec gitea gitea generate secret INTERNAL_TOKEN   # then write to app.ini
   ```
   Restart afterward, then verify push hooks still work (they call `/api/internal/hook/*`)
   by pushing a throwaway branch.

3. **Check whether `SECRET_KEY` is actually set.** If it is empty in `app.ini`, Gitea
   silently falls back to the hardcoded default `!#@FDEWREWR&*(` — upstream keeps that
   fallback deliberately because it cannot rotate an existing key. Everything encrypted
   at rest (**Actions secrets**, mirror credentials, 2FA seeds) is then protected by a
   constant published in the source, readable by anyone holding a copy of the database
   **or a database backup**.
   ```bash
   docker exec gitea grep '^SECRET_KEY' /data/gitea/conf/app.ini
   ```
   Setting a real key **invalidates existing encrypted values** — inventory them first
   (`select count(*) from two_factor;`, `from secret;`, `from mirror;`) and be ready to
   re-enter them. Rotate the underlying credentials too; assume they were exposed.

4. **Pin `REVERSE_PROXY_TRUSTED_PROXIES`.** A value of `*` trusts `X-Forwarded-For` from
   any source. Set it to the proxy's network (e.g. `172.19.0.0/16`).

5. **Treat plaintext secrets in "private" config repos as replicated secrets.** The
   convention of committing `app.ini` unencrypted to a private repo means *every clone,
   backup, and replicated dataset is a copy of every secret in it*. That is the most
   likely explanation for a leaked `INTERNAL_TOKEN` when no server-side exposure exists.

6. **The Actions runner mounts `/var/run/docker.sock`.** Anything that can run a workflow
   gets root on the Docker host. Keep registration disabled so outsiders cannot
   fork-and-PR into a workflow run, and prune stale runner registrations.

7. **Stay current.** 1.27.0 shipped breaking security fixes (hardened access checks,
   LFS proof-of-possession, path-traversal prevention in repo restore).

## Troubleshooting

- **401 Unauthorized on API**: Token invalid or expired - regenerate in Gitea settings
- **403 Forbidden**: Token lacks required scope - check token permissions
- **Push authentication fails**: Run setup again to update git credentials
- **IDE can't push**: Ensure credential.helper store is configured

For detailed API reference, see [REFERENCE.md](REFERENCE.md).
