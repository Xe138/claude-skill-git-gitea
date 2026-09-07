#!/usr/bin/env bash
set -euo pipefail

# sops-secrets.sh — standardized, simple SOPS/age secrets for ANY git repo.
#
# The common use case: give an AI agent (or a script) a credential inside a
# git-controlled workspace — e.g. a Cloudflare API token — without ever committing
# plaintext. The encrypted file is committed; any agent on a host whose age key is a
# recipient decrypts it transparently with `sops -d`.
#
# Runs against the CURRENT git repo ($PWD). Subcommands:
#   sops-secrets.sh init [recipient-alias...]   # scaffold .sops.yaml + secrets/ (once)
#   sops-secrets.sh add  <name> <KEY> [VALUE]    # add/replace a key (prompts if VALUE omitted)
#   sops-secrets.sh edit <name>                  # $EDITOR the file (decrypt in / re-encrypt out)
#   sops-secrets.sh view <name>                  # print decrypted contents
#   sops-secrets.sh rekey [name...]              # re-encrypt to current .sops.yaml recipients
#
# <name> is the file stem: "cloudflare" -> secrets/cloudflare.sops.yaml
#
# CANONICAL RECIPIENTS (edit here to extend the fleet). A repo is encrypted to
# `bill` (recovery, from his desktop) + the host(s) where its agents run + one
# recovery host. Defaults suit a workspace whose agents run on soos.
declare -A AGE_RECIPIENTS=(
  [bill]=age1usp4weqdyygssa9l9d063wv8gahy6t8zctr9gpzxdunfav57h3cqcaewj4    # user, recovery
  [wsl]=age1ethpglzfashs0824tcg3cvuzcrucg66xgx25f9amlqdm6wh5qemq3ws8ac     # soos user key (agents on soos)
  [soos]=age1g3vhtpfptz3klwvvw3qwyejg50neeqf0ac8lndvu0pdfv7wfqv8s3njelv    # soos host key
  [inkling]=age19hy45afa73e6m8ltjz36qd0hpp2ekmd0kg72etr5deaydp845azqr92pem # recovery host
  [shellington]=age1fcmjersjwuqecz9n58qf8n3pk46r7439fgzhdtjw5z9zq40sjygqfc5cz8
  [tweak]=age1l4qj6cf2cn469hr3fa743glnlzr9gk53j3l3az5muchsaepmnqhspuhe7m
)
DEFAULT_ALIASES=(bill wsl soos inkling)

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not inside a git repo" >&2; exit 1; }

# Resolve a sops invocation: native binary, else via nix.
if command -v sops >/dev/null 2>&1; then
  SOPS=(command sops)
elif command -v nix >/dev/null 2>&1; then
  SOPS=(nix run nixpkgs#sops --)
else
  echo "sops not found and nix is unavailable to provide it." >&2; exit 1
fi
run_sops() { "${SOPS[@]}" "$@"; }

path_for() {
  case "$1" in
    */*|*.sops.yaml) echo "$1" ;;
    *) echo "${REPO_ROOT}/secrets/${1}.sops.yaml" ;;
  esac
}

cmd=${1:-}; shift || true
case "$cmd" in
  init)
    aliases=("$@"); [[ ${#aliases[@]} -eq 0 ]] && aliases=("${DEFAULT_ALIASES[@]}")
    f="${REPO_ROOT}/.sops.yaml"
    if [[ -f "$f" ]]; then echo "$f already exists — leaving it untouched."; else
      { echo "# SOPS recipients for this repo. Managed by the git-gitea skill's"
        echo "# sops-secrets.sh. Every secrets/*.sops.yaml is encrypted to all of them,"
        echo "# so Bill and the listed hosts can always decrypt."
        echo "keys:"
        for a in "${aliases[@]}"; do
          [[ -n "${AGE_RECIPIENTS[$a]:-}" ]] || { echo "unknown alias: $a" >&2; exit 1; }
          printf '  - &%s %s\n' "$a" "${AGE_RECIPIENTS[$a]}"
        done
        echo
        echo "creation_rules:"
        echo "  - path_regex: secrets/.*\\.ya?ml\$"
        echo "    key_groups:"
        echo "      - age:"
        for a in "${aliases[@]}"; do printf '          - *%s\n' "$a"; done
      } > "$f"
      echo "Wrote $f (recipients: ${aliases[*]})."
    fi
    mkdir -p "${REPO_ROOT}/secrets"
    echo "Ready. Add a credential:  sops-secrets.sh add <name> <KEY>"
    ;;
  add)
    name=${1:?usage: add <name> <KEY> [VALUE]}; key=${2:?usage: add <name> <KEY> [VALUE]}; val=${3:-}
    f=$(path_for "$name")
    [[ -f "${REPO_ROOT}/.sops.yaml" ]] || { echo "no .sops.yaml — run 'sops-secrets.sh init' first" >&2; exit 1; }
    [[ -z "$val" ]] && { read -r -s -p "Value for ${key}: " val; echo; }
    if [[ ! -f "$f" ]]; then
      ( umask 077; printf '%s: %s\n' "$key" "$val" > "$f" )
      run_sops -e -i "$f"; echo "Created $f with key '$key'."
    else
      run_sops set "$f" "[\"${key}\"]" "\"${val}\""; echo "Set '$key' in $f."
    fi
    ;;
  edit) run_sops "$(path_for "${1:?usage: edit <name>}")" ;;
  view) run_sops -d "$(path_for "${1:?usage: view <name>}")" ;;
  rekey)
    if [[ $# -eq 0 ]]; then mapfile -t files < <(find "${REPO_ROOT}/secrets" -name '*.sops.yaml' 2>/dev/null)
    else files=(); for n in "$@"; do files+=("$(path_for "$n")"); done; fi
    for f in "${files[@]}"; do echo "updatekeys: $f"; run_sops updatekeys --yes "$f"; done
    ;;
  *) sed -n '3,20p' "$0"; exit 1 ;;
esac
