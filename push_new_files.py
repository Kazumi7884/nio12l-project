#!/usr/bin/env python3
"""Push new files to GitHub via Contents API."""
import subprocess
import json
import base64
import sys
from pathlib import Path

token_result = subprocess.run(
    ["gh", "auth", "token"],
    capture_output=True, text=True, timeout=30
)
TOKEN = token_result.stdout.strip()

OWNER = "Kazumi7884"
REPO = "nio12l-project"
BRANCH = "main"
PROJECT_DIR = Path(r"C:\Users\jamie\nio12l-project")

files_to_push = [
    "LICENSE",
    ".gitignore",
    "ai-toolkit/nio12l-benchmark.sh",
    "README.md",
]

for filepath in files_to_push:
    full_path = PROJECT_DIR / filepath
    if not full_path.exists():
        print(f"SKIP (missing): {filepath}")
        continue

    content = full_path.read_bytes()
    b64 = base64.b64encode(content).decode("ascii")

    result = subprocess.run(
        ["gh", "api", "-X", "PUT",
         f"/repos/{OWNER}/{REPO}/contents/{filepath}",
         "-f", f"message=Add {filepath}",
         "-f", f"content={b64}",
         "-f", f"branch={BRANCH}"],
        capture_output=True, text=True, timeout=60
    )

    if result.returncode == 0:
        print(f"OK: {filepath}")
    else:
        err = json.loads(result.stderr.strip()) if result.stderr else {}
        print(f"FAIL: {filepath} — {err.get('message', result.stderr[:150])}")
