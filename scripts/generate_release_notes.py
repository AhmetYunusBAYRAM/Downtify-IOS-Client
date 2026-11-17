#!/usr/bin/env python3
"""Package About page release notes.

A curated release-notes/<MARKETING_VERSION>-<CURRENT_PROJECT_VERSION>.json file wins when
present (used for release builds from main). Otherwise list branch commit subjects since
the merge base with main.
"""

import json
import os
import subprocess
import sys
from pathlib import Path


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def main() -> None:
    repo = Path(sys.argv[1])
    output = Path(sys.argv[2])
    version = os.environ.get("MARKETING_VERSION"), os.environ.get("CURRENT_PROJECT_VERSION")
    if all(version):
        curated = repo / "release-notes" / f"{version[0]}-{version[1]}.json"
        if curated.is_file():
            notes = json.loads(curated.read_text())
            assert isinstance(notes, list) and all(isinstance(n, str) for n in notes)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(notes, ensure_ascii=False, indent=2) + "\n")
            return
    try:
        base = git(repo, "rev-parse", "--verify", "refs/remotes/origin/main")
    except subprocess.CalledProcessError:
        base = git(repo, "rev-parse", "--verify", "refs/heads/main")
    fork = git(repo, "merge-base", base, "HEAD")
    changed = git(repo, "diff", "--name-only", fork, "HEAD")
    notes = []
    if changed:
        notes = [line for line in git(repo, "log", "--reverse", "--no-merges", "--format=%s", f"{fork}..HEAD").splitlines() if line]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(notes, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
