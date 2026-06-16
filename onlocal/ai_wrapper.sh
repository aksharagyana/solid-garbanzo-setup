#!/bin/bash

# Resolve this script's directory in bash or zsh (onlocal is often sourced from zsh).
if [[ -n "${ZSH_VERSION:-}" ]]; then
    _AI_WRAPPER_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    _AI_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

get_skills_help() {
    cat <<'EOF'
get_skills — install Codex skill files from a remote Git repository

Extract every SKILL.md or skills.md (case-insensitive) from a repo and save
them under per-skill folders for local Codex use.

Usage:
  get_skills -r <REPO_URL> [-d <DEST_DIR>]
  get_skills -h | --help

Options:
  -r, --repo URL       HTTPS Git repository URL (required)
  -d, --directory DIR  Destination directory (default: ~/.codex/skills/)
  -h, --help           Show this help

How it works:
  1. Shallow-clones the repository into a temporary workspace
  2. Recursively finds SKILL.md / skills.md files
  3. Writes each skill to: <DEST>/<parent-folder>/SKILL.md
  4. Prompts before overwriting any file that already exists

Naming:
  Repo path                          ->  Output file
  skills/tdd/SKILL.md                ->  ~/.codex/skills/tdd/SKILL.md
  modules/code-reviewer/skills.md    ->  ~/.codex/skills/code-reviewer/SKILL.md

  The parent folder name becomes a subdirectory under the destination.
  The skill file is always named SKILL.md inside that folder.

Overwrite:
  If a destination file already exists, you are asked:
    Overwrite? [y/N]
  Enter or N keeps the existing file; y replaces it.

Examples:
  get_skills -r https://github.com/org/codex-skills.git
  get_skills -r https://github.com/org/codex-skills.git -d ~/my-skills
  get_skills --help

Requirements:
  - python3, git
  - network access to clone the repository

See also: fix_skills — repair legacy flat *.SKILLS.md files

EOF
}

fix_skills_help() {
    cat <<'EOF'
fix_skills — repair legacy skill file layouts

Repairs:
  ~/.codex/skills/name.SKILLS.md      ->  ~/.codex/skills/name/SKILL.md
  ~/.codex/skills/name/SKILLS.md      ->  ~/.codex/skills/name/SKILL.md

Usage:
  fix_skills [-d <DEST_DIR>]
  fix_skills -h | --help

Options:
  -d, --directory DIR  Skills directory to repair (default: ~/.codex/skills/)
  -h, --help           Show this help

Behavior:
  1. Moves top-level *.SKILLS.md into <skill-name>/SKILL.md
  2. Renames nested SKILLS.md to SKILL.md inside skill folders
  3. Prompts before overwriting an existing SKILL.md

Examples:
  fix_skills
  fix_skills -d ~/.codex/skills

EOF
}

fix_skills() {
    case "${1:-}" in
        -h|--help|help)
            fix_skills_help
            return 0
            ;;
    esac

    local script_path="${_AI_WRAPPER_DIR}/ai.py"

    if [[ ! -f "${script_path}" ]]; then
        echo "[!] Error: Python script not found at: ${script_path}" >&2
        return 1
    fi

    python3 "${script_path}" fix "$@"
}

get_skills() {
    case "${1:-}" in
        -h|--help|help)
            get_skills_help
            return 0
            ;;
    esac

    local script_path="${_AI_WRAPPER_DIR}/ai.py"

    if [[ ! -f "${script_path}" ]]; then
        echo "[!] Error: Python script not found at: ${script_path}" >&2
        return 1
    fi

    python3 "${script_path}" "$@"
}
