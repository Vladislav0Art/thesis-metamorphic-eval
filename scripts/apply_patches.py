"""Apply metamorphic_base_patch to each benchmark instance and verify fix/test patches."""

import argparse
import logging
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from common.cli import run_cli_command
from common.fs import read_jsonl
from common.git import apply_patch, build_github_url, clone_repository, commit_all_changes
from common.logger import configure_logging

configure_logging("apply_patches.log")
logger = logging.getLogger(__name__)

_FIX_RUN_SH = """\
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$SCRIPT_DIR/repo"
cd "$REPO_DIR"

> "$SCRIPT_DIR/verdict.txt"

ERR=$(git apply --whitespace=nowarn "$SCRIPT_DIR/fix.patch" 2>&1)
if [ $? -ne 0 ]; then
    printf "FAILED (fix.patch):\\n%s" "$ERR" >> "$SCRIPT_DIR/verdict.txt"
    exit 1
fi
echo "PASSED (fix.patch)" >> "$SCRIPT_DIR/verdict.txt"

ERR=$(git apply --whitespace=nowarn "$SCRIPT_DIR/test.patch" 2>&1)
if [ $? -ne 0 ]; then
    printf "FAILED (test.patch):\\n%s" "$ERR" >> "$SCRIPT_DIR/verdict.txt"
    exit 1
fi
echo "PASSED (test.patch)" >> "$SCRIPT_DIR/verdict.txt"
"""


def to_agent_format(instance_id: str) -> str:
    match = re.fullmatch(r"([^/]+)/([^:]+):pr-(\d+)", instance_id)
    if match:
        org, repo, number = match.groups()
        return f"{org}__{repo}-{number}"
    return instance_id


def _process_instance(entry: dict, repos_dir: str) -> tuple[bool, str]:
    """Process one benchmark instance. Returns (passed, verdict_path)."""
    instance_id = entry.get("instance_id", "<unknown>")
    base = entry.get("base", {})
    org = entry.get("org")
    repo = entry.get("repo")
    base_sha = base.get("sha")
    metamorphic_base_patch = base.get("metamorphic_base_patch")
    fix_patch = entry.get("fix_patch", "")
    test_patch = entry.get("test_patch", "")

    missing = [f for f, v in [
        ("org", org), ("repo", repo), ("base.sha", base_sha),
        ("base.metamorphic_base_patch", metamorphic_base_patch),
    ] if not v]
    if missing:
        logger.error(f"[{instance_id}] Missing required fields: {', '.join(missing)}")
        return False, ""

    strategy = base.get("strategy")
    instance_dir = os.path.join(repos_dir, strategy, instance_id) if strategy else os.path.join(repos_dir, instance_id)
    repo_dir = os.path.join(instance_dir, "repo")
    os.makedirs(instance_dir, exist_ok=True)

    repo_url = build_github_url(org, repo)
    if not clone_repository(repo_url, repo_dir, base_sha, logger):
        return False, ""

    if not apply_patch(repo_dir, metamorphic_base_patch, logger):
        logger.error(f"[{instance_id}] Failed to apply metamorphic_base_patch")
        return False, ""

    commit_msg = f"[script]: apply metamorphic_base_patch to {base_sha}"
    if not commit_all_changes(repo_dir, commit_msg, logger):
        logger.error(f"[{instance_id}] Failed to commit metamorphic_base_patch")
        return False, ""

    # Write patch files
    for filename, content in [
        ("metamorphic_base.patch", metamorphic_base_patch),
        ("fix.patch", fix_patch),
        ("test.patch", test_patch),
    ]:
        path = os.path.join(instance_dir, filename)
        with open(path, "w") as f:
            f.write(content)

    # Write and chmod fix-run.sh
    fix_run_sh = os.path.join(instance_dir, "fix-run.sh")
    with open(fix_run_sh, "w") as f:
        f.write(_FIX_RUN_SH)
    run_cli_command("chmod", ["+x", fix_run_sh])

    # Run fix-run.sh
    logger.info(f"[{instance_id}] Running fix-run.sh")
    stdout, stderr, rc = run_cli_command("bash", [fix_run_sh])
    if stdout:
        logger.debug(f"[{instance_id}] fix-run stdout: {stdout}")
    if stderr:
        logger.debug(f"[{instance_id}] fix-run stderr: {stderr}")

    verdict_path = os.path.join(instance_dir, "verdict.txt")
    if not os.path.exists(verdict_path):
        logger.error(f"[{instance_id}] verdict.txt not found after running fix-run.sh")
        return False, verdict_path

    with open(verdict_path) as f:
        verdict = f.read().strip()

    passed = "FAILED" not in verdict
    logger.info(f"[{instance_id}] Verdict: {verdict}")
    return passed, verdict_path


def main():
    parser = argparse.ArgumentParser(
        description="Apply metamorphic_base_patch to benchmark repos and verify fix/test patches."
    )
    parser.add_argument("-i", "--input", required=True, help="Input JSONL dataset file.")
    parser.add_argument("-r", "--repos", required=True, help="Directory to mount cloned repos.")
    parser.add_argument(
        "--instance_ids",
        default=None,
        help="Comma-separated instance IDs to process (agent or eval format). "
             "If omitted, all entries in the input file are processed.",
    )
    args = parser.parse_args()

    entries = read_jsonl(args.input)

    if args.instance_ids:
        wanted = {to_agent_format(iid.strip()) for iid in args.instance_ids.split(",") if iid.strip()}
        entries = [e for e in entries if e.get("instance_id") in wanted]
        found = {e["instance_id"] for e in entries}
        missing = wanted - found
        if missing:
            logger.warning(f"Instance IDs not found in input: {', '.join(sorted(missing))}")

    if not entries:
        logger.error("No entries to process.")
        sys.exit(1)

    os.makedirs(args.repos, exist_ok=True)

    passed_ids: list[str] = []
    failed_ids: list[tuple[str, str]] = []  # (instance_id, verdict_path)

    for entry in entries:
        instance_id = entry.get("instance_id", "<unknown>")
        try:
            ok, verdict_path = _process_instance(entry, args.repos)
        except Exception as e:
            logger.exception(f"[{instance_id}] Unexpected error: {e}")
            ok, verdict_path = False, ""

        if ok:
            passed_ids.append(instance_id)
        else:
            failed_ids.append((instance_id, verdict_path))

    total = len(entries)
    n_passed = len(passed_ids)

    print(f"\nResults: {n_passed}/{total} passed")

    if passed_ids:
        print(f"\nPassed ({n_passed}):")
        for iid in passed_ids:
            print(f"  - {iid}")

    if failed_ids:
        print(f"\nFailed ({len(failed_ids)}):")
        for iid, vpath in failed_ids:
            suffix = f"  →  {vpath}" if vpath else ""
            print(f"  - {iid}{suffix}")


if __name__ == "__main__":
    main()
