#!/usr/bin/env python3
"""Stops a deploy if the content holds personal data or the repository holds a credential."""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PERSONAL = [
    ("email", re.compile(r"[\w.+-]+@(?![\w-]+\.example\b)[\w-]+\.[\w.-]+")),
    ("mobile", re.compile(r"(?<!\d)(?:\+?63|0)9\d{2}[\s-]?\d{3}[\s-]?\d{4}(?!\d)")),
]
SECRETS = re.compile(r"AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|gsk_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{30,}|sk-[A-Za-z0-9_-]{24,}|-----BEGIN [A-Z ]*PRIVATE KEY")

problems = []
for path in sorted((ROOT / "content").glob("*.md")):
    text = path.read_text()
    problems += [f"{path.name}: possible {label}" for label, rule in PERSONAL if rule.search(text)]

try:
    history = subprocess.run(["git", "-C", str(ROOT), "log", "--all", "-p"], capture_output=True, text=True, errors="replace", check=True).stdout
    tracked = subprocess.run(["git", "-C", str(ROOT), "grep", "-I", "-n", "-E", "AKIA[0-9A-Z]{16}"], capture_output=True, text=True).stdout
    if SECRETS.search(history) or tracked:
        problems.append("git history or tracked files: possible credential")
except (OSError, subprocess.CalledProcessError):
    problems.append("this folder is not a git repository yet: run git init and commit first")

if problems:
    print("Precheck failed:", *problems, sep="\n  ")
    sys.exit(1)
print("Precheck passed: no personal data in content, no credential patterns in git history.")
