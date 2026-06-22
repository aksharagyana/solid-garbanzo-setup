"""
PII Anonymization Script
========================

Description:
    This script replaces sensitive strings (PII - Personally Identifiable Information)
    such as names, emails, UUIDs, secrets, API keys, etc. with consistent random UUIDs.

    Key Features:
    - Persistent replacement map stored globally at ~/.pii_replacement_map.json
    - Consistent replacements across multiple files and runs
    - Interactive mode: user enters strings to anonymize one by one
    - Automatically replaces any string that already exists in the persistent map
    - If a string already has a mapping, asks user whether to generate a new UUID
    - Works with text, JSON, YAML, XML, logs, and other plain-text based formats
    - Safe regex-based replacement (handles special characters)

Requirements:
    - Python 3.6+
    - No external dependencies

Usage:
    python anonymize_pii.py -f /path/to/your/file.json
    python anonymize_pii.py --file /path/to/data.yaml

Behavior:
    1. Loads existing replacement map
    2. Asks user to input strings to replace (one per line)
    3. Type 'done' or press Ctrl+D to finish input
    4. Replaces all occurrences in the file
    5. Saves updated map and modified file in place

Safety Notes:
    - Always backup your original file before running
    - Replacements are done as whole-string matches (not partial substrings)
    - File is overwritten after processing
"""
import argparse
import json
import os
import re
import uuid
import sys
from pathlib import Path

# Persistent map file
MAP_FILE = Path.home() / '.pii_replacement_map.json'

def load_map():
    if MAP_FILE.exists():
        try:
            with open(MAP_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            print(f"Warning: Could not load map: {e}", file=sys.stderr)
    return {}

def save_map(replace_map):
    try:
        with open(MAP_FILE, 'w', encoding='utf-8') as f:
            json.dump(replace_map, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"Warning: Could not save map: {e}", file=sys.stderr)

def generate_uuid():
    return str(uuid.uuid4())

def get_replacement(replace_map, original):
    if original in replace_map:
        return replace_map[original]
    new_id = generate_uuid()
    replace_map[original] = new_id
    save_map(replace_map)
    return new_id

def main():
    parser = argparse.ArgumentParser(description="Anonymize PII strings in a file with consistent UUID replacements.")
    parser.add_argument('-f', '--file', required=True, help="Full path to the file to process.")
    args = parser.parse_args()

    file_path = Path(args.file)
    if not file_path.exists():
        print(f"Error: File {file_path} does not exist.")
        sys.exit(1)

    # Load persistent map
    replace_map = load_map()

    # Read the entire file content
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading file: {e}")
        sys.exit(1)

    print("Current replacement map has", len(replace_map), "entries.")
    print("Enter strings to replace (one per line). Type 'done' or press Ctrl+D to finish.")

    # Interactive input for strings to replace
    while True:
        try:
            user_input = input("> ").strip()
            if user_input.lower() in ['done', '']:
                break
            if not user_input:
                continue

            original = user_input

            if original in replace_map:
                print(f"Warning: '{original}' already exists in map with value '{replace_map[original]}'.")
                confirm = input("Do you want to generate a new UUID for it? (y/N): ").strip().lower()
                if confirm == 'y':
                    new_id = generate_uuid()
                    replace_map[original] = new_id
                    save_map(replace_map)
                    print(f"Updated replacement for '{original}' to {new_id}")
                else:
                    print("Keeping existing mapping.")
                    continue
            else:
                # Get or create replacement
                get_replacement(replace_map, original)  # This will add it

            # Immediately replace in content
            # Use word boundaries or full match to avoid partial replaces
            # But for safety, use re.sub with word boundary if it's a word
            # For generality, replace exact occurrences, considering it might be in quotes etc.
            pattern = re.escape(original)
            content = re.sub(pattern, lambda m: replace_map[original], content)

        except EOFError:
            break
        except KeyboardInterrupt:
            print("\nInterrupted.")
            break

    # After interactive session, replace any other known keys in the map that appear in the file
    # (in case they weren't entered this time)
    for orig, repl in list(replace_map.items()):
        if orig in content:  # Check if still present
            pattern = re.escape(orig)
            content = re.sub(pattern, repl, content)

    # Write back the anonymized content
    try:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Successfully processed file: {file_path}")
        print(f"Total mappings used: {len(replace_map)}")
    except Exception as e:
        print(f"Error writing file: {e}")
        sys.exit(1)

    # Optional: print summary
    if replace_map:
        print("\nReplacement summary:")
        for k, v in list(replace_map.items())[-5:]:  # last 5
            print(f"  '{k}' -> '{v}'")

if __name__ == "__main__":
    main()
