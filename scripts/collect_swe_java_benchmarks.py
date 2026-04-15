#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(
        description="Merge all JSONL files from a directory into a single JSONL file."
    )
    parser.add_argument("--input_dir", type=Path, help="Directory containing JSONL files")
    parser.add_argument("--output", type=Path, help="Output JSONL file path")
    args = parser.parse_args()

    jsonl_files = sorted(args.input_dir.glob("*.jsonl"))
    if not jsonl_files:
        print(f"No JSONL files found in {args.input_dir}")
        return

    args.output.parent.mkdir(parents=True, exist_ok=True)

    total = 0
    with args.output.open("w") as out:
        for path in jsonl_files:
            with path.open() as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    json.loads(line)  # validate
                    out.write(line + "\n")
                    total += 1

    print(f"Wrote {total} entries from {len(jsonl_files)} files to {args.output}")


if __name__ == "__main__":
    main()
