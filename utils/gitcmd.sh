TICKET_CACHE="$HOME/.ticket_cache"

error() {
  echo "❌ $1" >&2
  exit 1
}

info() {
  echo "ℹ️  $1"
}

get_ticket_info() {
    local ticketid="$1"
    if [[ -f "$TICKET_CACHE" ]]; then
        grep "^${ticketid}|" "$TICKET_CACHE"
    fi
}

save_ticket_info() {
    local ticketid="$1"
    local shn="$2"
    local msg="$3"
    local type="$4"   # NEW field

    # Remove existing entry
    grep -v "^${ticketid}|" "$TICKET_CACHE" 2>/dev/null > "${TICKET_CACHE}.tmp" || true
    mv "${TICKET_CACHE}.tmp" "$TICKET_CACHE"

    # Save new entry
    echo "${ticketid}|${shn}|${msg}|${type}" >> "$TICKET_CACHE"
}


git_create_feature_branch() {
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo "Not a git repository."
        return 1
    fi

    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

    if [[ "$current_branch" != "$default_branch" ]]; then
        echo "❌ You must be on the default branch ($default_branch) to create a feature branch."
        return 1
    fi

    echo "✔ On default branch: $default_branch"
    git pull origin "$default_branch"

    read -p "Enter ticket ID (alphanumeric allowed): " ticketid

    cache_line=$(get_ticket_info "$ticketid")
    if [[ -n "$cache_line" ]]; then
        IFS='|' read -r _tid shn msg type <<< "$cache_line"
        echo "✔ Loaded cached ticket data:"
        echo "  SHN:  $shn"
        echo "  MSG:  $msg"
        echo "  TYPE: ${type:-<not set>}"
    else
        read -p "Short name (shn): " shn
        read -p "Commit message: " msg
        type=""   # commit type not yet chosen
        save_ticket_info "$ticketid" "$shn" "$msg" "$type"
    fi

    feature_branch="feature/${ticketid}-${shn}"

    if git show-ref --quiet refs/heads/"$feature_branch"; then
        git checkout "$feature_branch"
    else
        git checkout -b "$feature_branch"
    fi

    echo "✔ Feature branch ready: $feature_branch"
}

git_commit_push() {
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    # Allow alphanumeric ticketid only + shn with multiple hyphens
    if [[ "$current_branch" =~ ^feature/([A-Za-z0-9]+)-(.*)$ ]]; then
        ticketid="${BASH_REMATCH[1]}"
        shn="${BASH_REMATCH[2]}"
    else
        echo "❌ Not a valid feature branch (feature/<ticketid>-<shn>)"
        return 1
    fi

    # Try to load metadata from cache
    cache_line=$(get_ticket_info "$ticketid")

    if [[ -z "$cache_line" ]]; then
        echo "⚠ No metadata cached for ticket ${ticketid}"
        echo "➡ Creating new cache entry (idempotent)"

        # Ask for message only — shn we already extracted
        read -p "Commit message: " msg

        # Ask for commit type
        echo "Select commit type:"
        select type in feat fix docs style refactor perf test chore; do
            [[ -n "$type" ]] && break
            echo "Invalid selection."
        done

        # Save metadata into cache
        save_ticket_info "$ticketid" "$shn" "$msg" "$type"
        echo "✔ Saved metadata for ticket ${ticketid}"

    else
        # Cache exists — load it
        IFS='|' read -r _tid _shn msg type <<< "$cache_line"

        # If type missing (old cache) → ask once
        if [[ -z "$type" ]]; then
            echo "Select commit type:"
            select type in feat fix docs style refactor perf test chore; do
                [[ -n "$type" ]] && break
                echo "Invalid selection."
            done
            save_ticket_info "$ticketid" "$_shn" "$msg" "$type"
            echo "✔ Commit type saved"
        fi
    fi

    commit_message="${type}(${ticketid}): ${msg}"

    git add .
    git commit -m "$commit_message"
    git push --set-upstream origin "$current_branch"

    echo "✔ Commit pushed:"
    echo "   $commit_message"
}

git_restore_from_default() {
    local target="$1"

    if [[ -z "$target" ]]; then
        echo "❌ Usage: git_restore_from_default <relative-path>"
        return 1
    fi

    # Ensure valid git repo
    git rev-parse --is-inside-work-tree &>/dev/null
    if [[ $? -ne 0 ]]; then
        echo "❌ Not a git repository."
        return 1
    fi

    # Detect default branch dynamically (origin/HEAD)
    local default_branch
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

    if [[ -z "$default_branch" ]]; then
        echo "❌ Unable to detect default branch."
        return 1
    fi

    # Check if the path exists in the current working tree
    if [[ ! -e "$target" ]]; then
        echo "⚠ Warning: Path '$target' does not exist locally — attempting restore anyway."
    fi

    # Check if the path exists in the default branch
    if ! git ls-tree -r --name-only "$default_branch" | grep -q "^$target"; then
        echo "❌ '$target' does not exist in default branch '$default_branch'."
        return 1
    fi

    echo "✔ Restoring '$target' from branch '$default_branch'..."

    # If a directory → restore recursively
    if [[ -d "$target" ]]; then
        git restore --source "$default_branch" "$target"
        echo "✔ Folder restored: $target"
    else
        git restore --source "$default_branch" "$target"
        echo "✔ File restored: $target"
    fi
}

# Switch Git identity (user.name, user.email) and SSH key based on the repository domain
fix_git_ssh(){
  mkdir -p "${HOME}/.ssh"
  cat "${SSH_CONFIG_PATH}" > "${HOME}/.ssh/config"
}

is_git_repo() {
    # Check current directory by default, or accept a path as argument
    local dir="${1:-.}"
    git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

lower() {
    echo "${1,,}"
}

get_email() {
    # local arg="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
    local arg=$(lower "$1")
    case "$arg" in
        github) echo "${GITHUB_USER_EMAIL}" ;;
        gitlab) echo "${GITLAB_USER_EMAIL}"  ;;
        azure) echo "${AZURE_USER_EMAIL}" ;;
    esac
}
get_username() {
    # local arg="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
    local arg=$(lower "$1")
    case "$arg" in
        github) echo "${GITHUB_USER_NAME}" ;;
        gitlab) echo "${GITLAB_USER_NAME}"  ;;
        azure) echo "${AZURE_USER_NAME}" ;;
    esac
}
unset_old_git_config() {
    git config --global --unset user.name 2>/dev/null || true
    git config --global --unset user.email 2>/dev/null || true
    git config --global --unset url."${AZURE_URL_ADO_PAT}".insteadOf 2>/dev/null || true
}
switch_to(){
    unset_old_git_config
    local arg=$1
    local email="$(get_email $arg)"
    echo "Configuring for $arg..."
    git config --global user.name "$(get_username $arg)"
    if is_git_repo; then
        git config --local user.email "${email}"
    else
        git config --global user.email "${email}"
    fi
    fix_git_ssh
    ssh -T "git@${arg}.com"
    current_git_user
}

switch_to_azure(){
    echo "Configuring for Azure..."
    unset_old_git_config
    git config --global user.name "$(get_username azure)"
    git config --global user.email "$(get_email azure)"
    git config --global url."${AZURE_URL_ADO_PAT}".insteadOf "${AZURE_URL_INSTEADOF}"
    current_git_user
}

current_git_user(){
  echo "Current git config in this repo:"
  echo "   Name : $(git config --get user.name)"
  echo "   Email: $(git config --get user.email)"
  echo "   SSH  : $(git config --get core.sshCommand || echo 'default')"
}

git_switch_identity() {
  local git_domain
  local config_dir="${HOME}/.gitconfig-includes"

  # Detect which remote we're dealing with (github or gitlab)
  git_domain=$(git config --get remote.origin.url | awk -F'[@.:]' '{print $2}')

  case "$git_domain" in
    github.com | github)
      switch_to "github"
      ;;

    gitlab.com | gitlab)
      switch_to "gitlab"
      ;;

    azure.com | azure)
      switch_to_azure
      ;;
  esac

  current_git_user
}


git_delete_all_branches(){
  REPO_DIR="${1:-.}"           # default: current directory
  FORCE_DELETE="${FORCE_DELETE:-false}"  # set FORCE_DELETE=true to force-delete branches
    #############################################
    # Move to repo
    #############################################

    cd "$REPO_DIR" || error "Cannot cd into $REPO_DIR"

    git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || error "Not a git repository"

    #############################################
    # Detect default branch
    #############################################

    DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

    if [[ -z "$DEFAULT_BRANCH" ]]; then
    error "Unable to detect default branch (origin/HEAD not set)"
    fi

    info "Default branch detected: $DEFAULT_BRANCH"

    #############################################
    # Stash all changes (tracked + untracked)
    #############################################

    if [[ -n "$(git status --porcelain)" ]]; then
    info "Stashing uncommitted changes (including untracked files)"
    git stash push -u -m "auto-stash before branch cleanup ($(date))"
    else
    info "Working tree clean – nothing to stash"
    fi

    #############################################
    # Checkout default branch
    #############################################

    CURRENT_BRANCH=$(git branch --show-current)

    if [[ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]]; then
    info "Checking out default branch: $DEFAULT_BRANCH"
    git checkout "$DEFAULT_BRANCH"
    else
    info "Already on default branch"
    fi

    #############################################
    # Delete local branches except default
    #############################################

    info "Deleting local branches except: $DEFAULT_BRANCH"

    git branch \
    | sed 's/^[* ] //' \
    | grep -v "^${DEFAULT_BRANCH}$" \
    | while read -r branch; do
        if [[ "$FORCE_DELETE" == "true" ]]; then
            info "Force deleting branch: $branch"
            git branch -D "$branch"
        else
            info "Deleting branch: $branch"
            git branch -d "$branch" || \
            echo "⚠️  Skipped $branch (not fully merged)"
        fi
        done

    info "✅ Done"

}

# Usage:
#   git-bootstrap-push "https://github.com/username/repo.git"
#   git-bootstrap-push "git@gitlab.com:group/project.git"

git-bootstrap-push() {
    local repo_url="$1"
    local target_branch="main"
    local feature_prefix="feat/bootstrap"

    if [ -z "$repo_url" ]; then
        echo "Error: No git URL provided"
        echo "Usage: git-bootstrap-push <repository-url>"
        return 1
    fi

    # ────────────────────────────────────────────────
    # 1. Already git repo or initialize new one
    # ────────────────────────────────────────────────
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "✓ Already a git repository"
        git remote -v 2>/dev/null || echo "  (no remotes configured)"
    else
        echo "→ Initializing new git repository..."
        git init --initial-branch=main --object-format=sha1
        git config --local init.defaultBranch main 2>/dev/null || true
    fi

    # ────────────────────────────────────────────────
    # 2. Set / update remote origin
    # ────────────────────────────────────────────────
    if ! git remote get-url origin >/dev/null 2>&1; then
        echo "→ Adding remote origin → $repo_url"
        git remote add origin "$repo_url"
    elif [ "$(git remote get-url origin)" != "$repo_url" ]; then
        echo "→ Updating remote origin URL to $repo_url"
        git remote set-url origin "$repo_url"
    fi

    # ────────────────────────────────────────────────
    # 3. Fetch current remote state (critical)
    # ────────────────────────────────────────────────
    echo "→ Fetching remote state..."
    if ! git fetch origin 2>/dev/null; then
        echo "× Fetch failed – check URL / credentials / network"
        return 1
    fi

    # ────────────────────────────────────────────────
    # 4. Stage & commit all changes if any
    # ────────────────────────────────────────────────
    echo "→ Adding all files..."
    git add -A

    if ! git diff --cached --quiet; then
        echo "→ Committing changes..."
        git commit -m "chore: bootstrap initial project files and configuration" || {
            echo "→ Commit failed (possibly nothing new?) – continuing"
        }
    else
        echo "→ No changes to commit"
    fi

    # ────────────────────────────────────────────────
    # 5. Ensure local branch is main (rename if needed)
    # ────────────────────────────────────────────────
    if git branch --show-current | grep -q "^${target_branch}$"; then
        echo "→ Already on branch ${target_branch}"
    elif git rev-parse --verify "refs/heads/master" >/dev/null 2>&1; then
        echo "→ Renaming master → ${target_branch}"
        git branch -m master "${target_branch}"
    elif ! git rev-parse --verify "refs/heads/${target_branch}" >/dev/null 2>&1; then
        echo "→ Creating local branch ${target_branch}"
        git checkout -b "${target_branch}"
    else
        git checkout "${target_branch}"
    fi

    # ────────────────────────────────────────────────
    # NEW: Check if remote main exists
    # ────────────────────────────────────────────────
    if ! git rev-parse --verify "refs/remotes/origin/${target_branch}" >/dev/null 2>&1; then
        echo "→ Remote branch ${target_branch} does NOT exist → safe to push directly"

        echo "→ Pushing to origin ${target_branch} ..."
        if git push --set-upstream origin "${target_branch}"; then
            echo "✓ Push successful – your content is now on remote ${target_branch}"
            return 0
        fi

        echo "→ Normal push failed → trying --force-with-lease ..."
        if git push --force-with-lease --set-upstream origin "${target_branch}"; then
            echo "✓ Push successful (--force-with-lease)"
            return 0
        fi

        echo "→ Trying plain --force as last resort..."
        if git push --force --set-upstream origin "${target_branch}"; then
            echo "✓ Push successful (full force)"
            return 0
        fi

        echo "× All push attempts failed – even though remote branch didn't exist"
        echo "  Possible reasons: permissions, pre-receive hooks, or repo settings"
        return 1
    fi

    # ────────────────────────────────────────────────
    # Remote main EXISTS → use feature branch workflow
    # ────────────────────────────────────────────────
    echo "→ Remote branch ${target_branch} already exists (likely protected)"
    echo "→ Switching to feature branch workflow to respect branch policies"

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local feature_branch="${feature_prefix}-${timestamp}"

    if git rev-parse --verify "refs/heads/${feature_branch}" >/dev/null 2>&1; then
        echo "→ Branch ${feature_branch} already exists locally – reusing"
    else
        echo "→ Creating feature branch → ${feature_branch}"
        git checkout -b "${feature_branch}" || return 1
    fi

    echo "→ Pushing feature branch to remote..."
    if git push --set-upstream origin "${feature_branch}"; then
        echo ""
        echo "✓ Feature branch pushed successfully!"
        echo ""
        echo "Next steps:"
        echo "  1. Open merge request in browser:"
        echo "     https://gitlab.com/shivanaranaya111-group/nidhi-db/-/merge_requests/new"
        echo "     → Source branch: ${feature_branch}"
        echo "     → Target branch: ${target_branch}"
        echo "  2. Use a conventional commit title, e.g.:"
        echo "     chore: bootstrap initial project structure and config files"
        echo "  3. Merge (squash recommended) when ready"
        echo ""
        return 0
    else
        echo "× Failed to push feature branch – check permissions or branch name"
        echo "  You can still push manually: git push -u origin ${feature_branch}"
        return 1
    fi
}

git-safe-rebase-pull() {
    local remote="${1:-origin}"
    local branch="${2:-$(git branch --show-current)}"

    if [ -z "$branch" ]; then
        echo "Error: Could not determine current branch" >&2
        return 1
    fi

    echo "→ Fetching latest changes from ${remote} ..."
    if ! git fetch --quiet "${remote}"; then
        echo "Error: git fetch failed" >&2
        return 1
    fi

    local remote_ref="${remote}/${branch}"

    if ! git rev-parse --verify "${remote_ref}" >/dev/null 2>&1; then
        echo "Error: Remote branch ${remote_ref} does not exist" >&2
        return 1
    fi

    echo "→ Rebasing $(git branch --show-current) onto ${remote_ref} (non-interactive) ..."

    # The three most important flags:
    #   --autostash        → automatically stash + re-apply local uncommitted changes
    #   --quiet            → less noisy output
    # GIT_SEQUENCE_EDITOR=:  → disable any interactive rebase editing
    GIT_SEQUENCE_EDITOR=: git rebase --autostash --quiet "${remote_ref}"

    local rc=$?

    if [ $rc -eq 0 ]; then
        echo "✓ Rebase successful"
        # Optional: fast-forward pull-like behavior if possible
        git merge --ff-only "${remote_ref}" 2>/dev/null || true
        return 0
    elif [ $rc -eq 1 ]; then
        echo ""
        echo "× Rebase conflict detected"
        echo "  You are now in the middle of a rebase."
        echo "  Resolve conflicts, then run:"
        echo "    git rebase --continue"
        echo "  or to abort:"
        echo "    git rebase --abort"
        return 1
    else
        echo "× git rebase failed (exit code ${rc})" >&2
        return $rc
    fi
}

git-rebase-pull-noninteractive() {
    local remote="${1:-origin}"
    local branch="${2:-$(git branch --show-current 2>/dev/null)}"

    [ -z "$branch" ] && { echo "No branch" >&2; return 1; }

    git fetch --quiet "${remote}" || return 1

    GIT_SEQUENCE_EDITOR=: \
    git rebase --autostash --quiet "${remote}/${branch}" || {
        echo "Rebase failed or conflict" >&2
        return 1
    }

    # Optional: try to fast-forward if possible after rebase
    git merge --ff-only "${remote}/${branch}" 2>/dev/null || true

    echo "Rebased onto ${remote}/${branch}"
}


# git-branches
#   Simple non-interactive branch & tag listing
#
# Usage examples:
#   git-branches                      # show local branches only (current highlighted)
#   git-branches -r                   # show remote branches
#   git-branches -a                   # show both local + remote
#   git-branches -t                   # show local + remote tags
#   git-branches -at                  # show everything: local/remote branches + tags
#
# Features:
#   - Marks current branch with *
#   - No pager/editor launched
#   - Clear separation of sections
#   - Works even when not on a branch (detached HEAD)
#
git-branches() {
    local show_local=1
    local show_remote=0
    local show_tags=0

    # Parse short options (-r, -a, -t, combinations like -at, -ra, etc.)
    while getopts ":art" opt; do
        case $opt in
            a)  show_local=1; show_remote=1 ;;
            r)  show_remote=1; show_local=0 ;;
            t)  show_tags=1 ;;
            \?) echo "Usage: git-branches [-a] [-r] [-t]" >&2; return 1 ;;
        esac
    done
    shift $((OPTIND-1))

    # Default: show local branches if nothing specified
    [ $show_local -eq 0 ] && [ $show_remote -eq 0 ] && [ $show_tags -eq 0 ] && show_local=1

    # ────────────────────────────────────────────────
    # Local branches
    # ────────────────────────────────────────────────
    if [ $show_local -eq 1 ]; then
        echo "Local branches:"
        echo "────────────────"

        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            git branch --color=always --sort=-committerdate |
                sed 's/^\*/ →/' |  # nicer symbol for current branch
                sed 's/^/  /'      # indent
        else
            echo "  (not inside a git repository)"
        fi
        echo ""
    fi

    # ────────────────────────────────────────────────
    # Remote branches
    # ────────────────────────────────────────────────
    if [ $show_remote -eq 1 ]; then
        echo "Remote branches:"
        echo "─────────────────"

        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            git branch --remote --color=always --sort=-committerdate |
                grep -v ' -> ' |   # hide HEAD -> ... line
                sed 's/^  /  /'    # indent
        else
            echo "  (not inside a git repository)"
        fi
        echo ""
    fi

    # ────────────────────────────────────────────────
    # Tags (local + remote)
    # ────────────────────────────────────────────────
    if [ $show_tags -eq 1 ]; then
        echo "Tags:"
        echo "─────"

        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            git tag --sort=-v:refname |
                sed 's/^/  /'
        else
            echo "  (not inside a git repository)"
        fi
        echo ""
    fi

    # Optional: show current HEAD commit if useful
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "Current HEAD:"
        echo "─────────────"
        git rev-parse --short HEAD --symbolic-full-name HEAD 2>/dev/null |
            sed 's/^/  /'
        echo ""
    fi
}

# ------------------------------------------------------------------------------
# dummy_commit [options]
# Triggers a CI pipeline with a real (non-empty) commit
# ------------------------------------------------------------------------------

git_trigger_pipeline() {
    local msg="${1:-chore: trigger CI/CD pipeline [empty commit]}"
    
    git commit --allow-empty -m "$msg" || {
        echo "Commit failed (maybe nothing to commit or protected branch?)"
        return 1
    }
    
    local branch
    branch=$(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD)
    
    echo "Pushing empty commit to: $branch"
    git push origin "$branch"
}

_git_merge_fix_trailing_whitespace() {
    local f
    for f in "$@"; do
        [[ -f "${f}" ]] || continue
        perl -pi -e 's/\s+$//' "${f}" 2>/dev/null || \
            sed -i 's/[[:space:]]*$//' "${f}" 2>/dev/null || true
    done
}

_git_merge_whitespace_error_files() {
    {
        git diff --check 2>&1 || true
        git diff --cached --check 2>&1 || true
    } | sed -n 's/^\([^:]*\):[0-9]*: trailing whitespace\./\1/p' | sort -u
}

_git_merge_conflict_files() {
    git diff --name-only --diff-filter=U 2>/dev/null
}

_git_merge_in_progress() {
    local git_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
    [[ -f "${git_dir}/MERGE_HEAD" ]]
}

_git_merge_stash_if_dirty() {
    if [[ -n "$(git status --porcelain)" ]]; then
        info "Stashing uncommitted changes before merge (including untracked files)"
        git stash push -u -m "auto-stash before git_merge ($(date +%Y%m%d-%H%M%S))" || return 1
        return 0
    fi
    return 1
}

_git_merge_pop_stash_if_any() {
    local had_stash="${1:-0}"
    local top_stash

    [[ "${had_stash}" -eq 1 ]] || return 0

    top_stash=$(git stash list | head -n1)
    if [[ "${top_stash}" != *'auto-stash before git_merge'* ]]; then
        echo "WARNING: Expected git_merge stash not at stash@{0} — re-apply manually: git stash list" >&2
        return 1
    fi

    info "Re-applying stashed changes"
    git stash pop || {
        echo "WARNING: Stash pop had conflicts — resolve manually with: git stash list" >&2
        return 1
    }
    return 0
}

_git_merge_abort_and_cleanup() {
    if _git_merge_in_progress; then
        git merge --abort 2>/dev/null || true
    fi
}

_git_merge_complete() {
    local f
    local ws_files=()
    while IFS= read -r f; do
        [[ -n "${f}" ]] && ws_files+=("${f}")
    done < <(_git_merge_whitespace_error_files)

    if [[ ${#ws_files[@]} -gt 0 ]]; then
        info "Fixing trailing whitespace in ${#ws_files[@]} file(s)"
        _git_merge_fix_trailing_whitespace "${ws_files[@]}"
        git add -- "${ws_files[@]}" 2>/dev/null || true
    fi

    GIT_EDITOR=true git commit --no-edit
}

_git_merge_resolve_conflicts() {
    local side="$1"
    local source_branch="$2"
    local target_branch="$3"
    local file

    while IFS= read -r file; do
        [[ -z "${file}" ]] && continue
        case "${side}" in
            source)
                git checkout --theirs -- "${file}" || return 1
                ;;
            target)
                git checkout --ours -- "${file}" || return 1
                ;;
            *)
                echo "ERROR: Unknown conflict resolution side: ${side}" >&2
                return 1
                ;;
        esac
        _git_merge_fix_trailing_whitespace "${file}"
        git add -- "${file}" || return 1
    done < <(_git_merge_conflict_files)

    echo "Resolved conflicts using ${side} version"
    echo "  source (${source_branch}) → theirs"
    echo "  target (${target_branch}) → ours"
    _git_merge_complete
}

_git_merge_handle_failure() {
    local merge_rc="$1"
    local source_branch="$2"
    local target_branch="$3"
    local merge_log="$4"
    local conflict_files=()
    local file
    local choice
    local resolve_side=""

    echo "ERROR: Merge failed (exit ${merge_rc})." >&2
    if [[ -n "${merge_log}" ]]; then
        echo "${merge_log}" | tail -n 20
    fi

    if echo "${merge_log}" | grep -qiE 'whitespace|trailing whitespace'; then
        info "Whitespace issues detected — attempting automatic fix"
        local ws_files=()
        while IFS= read -r file; do
            [[ -n "${file}" ]] && ws_files+=("${file}")
        done < <(_git_merge_whitespace_error_files)

        if [[ ${#ws_files[@]} -eq 0 ]]; then
            while IFS= read -r file; do
                [[ -n "${file}" ]] && ws_files+=("${file}")
            done < <(git diff --name-only; git diff --cached --name-only)
        fi

        if [[ ${#ws_files[@]} -gt 0 ]]; then
            _git_merge_fix_trailing_whitespace "${ws_files[@]}"
            git add -A 2>/dev/null || true
            if _git_merge_in_progress; then
                if _git_merge_complete; then
                    echo "Merge completed after fixing whitespace."
                    return 0
                fi
            else
                info "Retrying merge after whitespace fix"
                return 2
            fi
        fi
    fi

    if ! _git_merge_in_progress; then
        echo "Merge did not start (no MERGE_HEAD). Check branch names, local changes, or remote state." >&2
        return "${merge_rc}"
    fi

    while IFS= read -r file; do
        [[ -n "${file}" ]] && conflict_files+=("${file}")
    done < <(_git_merge_conflict_files)

    if [[ ${#conflict_files[@]} -eq 0 ]]; then
        echo "Merge is in progress but no unmerged files were found." >&2
        echo "Resolve manually, then: git commit --no-edit" >&2
        echo "Or abort with: git merge --abort" >&2
        return "${merge_rc}"
    fi

    echo ""
    echo "Conflicting files (${#conflict_files[@]}):"
    for file in "${conflict_files[@]}"; do
        echo "  - ${file}"
    done
    echo ""
    echo "During merge into '${target_branch}':"
    echo "  source (${source_branch}) = theirs"
    echo "  target (${target_branch}) = ours"
    echo ""

    if [[ -n "${GIT_MERGE_RESOLVE:-}" ]]; then
        case "${GIT_MERGE_RESOLVE}" in
            source|theirs) resolve_side="source" ;;
            target|ours) resolve_side="target" ;;
            abort)
                _git_merge_abort_and_cleanup
                echo "Merge aborted."
                return 1
                ;;
            *)
                echo "ERROR: Invalid GIT_MERGE_RESOLVE='${GIT_MERGE_RESOLVE}' (use source|target|abort)" >&2
                return 1
                ;;
        esac
    elif [[ ! -t 0 ]]; then
        echo "Non-interactive shell — set GIT_MERGE_RESOLVE=source|target|abort or resolve manually." >&2
        echo "  git merge --abort" >&2
        return "${merge_rc}"
    else
        PS3="Choose conflict resolution: "
        select choice in \
            "Use source (${source_branch}) for all conflicts" \
            "Use target (${target_branch}) for all conflicts" \
            "Abort merge" \
            "Leave conflicts for manual resolution"
        do
            case "${REPLY}" in
                1) resolve_side="source"; break ;;
                2) resolve_side="target"; break ;;
                3)
                    _git_merge_abort_and_cleanup
                    echo "Merge aborted."
                    return 1
                    ;;
                4)
                    echo "Conflicts left in place. Resolve files, then run:"
                    echo "  git add <files>"
                    echo "  git commit --no-edit"
                    echo "Or abort with:"
                    echo "  git merge --abort"
                    return "${merge_rc}"
                    ;;
                *) echo "Invalid selection." ;;
            esac
        done
    fi

    if [[ -n "${resolve_side}" ]]; then
        _git_merge_resolve_conflicts "${resolve_side}" "${source_branch}" "${target_branch}" || return 1
        echo "Merge completed after resolving conflicts."
        return 0
    fi

    return "${merge_rc}"
}

git_revert_last_commit() {
    local branch

    git rev-parse --is-inside-work-tree &>/dev/null || {
        echo "Error: This directory is not a git repository." >&2
        return 1
    }

    branch=$(git rev-parse --abbrev-ref HEAD)
    echo "Targeting branch: ${branch}"

    git revert HEAD --no-edit || {
        echo "Error: Revert failed. You might have manual conflicts to resolve." >&2
        return 1
    }

    echo "Revert successful. Pushing to origin/${branch}..."
    git push origin "${branch}" || return 1

    echo "Done! The last commit has been undone and pushed."
}

git_merge() {
    local source_branch=""
    local target_branch=""
    local stashed=0
    local merge_rc=0
    local merge_log=""

    usage() {
        cat <<EOF
Usage:
  git_merge [-s <source_branch>] [-t <target_branch>]

Merge source into target (checkout target, pull, merge source).

Options:
  -s    Source branch to merge from (default: repo default branch)
  -t    Target branch to merge into (default: current branch)
  -h    Show this help

Environment:
  GIT_MERGE_RESOLVE   Non-interactive conflict resolution: source | target | abort

Examples:
  git_merge                                    # merge main into current branch
  git_merge -s main -t feature/my-branch
  git_merge -s develop                         # merge develop into current branch
  GIT_MERGE_RESOLVE=source git_merge -s main   # take incoming branch on conflicts
EOF
    }

    local OPTIND
    OPTIND=1
    while getopts ":s:t:h" opt; do
        case "${opt}" in
            s) source_branch="${OPTARG}" ;;
            t) target_branch="${OPTARG}" ;;
            h)
                usage
                return 0
                ;;
            *)
                usage
                return 1
                ;;
        esac
    done

    git rev-parse --is-inside-work-tree &>/dev/null || {
        echo "ERROR: Not a git repository." >&2
        return 1
    }

    if [[ -z "${target_branch}" ]]; then
        target_branch=$(git branch --show-current 2>/dev/null)
        if [[ -z "${target_branch}" ]]; then
            echo "ERROR: Could not determine current branch (detached HEAD?). Use -t." >&2
            return 1
        fi
    fi

    echo "Fetching latest changes..."
    git fetch --all --prune || return 1

    if [[ -z "${source_branch}" ]]; then
        source_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
        if [[ -z "${source_branch}" ]]; then
            local candidate
            for candidate in main master; do
                if git rev-parse --verify "origin/${candidate}" >/dev/null 2>&1; then
                    source_branch="${candidate}"
                    break
                fi
            done
        fi
        if [[ -z "${source_branch}" ]]; then
            echo "ERROR: Could not detect default branch. Use -s." >&2
            return 1
        fi
    fi

    if [[ "${source_branch}" == "${target_branch}" ]]; then
        echo "ERROR: Source and target are both '${source_branch}'; nothing to merge." >&2
        return 1
    fi

    if _git_merge_stash_if_dirty; then
        stashed=1
    fi

    echo "Source: ${source_branch}"
    echo "Target: ${target_branch}"
    echo "Checking out target branch: ${target_branch}"
    git checkout "${target_branch}" || {
        [[ ${stashed} -eq 1 ]] && _git_merge_pop_stash_if_any "${stashed}"
        return 1
    }

    echo "Pulling latest changes..."
    git pull origin "${target_branch}" || {
        [[ ${stashed} -eq 1 ]] && _git_merge_pop_stash_if_any "${stashed}"
        return 1
    }

    echo "Merging ${source_branch} into ${target_branch}..."

    local merge_attempt=0
    while [[ ${merge_attempt} -lt 2 ]]; do
        merge_rc=0
        merge_log=$(
            GIT_EDITOR=true git -c core.whitespace=fix merge \
                --no-ff \
                --no-edit \
                "${source_branch}" 2>&1
        ) || merge_rc=$?

        if [[ ${merge_rc} -eq 0 ]]; then
            break
        fi

        if _git_merge_handle_failure "${merge_rc}" "${source_branch}" "${target_branch}" "${merge_log}"; then
            merge_rc=0
            break
        fi

        local handle_rc=$?
        if [[ ${handle_rc} -eq 2 ]]; then
            merge_attempt=$((merge_attempt + 1))
            continue
        fi

        [[ ${stashed} -eq 1 ]] && {
            echo "Your pre-merge stash was kept. Re-apply later with: git stash pop" >&2
        }
        return "${merge_rc}"
    done

    if [[ ${merge_rc} -ne 0 ]]; then
        [[ ${stashed} -eq 1 ]] && {
            echo "Your pre-merge stash was kept. Re-apply later with: git stash pop" >&2
        }
        return "${merge_rc}"
    fi

    if [[ ${stashed} -eq 1 ]]; then
        _git_merge_pop_stash_if_any "${stashed}" || return 1
    fi

    echo "Merge completed successfully."
}
