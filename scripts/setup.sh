#!/usr/bin/env bash
# Git-Gitea Skill Setup Script
# Configures git identity, Gitea instance, and credentials

set -e

CONFIG_DIR="${HOME}/.config/gitea"
CONFIG_FILE="${CONFIG_DIR}/config"
TOKEN_FILE="${CONFIG_DIR}/token"
GIT_CREDENTIALS="${HOME}/.git-credentials"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Git-Gitea Skill Setup${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_section() {
    echo -e "\n${YELLOW}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Load existing configuration if present
load_existing_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# Prompt with default value
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local is_secret="${4:-false}"

    if [ -n "$default" ]; then
        if [ "$is_secret" = "true" ]; then
            echo -n "$prompt [****]: "
        else
            echo -n "$prompt [$default]: "
        fi
    else
        echo -n "$prompt: "
    fi

    if [ "$is_secret" = "true" ]; then
        read -s value
        echo ""
    else
        read value
    fi

    if [ -z "$value" ]; then
        value="$default"
    fi

    eval "$var_name=\"$value\""
}

# Validate URL format
validate_url() {
    local url="$1"
    if [[ "$url" =~ ^https?:// ]]; then
        return 0
    else
        return 1
    fi
}

# Validate email format
validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Parse JSON field (jq fallback using grep/sed or node)
parse_json_field() {
    local json="$1"
    local field="$2"

    # Try jq first
    if command -v jq &>/dev/null; then
        echo "$json" | jq -r ".$field" 2>/dev/null
        return
    fi

    # Try node
    if command -v node &>/dev/null; then
        echo "$json" | node -e "
            let data = '';
            process.stdin.on('data', chunk => data += chunk);
            process.stdin.on('end', () => {
                try {
                    const obj = JSON.parse(data);
                    console.log(obj['$field'] || '');
                } catch(e) { console.log(''); }
            });
        " 2>/dev/null
        return
    fi

    # Fallback: grep/sed for simple cases
    echo "$json" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*":.*"\(.*\)"/\1/' 2>/dev/null
}

# Test API token
test_api_token() {
    local url="$1"
    local token="$2"

    local response
    response=$(curl -s -w "\n%{http_code}" "${url}/api/v1/user" \
        -H "Authorization: token ${token}" 2>/dev/null)

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        local login
        login=$(parse_json_field "$body" "login")
        if [ -n "$login" ] && [ "$login" != "null" ]; then
            echo "$login"
            return 0
        fi
    fi
    return 1
}

# Validate token has required scopes
validate_token_scopes() {
    local url="$1"
    local token="$2"
    local missing_scopes=""

    # Test write:user scope (required for creating repos)
    local response
    response=$(curl -s "${url}/api/v1/user/repos" \
        -X POST \
        -H "Authorization: token ${token}" \
        -H "Content-Type: application/json" \
        -d '{"name":"__scope_test_delete_me__","private":true}' 2>/dev/null)

    if echo "$response" | grep -q "required=\[write:user\]"; then
        missing_scopes="${missing_scopes}write:user "
    elif echo "$response" | grep -q '"id"'; then
        # Repo was created, delete it
        curl -s -X DELETE "${url}/api/v1/repos/$(parse_json_field "$response" "owner" | head -1)/$(parse_json_field "$response" "name")" \
            -H "Authorization: token ${token}" >/dev/null 2>&1
        # Try alternate extraction if owner parsing failed
        local owner
        owner=$(echo "$response" | grep -o '"login":"[^"]*"' | head -1 | sed 's/"login":"\([^"]*\)"/\1/')
        if [ -n "$owner" ]; then
            curl -s -X DELETE "${url}/api/v1/repos/${owner}/__scope_test_delete_me__" \
                -H "Authorization: token ${token}" >/dev/null 2>&1
        fi
    fi

    # Test read:user scope
    response=$(curl -s "${url}/api/v1/user" \
        -H "Authorization: token ${token}" 2>/dev/null)

    if echo "$response" | grep -q "required=\[read:user\]"; then
        missing_scopes="${missing_scopes}read:user "
    fi

    # Return results
    if [ -n "$missing_scopes" ]; then
        echo "$missing_scopes"
        return 1
    fi
    return 0
}

# URL-encode a string
url_encode() {
    local string="$1"

    # Try node first
    if command -v node &>/dev/null; then
        node -e "console.log(encodeURIComponent('$string'))" 2>/dev/null
        return
    fi

    # Try python3
    if command -v python3 &>/dev/null; then
        python3 -c "import urllib.parse; print(urllib.parse.quote('$string', safe=''))" 2>/dev/null
        return
    fi

    # Fallback: basic encoding for common special chars
    echo "$string" | sed 's/%/%25/g; s/ /%20/g; s/!/%21/g; s/"/%22/g; s/#/%23/g; s/\$/%24/g; s/&/%26/g; s/'\''/%27/g; s/(/%28/g; s/)/%29/g; s/*/%2A/g; s/+/%2B/g; s/,/%2C/g; s/:/%3A/g; s/;/%3B/g; s/</%3C/g; s/=/%3D/g; s/>/%3E/g; s/?/%3F/g; s/@/%40/g; s/\[/%5B/g; s/\\/%5C/g; s/\]/%5D/g'
}

# Configure git credentials for the Gitea instance
configure_git_credentials() {
    local url="$1"
    local username="$2"
    local password="$3"

    # Extract host from URL
    local host
    host=$(echo "$url" | sed -E 's|https?://||' | sed 's|/.*||')

    # URL-encode username and password
    local encoded_username
    local encoded_password
    encoded_username=$(url_encode "$username")
    encoded_password=$(url_encode "$password")

    # Build credential line
    local protocol="https"
    local cred_line="${protocol}://${encoded_username}:${encoded_password}@${host}"

    # Remove existing entry for this host if present
    if [ -f "$GIT_CREDENTIALS" ]; then
        grep -v "@${host}$" "$GIT_CREDENTIALS" > "${GIT_CREDENTIALS}.tmp" 2>/dev/null || true
        mv "${GIT_CREDENTIALS}.tmp" "$GIT_CREDENTIALS"
    fi

    # Append new credential
    echo "$cred_line" >> "$GIT_CREDENTIALS"
    chmod 600 "$GIT_CREDENTIALS"
}

# Main setup function
main() {
    print_header

    # Check for existing configuration
    local existing_url=""
    local existing_username=""
    local existing_email=""
    local existing_token=""

    if load_existing_config; then
        existing_url="$GITEA_URL"
        existing_username="$GITEA_USERNAME"
        existing_email="$GIT_EMAIL"
        if [ -f "$TOKEN_FILE" ]; then
            existing_token=$(cat "$TOKEN_FILE")
        fi
        print_info "Existing configuration found. Press Enter to keep current values."
    fi

    # Collect configuration
    print_section "Gitea Instance Configuration"

    while true; do
        prompt_with_default "Gitea URL (e.g., https://git.example.com)" "$existing_url" "gitea_url"
        # Remove trailing slash if present
        gitea_url="${gitea_url%/}"
        if validate_url "$gitea_url"; then
            break
        else
            print_error "Invalid URL format. Please include https:// or http://"
        fi
    done

    print_section "Git Identity Configuration"

    prompt_with_default "Git username (for commits)" "$existing_username" "git_username"

    while true; do
        prompt_with_default "Git email (for commits)" "$existing_email" "git_email"
        if validate_email "$git_email"; then
            break
        else
            print_error "Invalid email format. Please enter a valid email address."
        fi
    done

    print_section "Gitea API Token"
    print_info "Create a token at: ${gitea_url}/user/settings/applications"
    echo ""
    echo "  Required scopes:"
    echo "    • write:user        - Create personal repositories"
    echo "    • write:repository  - Repository operations"
    echo "    • read:user         - Verify token, get user info"
    echo ""
    echo "  Optional scopes:"
    echo "    • delete_repo       - Delete repositories"
    echo "    • write:issue       - Manage issues/PRs"
    echo "    • write:organization - Organization repos"
    echo ""

    while true; do
        prompt_with_default "API Token" "$existing_token" "api_token" "true"

        if [ -z "$api_token" ]; then
            print_error "API token is required"
            continue
        fi

        echo -n "Testing API token... "
        local verified_user
        if verified_user=$(test_api_token "$gitea_url" "$api_token"); then
            print_success "Token valid for user: $verified_user"

            # Validate required scopes
            echo -n "Validating token scopes... "
            local missing
            if missing=$(validate_token_scopes "$gitea_url" "$api_token"); then
                print_success "All required scopes present"
            else
                print_error "Missing required scopes: $missing"
                echo ""
                print_info "Please create a new token with the required scopes listed above"
                echo -n "Try again with a different token? [Y/n]: "
                read retry
                if [[ "$retry" =~ ^[Nn] ]]; then
                    print_info "Continuing with limited token (some features may not work)"
                    break
                fi
                continue
            fi
            break
        else
            print_error "Token verification failed"
            echo -n "Try again? [Y/n]: "
            read retry
            if [[ "$retry" =~ ^[Nn] ]]; then
                print_info "Continuing with unverified token"
                break
            fi
        fi
    done

    print_section "Git Credentials (for push/pull/clone)"
    print_info "These credentials will be stored for IDE and CLI git operations."
    print_info "Username/password for: $gitea_url"

    prompt_with_default "Gitea login username" "$git_username" "gitea_login"
    prompt_with_default "Gitea login password" "" "gitea_password" "true"

    # Confirm configuration
    print_section "Configuration Summary"
    echo ""
    echo "  Gitea URL:      $gitea_url"
    echo "  Git Username:   $git_username"
    echo "  Git Email:      $git_email"
    echo "  Gitea Login:    $gitea_login"
    echo "  API Token:      ****${api_token: -4}"
    echo ""

    echo -n "Apply this configuration? [Y/n]: "
    read confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        print_error "Setup cancelled"
        exit 1
    fi

    # Create config directory
    print_section "Applying Configuration"

    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    # Write configuration file
    cat > "$CONFIG_FILE" << EOF
# Git-Gitea Skill Configuration
# Generated by setup.sh on $(date)

GITEA_URL="$gitea_url"
GITEA_USERNAME="$git_username"
GIT_EMAIL="$git_email"
GITEA_LOGIN="$gitea_login"
EOF
    chmod 600 "$CONFIG_FILE"
    print_success "Configuration saved to $CONFIG_FILE"

    # Write API token
    echo -n "$api_token" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    print_success "API token saved to $TOKEN_FILE"

    # Configure git global settings (skip if read-only, e.g., NixOS/home-manager)
    if git config --global user.name "$git_username" 2>/dev/null; then
        git config --global user.email "$git_email"
        git config --global credential.helper store
        print_success "Git global config updated"
    else
        print_info "Git global config is read-only (managed by NixOS/home-manager)"
        print_info "Current git identity: $(git config --global user.name) <$(git config --global user.email)>"
    fi

    # Store git credentials
    if [ -n "$gitea_password" ]; then
        configure_git_credentials "$gitea_url" "$gitea_login" "$gitea_password"
        print_success "Git credentials stored in $GIT_CREDENTIALS"
    else
        print_info "No password provided - you'll be prompted on first git operation"
    fi

    # Summary
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Setup Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Configuration files:"
    echo "    • $CONFIG_FILE"
    echo "    • $TOKEN_FILE"
    echo "    • $GIT_CREDENTIALS"
    echo ""
    echo "  You can now use the gitea-helper.sh functions:"
    echo "    source ~/.claude/skills/git-gitea/scripts/gitea-helper.sh"
    echo "    gitea_help"
    echo ""
}

# Run main function
main "$@"
