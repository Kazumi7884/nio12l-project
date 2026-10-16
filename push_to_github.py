#!/usr/bin/env python3
"""
push_to_github.py — Push local git files to GitHub via the Contents API
Uses gh CLI's internal token to authenticate (bypasses broken MSYS2 git DNS).
"""
import subprocess
import json
import base64
import os
import sys
from pathlib import Path

# Get GitHub token from gh CLI
result = subprocess.run(
    ["gh", "api", "user"],
    capture_output=True, text=True, timeout=30
)
if result.returncode != 0:
    print("ERROR: gh API not working. Cannot get token.")
    sys.exit(1)

# Get token via gh auth
token_result = subprocess.run(
    ["gh", "auth", "token"],
    capture_output=True, text=True, timeout=30
)
if token_result.returncode != 0:
    print("ERROR: Cannot get gh token.")
    sys.exit(1)

TOKEN = token_result.stdout.strip()
if not TOKEN:
    print("ERROR: Empty token.")
    sys.exit(1)

OWNER = "Kazumi7884"
REPO = "nio12l-project"
BRANCH = "main"
PROJECT_DIR = Path(r"C:\Users\jamie\nio12l-project")

# Get all tracked files
result = subprocess.run(
    ["git", "ls-files"],
    capture_output=True, text=True, timeout=30,
    cwd=PROJECT_DIR
)
files = [f for f in result.stdout.strip().split("\n") if f and f != ".gitignore"]

print(f"Will push {len(files)} files to {OWNER}/{REPO}:{BRANCH}")

success = 0
failed = 0

for filepath in files:
    full_path = PROJECT_DIR / filepath
    if not full_path.exists():
        print(f"  SKIP (missing): {filepath}")
        continue

    content = full_path.read_bytes()
    b64 = base64.b64encode(content).decode("ascii")

    payload = json.dumps({
        "message": f"Add {filepath}",
        "content": b64,
        "branch": BRANCH
    })

    # Use gh api to call GitHub Contents API
    result = subprocess.run(
        ["gh", "api", "-X", "PUT",
         f"/repos/{OWNER}/{REPO}/contents/{filepath}",
         "-f", f"message=Add {filepath}",
         "-f", f"content={b64}",
         "-f", f"branch={BRANCH}"],
        capture_output=True, text=True, timeout=60
    )

    if result.returncode == 0:
        print(f"  OK: {filepath}")
        success += 1
    else:
        # Try without special chars
        err = json.loads(result.stderr.strip()) if result.stderr else {}
        msg = err.get("message", result.stderr[:200])
        if "already exists" in msg:
            # File exists - need to update with SHA
            sha_result = subprocess.run(
                ["gh", "api", f"/repos/{OWNER}/{REPO}/contents/{filepath}?ref={BRANCH}"],
                capture_output=True, text=True, timeout=30
            )
            try:
                sha_info = json.loads(sha_result.stdout)
                sha = sha_info.get("sha", "")
                if sha:
                    result = subprocess.run(
                        ["gh", "api", "-X", "PUT",
                         f"/repos/{OWNER}/{REPO}/contents/{filepath}",
                         "-f", f"message=Update {filepath}",
                         "-f", f"content={b64}",
                         "-f", f"branch={BRANCH}",
                         "-f", f"sha={sha}"],
                        capture_output=True, text=True, timeout=60
                    )
                    if result.returncode == 0:
                        print(f"  OK (updated): {filepath}")
                        success += 1
                    else:
                        print(f"  FAIL: {filepath} — {result.stderr[:200]}")
                        failed += 1
                else:
                    print(f"  FAIL: {filepath} — no SHA found")
                    failed += 1
            except Exception as e:
                print(f"  FAIL: {filepath} — {e}")
                failed += 1
        else:
            print(f"  FAIL: {filepath} — {msg[:150]}")
            failed += 1

print(f"\n=== Results: {success} success, {failed} failed ===")
