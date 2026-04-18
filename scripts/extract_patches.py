#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path


def normalize_instance_id(raw: str) -> str:
    """Normalize both formats to the canonical `org__repo-number` form."""
    # Already canonical: fasterxml__jackson-core-183
    if "__" in raw:
        return raw
    # Alternative: fasterxml/jackson-core:pr-183
    m = re.fullmatch(r"([^/]+)/([^:]+):pr-(\d+)", raw)
    if m:
        org, repo, number = m.group(1), m.group(2), m.group(3)
        return f"{org}__{repo}-{number}"
    raise ValueError(f"Unrecognized instance_id format: {raw!r}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract per-instance patches from a metamorphic benchmark JSONL."
    )
    parser.add_argument("-i", "--input", required=True, help="Input JSONL file")
    parser.add_argument("-o", "--output", required=True, help="Output directory")
    parser.add_argument(
        "--instance_ids",
        default=None,
        help="Comma-separated list of instance IDs to extract (omit to extract all)",
    )
    args = parser.parse_args()

    target_ids: set[str] | None = (
        {
            normalize_instance_id(s.strip())
            for s in args.instance_ids.split(",")
            if s.strip()
        }
        if args.instance_ids is not None
        else None
    )

    output_root = Path(args.output)
    input_path = Path(args.input)

    if not input_path.exists():
        sys.exit(f"Input file not found: {input_path}")

    found: set[str] = set()

    with input_path.open() as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError as exc:
                sys.exit(f"JSON parse error on line {lineno}: {exc}")

            iid = entry.get("instance_id", "")
            if target_ids is not None and iid not in target_ids:
                continue

            base_patch = (entry.get("base") or {}).get("metamorphic_base_patch", "")
            fix_patch = entry.get("fix_patch", "")
            test_patch = entry.get("test_patch", "")

            out_dir = output_root / iid
            out_dir.mkdir(parents=True, exist_ok=True)

            (out_dir / "base.patch").write_text(base_patch)
            (out_dir / "fix.patch").write_text(fix_patch)
            (out_dir / "test.patch").write_text(test_patch)

            found.add(iid)
            print(f"Extracted: {iid}")

    if target_ids is not None:
        missing = target_ids - found
        if missing:
            for iid in sorted(missing):
                print(f"Warning: not found in input: {iid}", file=sys.stderr)
        print(f"\nDone. {len(found)}/{len(target_ids)} instances extracted to {output_root}")
    else:
        print(f"\nDone. {len(found)} instances extracted to {output_root}")


if __name__ == "__main__":
    main()
