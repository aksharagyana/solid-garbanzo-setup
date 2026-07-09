#!/usr/bin/env python3
"""Create a consistently ordered JSON file for easier visual diffing.

Rules:
- Objects: sort keys alphabetically at every level.
- Arrays of primitives: sort values.
- Arrays of objects: sort keys inside each object, then sort objects by the
  value of each object's first key (alphabetically smallest key).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def _canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _primitive_sort_key(value: Any) -> tuple[str, Any]:
    if isinstance(value, bool):
        return ("bool", value)
    if value is None:
        return ("null", "")
    if isinstance(value, (int, float)):
        return ("number", value)
    if isinstance(value, str):
        return ("string", value)
    return (type(value).__name__, _canonical_json(value))


def _object_array_sort_key(obj: dict[str, Any]) -> str:
    first_key = min(obj)
    return _canonical_json(obj[first_key])


def align_value(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: align_value(value[key]) for key in sorted(value)}

    if isinstance(value, list):
        if not value:
            return []

        aligned = [align_value(item) for item in value]

        if all(isinstance(item, dict) for item in aligned):
            return sorted(aligned, key=_object_array_sort_key)

        if all(not isinstance(item, (dict, list)) for item in aligned):
            return sorted(aligned, key=_primitive_sort_key)

        return aligned

    return value


def _aligned_output_path(source: Path, output: Path | None, output_dir: Path | None) -> Path:
    if output is not None:
        return output
    name = f"{source.stem}_aligned{source.suffix or '.json'}"
    return (output_dir or source.parent) / name


def align_file(
    source_path: Path,
    *,
    output_path: Path | None = None,
    output_dir: Path | None = None,
) -> Path:
    with source_path.open(encoding="utf-8") as handle:
        data = json.load(handle)

    aligned = align_value(data)
    destination = _aligned_output_path(source_path, output_path, output_dir)

    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("w", encoding="utf-8") as handle:
        json.dump(aligned, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    return destination


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Create a consistently ordered JSON file for visual diffing.",
    )
    parser.add_argument("input", type=Path, help="JSON file to align")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Output file path (default: <stem>_aligned.json beside input)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="Write default-named output into this directory",
    )
    parser.add_argument(
        "-q",
        "--quiet",
        action="store_true",
        help="Suppress progress messages",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    source_path: Path = args.input
    if not source_path.is_file():
        print(f"Error: file not found: {source_path}", file=sys.stderr)
        return 1

    if args.output is not None and args.output_dir is not None:
        print("Error: use either -o or --output-dir, not both", file=sys.stderr)
        return 1

    try:
        destination = align_file(
            source_path,
            output_path=args.output,
            output_dir=args.output_dir,
        )
    except json.JSONDecodeError as exc:
        print(f"Error: invalid JSON — {exc}", file=sys.stderr)
        return 1

    if not args.quiet:
        print(f"Wrote {destination}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
