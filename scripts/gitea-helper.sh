#!/usr/bin/env bash
# Gitea Helper Script
# Usage: source this script or run individual functions

# Skill directory (auto-detected from script location)
GITEA_SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITEA_SETUP_SCRIPT="${GITEA_SKILL_DIR}/scripts/setup.sh"

# Configuration paths
CONFIG_DIR="${HOME}/.config/gitea"
CONFIG_FILE="${CONFIG_DIR}/config"
TOKEN_FILE="${CONFIG_DIR}/token"

# Load configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi

    # Defaults (empty if not configured - setup required)
    GITEA_URL="${GITEA_URL:-}"
    GITEA_USERNAME="${GITEA_USERNAME:-}"
    GIT_EMAIL="${GIT_EMAIL:-}"
    GITEA_LOGIN="${GITEA_LOGIN:-$GITEA_USERNAME}"
}

# Initialize on load
load_config

# Require configuration check
require_config() {
    if [ -z "$GITEA_URL" ]; then
        echo "Error: Gitea not configured. Run setup first:" >&2
        echo "  $GITEA_SETUP_SCRIPT" >&2
        return 1
    fi
    return 0
}

# API URL (set after config loaded)
GITEA_API="${GITEA_URL}/api/v1"

# Parse JSON field (jq fallback using node or grep)
parse_json_field() {
    local json="$1"
    local field="$2"

    if command -v jq &>/dev/null; then
        echo "$json" | jq -r ".$field" 2>/dev/null
        return
    fi

    if command -v node &>/dev/null; then
        echo "$json" | node -e "
            let d='';process.stdin.on('data',c=>d+=c);
            process.stdin.on('end',()=>{try{console.log(JSON.parse(d)['$field']||'')}catch(e){console.log('')}});
        " 2>/dev/null
        return
    fi

    echo "$json" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*":.*"\(.*\)"/\1/' 2>/dev/null
}

# Parse JSON array for repo listing
parse_repo_list() {
    local json="$1"

    if command -v jq &>/dev/null; then
        echo "$json" | jq -r '.[] | "\(.name)\t\(.clone_url)\t\(.private)"' 2>/dev/null
        return
    fi

    if command -v node &>/dev/null; then
        echo "$json" | node -e "
            let d='';process.stdin.on('data',c=>d+=c);
            process.stdin.on('end',()=>{
                try{
                    JSON.parse(d).forEach(r=>console.log(r.name+'\t'+r.clone_url+'\t'+r.private));
                }catch(e){}
            });
        " 2>/dev/null
        return
    fi

    echo "(JSON parsing requires jq or node)"
}

# Parse JSON array for PR listing (reads from stdin)
parse_pr_list() {
    if command -v jq &>/dev/null; then
        jq -r '.[] | "#\(.number)\t\(.title)\t\(.state)\t\(.user.login)\t\(.created_at)"' 2>/dev/null
        return
    fi

    if command -v node &>/dev/null; then
        node -e "
            let d='';process.stdin.on('data',c=>d+=c);
            process.stdin.on('end',()=>{
                try{
                    JSON.parse(d).forEach(p=>console.log('#'+p.number+'\t'+p.title+'\t'+p.state+'\t'+p.user.login+'\t'+p.created_at));
                }catch(e){}
            });
        " 2>/dev/null
        return
    fi

    cat > /dev/null
    echo "(JSON parsing requires jq or node)"
}

# Get Gitea token from secure storage
get_gitea_token() {
    require_config || return 1

    if [ -n "$GITEA_TOKEN" ]; then
        echo "$GITEA_TOKEN"
    elif [ -f "$TOKEN_FILE" ]; then
        cat "$TOKEN_FILE"
    elif [ -f ~/.gitea-token ]; then
        cat ~/.gitea-token
    else
        echo "Error: No Gitea token found." >&2
        echo "Run setup: $GITEA_SETUP_SCRIPT" >&2
        return 1
    fi
}

# Get current Gitea URL
get_gitea_url() {
    echo "$GITEA_URL"
}

# Get current username
get_gitea_username() {
    echo "${GITEA_LOGIN:-$GITEA_USERNAME}"
}

# Check if skill is configured
gitea_check_config() {
    local missing=0

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Configuration file not found: $CONFIG_FILE"
        missing=1
    fi

    if [ ! -f "$TOKEN_FILE" ]; then
        echo "API token file not found: $TOKEN_FILE"
        missing=1
    fi

    if [ "$missing" -eq 1 ]; then
        echo ""
        echo "Run setup: $GITEA_SETUP_SCRIPT"
        return 1
    fi

    echo "Configuration OK"
    echo "  Gitea URL:    $GITEA_URL"
    echo "  Username:     $GITEA_USERNAME"
    echo "  Email:        $GIT_EMAIL"
    echo "  Token:        ****$(cat "$TOKEN_FILE" | tail -c 4)"
    return 0
}

# Configure git with settings from config (IDE-compatible)
gitea_configure_git() {
    if [ -z "$GITEA_USERNAME" ] || [ -z "$GIT_EMAIL" ]; then
        echo "Error: Configuration not found. Run setup first." >&2
        echo "  $GITEA_SETUP_SCRIPT" >&2
        return 1
    fi

    git config --global user.name "$GITEA_USERNAME"
    git config --global user.email "$GIT_EMAIL"
    git config credential.helper store

    echo "Git configured successfully"
    echo "  Username: $GITEA_USERNAME"
    echo "  Email: $GIT_EMAIL"
    echo "  Credential helper: store (IDE-compatible)"
    echo ""
    echo "Note: Git credentials (for push/pull) are separate from API token (for repo management)"
}

# Create a new repository on Gitea
# Usage: gitea_create_repo <name> [description] [private:true/false]
gitea_create_repo() {
    local name="$1"
    local description="${2:-}"
    local private="${3:-true}"
    local token

    if [ -z "$name" ]; then
        echo "Usage: gitea_create_repo <name> [description] [private:true/false]" >&2
        return 1
    fi

    token=$(get_gitea_token) || return 1

    curl -s -X POST "${GITEA_API}/user/repos" \
        -H "Authorization: token ${token}" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"${name}\",
            \"description\": \"${description}\",
            \"private\": ${private},
            \"auto_init\": true
        }"
}

# List all user repositories
gitea_list_repos() {
    local token
    token=$(get_gitea_token) || return 1

    local result
    result=$(curl -s "${GITEA_API}/user/repos" -H "Authorization: token ${token}")
    parse_repo_list "$result"
}

# Get repository information
# Usage: gitea_repo_info <owner> <repo>
gitea_repo_info() {
    local owner="${1:-$(get_gitea_username)}"
    local repo="$2"
    local token

    if [ -z "$repo" ]; then
        if [ -z "$owner" ]; then
            echo "Usage: gitea_repo_info <owner> <repo>" >&2
            echo "   or: gitea_repo_info <repo>  (uses configured username)" >&2
            return 1
        fi
        # If only one arg, treat it as repo name
        repo="$owner"
        owner=$(get_gitea_username)
    fi

    token=$(get_gitea_token) || return 1

    curl -s "${GITEA_API}/repos/${owner}/${repo}" \
        -H "Authorization: token ${token}"
}

# Delete a repository (use with caution!)
# Usage: gitea_delete_repo <owner> <repo>
gitea_delete_repo() {
    local owner="${1:-}"
    local repo="${2:-}"
    local token

    if [ -z "$repo" ]; then
        if [ -z "$owner" ]; then
            echo "Usage: gitea_delete_repo <owner> <repo>" >&2
            echo "   or: gitea_delete_repo <repo>  (uses configured username)" >&2
            return 1
        fi
        # If only one arg, treat it as repo name
        repo="$owner"
        owner=$(get_gitea_username)
    fi

    token=$(get_gitea_token) || return 1

    echo "WARNING: This will permanently delete ${owner}/${repo}"
    read -p "Type the repository name to confirm: " confirm

    if [ "$confirm" = "$repo" ]; then
        curl -s -X DELETE "${GITEA_API}/repos/${owner}/${repo}" \
            -H "Authorization: token ${token}"
        echo "Repository deleted"
    else
        echo "Deletion cancelled"
        return 1
    fi
}

# Initialize a new project and push to Gitea
# Usage: gitea_init_project <repo-name> [description]
gitea_init_project() {
    local name="$1"
    local description="${2:-}"
    local username

    if [ -z "$name" ]; then
        echo "Usage: gitea_init_project <repo-name> [description]" >&2
        return 1
    fi

    username=$(get_gitea_username)
    if [ -z "$username" ]; then
        echo "Error: Username not configured. Run setup first." >&2
        return 1
    fi

    # Create remote repo
    echo "Creating remote repository..."
    gitea_create_repo "$name" "$description" "true" || return 1

    # Initialize local repo if needed
    if [ ! -d .git ]; then
        git init
    fi

    # Add remote
    local remote_url="${GITEA_URL}/${username}/${name}.git"
    git remote add origin "$remote_url" 2>/dev/null || \
        git remote set-url origin "$remote_url"

    echo ""
    echo "Remote configured: $remote_url"
    echo "Run 'git add . && git commit -m \"Initial commit\" && git push -u origin main' to push"
}

# Verify token is working
gitea_verify_token() {
    local token
    token=$(get_gitea_token) || return 1

    local result
    result=$(curl -s "${GITEA_API}/user" -H "Authorization: token ${token}")

    local login
    login=$(parse_json_field "$result" "login")
    if [ -n "$login" ] && [ "$login" != "null" ]; then
        echo "Token valid for user: $login"
        echo "Instance: $GITEA_URL"
        return 0
    else
        echo "Token verification failed: $result" >&2
        return 1
    fi
}

# Clone a repository from the configured Gitea instance
# Usage: gitea_clone <repo> [owner]
gitea_clone() {
    local repo="$1"
    local owner="${2:-$(get_gitea_username)}"

    if [ -z "$repo" ]; then
        echo "Usage: gitea_clone <repo> [owner]" >&2
        return 1
    fi

    git clone "${GITEA_URL}/${owner}/${repo}.git"
}

# ========================================
# Pull Request Management
# ========================================

# List pull requests for a repository
# Usage: gitea_list_prs [OWNER] REPO [STATE]
gitea_list_prs() {
    local owner="${1:-}"
    local repo="${2:-}"
    local state="${3:-open}"
    local token

    if [ -z "$repo" ]; then
        if [ -z "$owner" ]; then
            echo "Usage: gitea_list_prs [OWNER] REPO [STATE]" >&2
            echo "   STATE: open (default), closed, all" >&2
            return 1
        fi
        # If only one arg, treat as repo name
        repo="$owner"
        owner=$(get_gitea_username)
    fi

    token=$(get_gitea_token) || return 1

    curl -s "${GITEA_API}/repos/${owner}/${repo}/pulls?state=${state}&limit=50" \
        -H "Authorization: token ${token}" | parse_pr_list
}

# Get details for a single pull request
# Usage: gitea_get_pr [OWNER] REPO INDEX
gitea_get_pr() {
    local owner="${1:-}"
    local repo="${2:-}"
    local index="${3:-}"
    local token

    if [ -z "$index" ]; then
        if [ -n "$repo" ] && [ -z "$index" ]; then
            # Two args: repo and index
            index="$repo"
            repo="$owner"
            owner=$(get_gitea_username)
        else
            echo "Usage: gitea_get_pr [OWNER] REPO INDEX" >&2
            return 1
        fi
    fi

    token=$(get_gitea_token) || return 1

    curl -s "${GITEA_API}/repos/${owner}/${repo}/pulls/${index}" \
        -H "Authorization: token ${token}"
}

# Show diff for a pull request
# Usage: gitea_pr_diff [OWNER] REPO INDEX
gitea_pr_diff() {
    local owner="${1:-}"
    local repo="${2:-}"
    local index="${3:-}"
    local token

    if [ -z "$index" ]; then
        if [ -n "$repo" ] && [ -z "$index" ]; then
            index="$repo"
            repo="$owner"
            owner=$(get_gitea_username)
        else
            echo "Usage: gitea_pr_diff [OWNER] REPO INDEX" >&2
            return 1
        fi
    fi

    token=$(get_gitea_token) || return 1

    curl -s "${GITEA_API}/repos/${owner}/${repo}/pulls/${index}.diff" \
        -H "Authorization: token ${token}"
}

# Merge a pull request
# Usage: gitea_merge_pr [OWNER] REPO INDEX [MERGE_TYPE]
# MERGE_TYPE: merge (default), rebase, squash, rebase-merge
gitea_merge_pr() {
    local owner="${1:-}"
    local repo="${2:-}"
    local index="${3:-}"
    local merge_type="${4:-merge}"
    local token

    if [ -z "$index" ]; then
        if [ -n "$repo" ] && [ -z "$index" ]; then
            index="$repo"
            repo="$owner"
            owner=$(get_gitea_username)
            merge_type="${3:-merge}"
        else
            echo "Usage: gitea_merge_pr [OWNER] REPO INDEX [MERGE_TYPE]" >&2
            echo "   MERGE_TYPE: merge (default), rebase, squash, rebase-merge" >&2
            return 1
        fi
    fi

    token=$(get_gitea_token) || return 1

    curl -s -X POST "${GITEA_API}/repos/${owner}/${repo}/pulls/${index}/merge" \
        -H "Authorization: token ${token}" \
        -H "Content-Type: application/json" \
        -d "{
            \"Do\": \"${merge_type}\",
            \"delete_branch_after_merge\": true
        }"
}

# Close a pull request without merging
# Usage: gitea_close_pr [OWNER] REPO INDEX
gitea_close_pr() {
    local owner="${1:-}"
    local repo="${2:-}"
    local index="${3:-}"
    local token

    if [ -z "$index" ]; then
        if [ -n "$repo" ] && [ -z "$index" ]; then
            index="$repo"
            repo="$owner"
            owner=$(get_gitea_username)
        else
            echo "Usage: gitea_close_pr [OWNER] REPO INDEX" >&2
            return 1
        fi
    fi

    token=$(get_gitea_token) || return 1

    curl -s -X PATCH "${GITEA_API}/repos/${owner}/${repo}/pulls/${index}" \
        -H "Authorization: token ${token}" \
        -H "Content-Type: application/json" \
        -d '{"state": "closed"}'
}

# Tick the Renovate "rebase-check" checkbox on a PR.
# Editing the body to [x] tells Renovate to rebase/retry (or close-if-obsolete)
# on its next run. Used for superseded/conflicted Renovate PRs instead of closing.
gitea_pr_check_rebase() {
    local owner="${1:-}" repo="${2:-}" index="${3:-}" token

    # optional-owner shorthand, matching gitea_merge_pr/gitea_get_pr
    if [ -z "$index" ]; then
        if [ -n "$repo" ] && [ -z "$index" ]; then
            index="$repo"; repo="$owner"; owner=$(get_gitea_username)
        else
            echo "Usage: gitea_pr_check_rebase [OWNER] REPO INDEX" >&2
            return 1
        fi
    fi

    token=$(get_gitea_token) || return 1

    local pr body new_body payload http_code
    pr=$(curl -s "${GITEA_API}/repos/${owner}/${repo}/pulls/${index}" \
        -H "Authorization: token ${token}")

    if command -v jq &>/dev/null; then
        body=$(printf '%s' "$pr" | jq -r '.body // empty')
    elif command -v node &>/dev/null; then
        body=$(printf '%s' "$pr" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{process.stdout.write(JSON.parse(d).body||'')}catch(e){}})")
    else
        echo "gitea_pr_check_rebase requires jq or node" >&2; return 1
    fi

    if [ -z "$body" ]; then
        echo "PR #${index}: could not read body (check owner/repo/index)" >&2; return 1
    fi
    if printf '%s' "$body" | grep -q -- '- \[x\] <!-- rebase-check -->'; then
        echo "PR #${index}: rebase-check already ticked"; return 0
    fi
    if ! printf '%s' "$body" | grep -q -- '<!-- rebase-check -->'; then
        echo "PR #${index}: no rebase-check checkbox (not a Renovate PR?)" >&2; return 1
    fi

    new_body=$(printf '%s' "$body" | sed 's/- \[ \] <!-- rebase-check -->/- [x] <!-- rebase-check -->/')

    if command -v jq &>/dev/null; then
        payload=$(jq -n --arg b "$new_body" '{body:$b}')
    else
        payload=$(printf '%s' "$new_body" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(JSON.stringify({body:d})))")
    fi

    http_code=$(curl -s -o /dev/null -w '%{http_code}' \
        -X PATCH "${GITEA_API}/repos/${owner}/${repo}/pulls/${index}" \
        -H "Authorization: token ${token}" \
        -H "Content-Type: application/json" \
        -d "$payload")
    if [ "$http_code" -ge 200 ] 2>/dev/null && [ "$http_code" -lt 300 ] 2>/dev/null; then
        echo "PR #${index}: rebase-check ticked ✓"
    else
        echo "PR #${index}: rebase-check FAILED (HTTP ${http_code:-no response})" >&2
        return 1
    fi
}

# List all open Renovate bot PRs across repositories
# Usage: gitea_list_renovate_prs [OWNER]
gitea_list_renovate_prs() {
    local bot_user="${RENOVATE_USER:-renovate-bot}"
    local token page total_prs
    local tmpfile tmpfile_pr tmpfile_names tmpfile_out
    page=1
    total_prs=0

    token=$(get_gitea_token) || return 1
    tmpfile=$(mktemp)
    tmpfile_pr=$(mktemp)
    tmpfile_names=$(mktemp)
    tmpfile_out=$(mktemp)

    echo "Scanning repos for open PRs from ${bot_user}..."
    echo ""
    printf "%-30s %-6s %s\n" "REPOSITORY" "PR#" "TITLE"
    printf "%-30s %-6s %s\n" "----------" "---" "-----"

    while true; do
        curl -s "${GITEA_API}/repos/search?limit=50&page=${page}" \
            -H "Authorization: token ${token}" > "$tmpfile"

        local repo_count=$(jq -r '.data | length' "$tmpfile" 2>/dev/null)

        if [ -z "$repo_count" ] || [ "$repo_count" = "0" ] || [ "$repo_count" = "null" ]; then
            break
        fi

        # Extract repo names with open PRs to a file
        jq -r '.data[] | select(.open_pr_counter > 0) | .full_name' "$tmpfile" > "$tmpfile_names" 2>/dev/null

        while IFS= read -r full_name; do
            [ -z "$full_name" ] && continue

            curl -s "${GITEA_API}/repos/${full_name}/pulls?state=open&limit=50" \
                -H "Authorization: token ${token}" > "$tmpfile_pr"

            # Extract renovate-bot PRs to output file
            jq -r --arg bot "$bot_user" \
                '.[] | select(.user.login == $bot) | "\(.number)\t\(.title)"' \
                "$tmpfile_pr" > "$tmpfile_out" 2>/dev/null

            if [ -s "$tmpfile_out" ]; then
                local repo_short="${full_name#*/}"
                while IFS=$'\t' read -r num title; do
                    [ -z "$num" ] && continue
                    printf "%-30s #%-5s %s\n" "$repo_short" "$num" "$title"
                    total_prs=$((total_prs + 1))
                done < "$tmpfile_out"
            fi
        done < "$tmpfile_names"

        if [ "$repo_count" -lt 50 ]; then
            break
        fi
        page=$((page + 1))
    done

    rm -f "$tmpfile" "$tmpfile_pr" "$tmpfile_names" "$tmpfile_out"
    echo ""
    echo "Total: ${total_prs} open Renovate PRs"
}

# Print current configuration
gitea_config() {
    echo "Git-Gitea Skill Configuration"
    echo ""
    echo "Gitea Instance:"
    echo "  URL:        ${GITEA_URL}"
    echo "  Username:   ${GITEA_USERNAME}"
    echo "  Login:      ${GITEA_LOGIN}"
    echo ""
    echo "Git Identity:"
    echo "  Name:       $(git config --global user.name 2>/dev/null || echo 'not set')"
    echo "  Email:      $(git config --global user.email 2>/dev/null || echo 'not set')"
    echo ""
    echo "Files:"
    echo "  Config:     ${CONFIG_FILE}"
    echo "  Token:      ${TOKEN_FILE}"
    echo ""
    echo "To reconfigure, run:"
    echo "  $GITEA_SETUP_SCRIPT"
}

# Print help
gitea_help() {
    echo "Git-Gitea Skill Helper Functions"
    echo ""
    echo "SETUP:"
    echo "  Run initial setup:"
    echo "    $GITEA_SETUP_SCRIPT"
    echo ""
    echo "  This configures:"
    cat << 'EOF'
    • Gitea instance URL
    • Git identity (username, email)
    • API token for repository management
    • Git credentials for push/pull operations

AUTHENTICATION (two separate systems):
  1. Git credentials (for push/pull/clone via CLI or IDE):
     - Uses credential.helper store (~/.git-credentials)
     - Configured during setup

  2. API token (for repository management via API):
     - Stored in ~/.config/gitea/token
     - Used by these helper functions

FUNCTIONS:
  Configuration:
    gitea_config           - Show current configuration
    gitea_check_config     - Verify configuration is complete
    gitea_configure_git    - Apply git config from settings
    gitea_verify_token     - Test API token

  Repository Management:
    gitea_create_repo NAME [DESC] [PRIVATE] - Create new repository
    gitea_list_repos                        - List all your repositories
    gitea_repo_info [OWNER] REPO            - Get repository details
    gitea_delete_repo [OWNER] REPO          - Delete a repository
    gitea_init_project NAME [DESC]          - Create repo & configure local git
    gitea_clone REPO [OWNER]                - Clone a repository

  Pull Request Management:
    gitea_list_prs [OWNER] REPO [STATE]     - List PRs (state: open/closed/all)
    gitea_get_pr [OWNER] REPO INDEX         - Get PR details (JSON)
    gitea_pr_diff [OWNER] REPO INDEX        - Show PR diff
    gitea_merge_pr [OWNER] REPO INDEX [TYPE]- Merge PR (type: merge/rebase/squash)
    gitea_close_pr [OWNER] REPO INDEX       - Close PR without merging
    gitea_pr_check_rebase [OWNER] REPO INDEX- Tick Renovate rebase-check checkbox
    gitea_list_renovate_prs [OWNER]         - List all open Renovate bot PRs

EXAMPLES:
  gitea_create_repo my-project "A cool project" true
  gitea_list_repos
  gitea_init_project new-app "My new application"
  gitea_clone existing-repo
  gitea_repo_info my-project
  gitea_list_renovate_prs
  gitea_merge_pr Bill Grafana-docker 45
EOF
}

# If script is sourced, show available functions
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    if [ -f "$CONFIG_FILE" ]; then
        echo "Gitea helper loaded for: $GITEA_URL"
    else
        echo "Gitea helper loaded (not configured)"
        echo "Run setup: $GITEA_SETUP_SCRIPT"
    fi
    echo "Run 'gitea_help' for usage."
fi
