#!/usr/bin/env python3
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SKILL_FILENAMES = {"skill.md", "skills.md"}
FLAT_SKILL_SUFFIX = ".SKILLS.md"
LEGACY_NESTED_FILENAME = "SKILLS.md"
OUTPUT_FILENAME = "SKILL.md"
DEFAULT_DEST = Path("~/.codex/skills").expanduser()


def repo_slug(repo_url: str) -> str:
    name = repo_url.rstrip("/").split("/")[-1]
    if name.endswith(".git"):
        name = name[:-4]
    return name or "repo"


def parent_folder_name(skill_path: Path, clone_root: Path, slug: str) -> str:
    parent = skill_path.parent
    if parent == clone_root:
        return slug
    name = parent.name
    return name or slug


def clone_repo(repo_url: str, workspace: Path) -> Path:
    clone_dir = workspace / repo_slug(repo_url)
    result = subprocess.run(
        ["git", "clone", "--depth", "1", repo_url, str(clone_dir)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        message = (result.stderr or result.stdout or "").strip()
        print(
            f"[!] Critical Error: Failed to clone repository '{repo_url}'.",
            file=sys.stderr,
        )
        if message:
            print(message, file=sys.stderr)
        sys.exit(1)
    return clone_dir


def find_skill_files(clone_root: Path) -> list[Path]:
    matches: list[Path] = []
    for root, _, files in os.walk(clone_root):
        for filename in files:
            if filename.lower() in SKILL_FILENAMES:
                matches.append(Path(root) / filename)
    return sorted(matches)


def find_flat_skill_files(dest_dir: Path) -> list[Path]:
    if not dest_dir.is_dir():
        return []
    return sorted(
        path
        for path in dest_dir.glob(f"*{FLAT_SKILL_SUFFIX}")
        if path.is_file()
    )


def destination_path(dest_dir: Path, folder: str) -> Path:
    return dest_dir / folder / OUTPUT_FILENAME


def flat_skill_folder(flat_file: Path) -> str:
    return flat_file.name[: -len(FLAT_SKILL_SUFFIX)]


def confirm_overwrite(dest_file: Path) -> bool:
    if not dest_file.exists():
        return True
    try:
        answer = input(
            f"[!] {dest_file} already exists. Overwrite? [y/N]: "
        ).strip()
    except EOFError:
        print("  [-] Skipped (non-interactive).")
        return False
    if answer.lower() in ("y", "yes"):
        return True
    print(f"  [-] Skipped: {dest_file}")
    return False


def find_nested_legacy_skill_files(dest_dir: Path) -> list[Path]:
    if not dest_dir.is_dir():
        return []
    return sorted(
        path
        for path in dest_dir.rglob(LEGACY_NESTED_FILENAME)
        if path.is_file() and path.name == LEGACY_NESTED_FILENAME
    )


def fix_skill_layout(dest_dir: Path) -> int:
    dest_dir.mkdir(parents=True, exist_ok=True)

    moved: list[Path] = []
    skipped: list[Path] = []

    print(f"[*] Scanning for flat *{FLAT_SKILL_SUFFIX} files in: {dest_dir}")
    flat_files = find_flat_skill_files(dest_dir)

    for src in flat_files:
        folder = flat_skill_folder(src)
        if not folder:
            print(f"  [!] Could not derive folder name from: {src.name}", file=sys.stderr)
            skipped.append(src.resolve())
            continue

        dest_file = destination_path(dest_dir, folder)
        if dest_file.exists() and not confirm_overwrite(dest_file):
            skipped.append(src.resolve())
            continue

        dest_file.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(src), str(dest_file))
        moved.append(dest_file.resolve())
        print(f"  [+] {src.name}  ->  {dest_file}")

    print(f"[*] Scanning for nested {LEGACY_NESTED_FILENAME} files in: {dest_dir}")
    nested_files = find_nested_legacy_skill_files(dest_dir)

    if not flat_files and not nested_files:
        print("[*] Nothing to fix — no legacy skill files found.")
        return 0

    for src in nested_files:
        dest_file = src.parent / OUTPUT_FILENAME
        if dest_file.resolve() == src.resolve():
            continue
        if dest_file.exists() and not confirm_overwrite(dest_file):
            skipped.append(src.resolve())
            continue

        shutil.move(str(src), str(dest_file))
        moved.append(dest_file.resolve())
        print(f"  [+] {src}  ->  {dest_file}")

    if moved:
        print(f"\n[*] Fixed {len(moved)} skill file(s):")
        for path in moved:
            print(path)
    if skipped:
        print(f"\n[*] Skipped {len(skipped)} file(s):")
        for path in skipped:
            print(path)

    return 0 if not skipped or moved else 1


def fix_flat_skills(dest_dir: Path) -> int:
    return fix_skill_layout(dest_dir)

def run_install(args: argparse.Namespace) -> int:
    repo_url = args.repo
    dest_dir = Path(args.directory).expanduser().resolve()
    slug = repo_slug(repo_url)

    print(f"[*] Target location: {dest_dir}")
    print(f"[*] Fetching repository: {repo_url}")

    dest_dir.mkdir(parents=True, exist_ok=True)

    created: list[Path] = []
    skipped: list[Path] = []

    with tempfile.TemporaryDirectory() as tmpdir:
        clone_root = clone_repo(repo_url, Path(tmpdir))

        print("[*] Recursively scanning for SKILL.md / skills.md ...")
        skill_files = find_skill_files(clone_root)

        if not skill_files:
            print(
                "[!] Warning: No SKILL.md or skills.md files found in this repository."
            )
            return 0

        for src in skill_files:
            folder = parent_folder_name(src, clone_root, slug)
            dest_file = destination_path(dest_dir, folder)
            if not confirm_overwrite(dest_file):
                skipped.append(dest_file.resolve())
                continue
            dest_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest_file)
            created.append(dest_file.resolve())
            print(f"  [+] {dest_file}")

    if created:
        print(f"\n[*] Installed {len(created)} skill file(s):")
        for path in created:
            print(path)
    if skipped:
        print(f"\n[*] Skipped {len(skipped)} existing file(s):")
        for path in skipped:
            print(path)
    if not created and not skipped:
        print("\n[*] No skill files installed.")

    return 0


def run_fix(args: argparse.Namespace) -> int:
    dest_dir = Path(args.directory).expanduser().resolve()
    return fix_flat_skills(dest_dir)


def build_install_parser() -> argparse.ArgumentParser:
    epilog = """
examples:
  %(prog)s -r https://github.com/org/codex-skills.git
  %(prog)s -r https://github.com/org/codex-skills.git -d ~/my-skills

naming:
  skills/tdd/SKILL.md             ->  ~/.codex/skills/tdd/SKILL.md
  modules/reviewer/skills.md      ->  ~/.codex/skills/reviewer/SKILL.md

  Each skill is saved under <destination>/<parent-folder>/SKILL.md.

overwrite:
  Existing destination files trigger an interactive prompt [y/N].
""".strip()

    parser = argparse.ArgumentParser(
        description=(
            "Extract SKILL.md / skills.md files from a Git repo into "
            "per-skill folders under a local skills directory."
        ),
        epilog=epilog,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "-r",
        "--repo",
        required=True,
        help="HTTPS URL of the Git repository to clone",
    )
    parser.add_argument(
        "-d",
        "--directory",
        default=str(DEFAULT_DEST),
        help=f"destination directory (default: {DEFAULT_DEST})",
    )
    return parser


def build_fix_parser() -> argparse.ArgumentParser:
    epilog = f"""
examples:
  %(prog)s
  %(prog)s -d ~/.codex/skills

migration:
  shipping-and-launch.SKILLS.md       ->  shipping-and-launch/SKILL.md
  skill-creator/SKILLS.md             ->  skill-creator/SKILL.md

  Repairs flat *{FLAT_SKILL_SUFFIX} files and nested {LEGACY_NESTED_FILENAME} names.
""".strip()

    parser = argparse.ArgumentParser(
        description=(
            "Repair legacy skill layouts: flat *"
            f"{FLAT_SKILL_SUFFIX} and nested {LEGACY_NESTED_FILENAME} "
            f"-> <name>/{OUTPUT_FILENAME}."
        ),
        epilog=epilog,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "-d",
        "--directory",
        default=str(DEFAULT_DEST),
        help=f"skills directory to repair (default: {DEFAULT_DEST})",
    )
    return parser


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "fix":
        args = build_fix_parser().parse_args(sys.argv[2:])
        sys.exit(run_fix(args))

    args = build_install_parser().parse_args()
    sys.exit(run_install(args))


if __name__ == "__main__":
    main()
