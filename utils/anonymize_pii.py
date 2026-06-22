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
