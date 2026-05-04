"""Select a subset of benchmark entries from a JSONL file by instance ID."""

import argparse
import json
import re
import sys


def to_agent_format(instance_id: str) -> str:
    """Normalize an instance ID to agent format: org__repo-number."""
    # eval format: fasterxml/jackson-databind:pr-1923
    match = re.fullmatch(r"([^/]+)/([^:]+):pr-(\d+)", instance_id)
    if match:
        org, repo, number = match.groups()
        return f"{org}__{repo}-{number}"
    # already agent format: fasterxml__jackson-databind-1923
    return instance_id


def main():
    parser = argparse.ArgumentParser(description="Select benchmark entries by instance ID.")
    parser.add_argument("-i", "--input", required=True, help="Input JSONL file.")
    parser.add_argument("-o", "--output", required=True, help="Output JSONL file.")
    parser.add_argument(
        "--instance_ids",
        required=True,
        help="Comma-separated instance IDs (eval or agent format).",
    )
    args = parser.parse_args()

    wanted = {to_agent_format(iid.strip()) for iid in args.instance_ids.split(",") if iid.strip()}

    matched: list[dict] = []
    with open(args.input) as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError as e:
                print(f"Warning: skipping malformed JSON on line {lineno}: {e}", file=sys.stderr)
                continue
            if entry.get("instance_id") in wanted:
                matched.append(entry)

    found_ids = {e["instance_id"] for e in matched}
    missing = wanted - found_ids
    if missing:
        print(f"Warning: {len(missing)} instance ID(s) not found: {', '.join(sorted(missing))}", file=sys.stderr)

    with open(args.output, "w") as f:
        for entry in matched:
            f.write(json.dumps(entry) + "\n")

    print(f"Wrote {len(matched)} entries to {args.output}")


if __name__ == "__main__":
    main()
