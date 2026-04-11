import argparse
import json
import re
import os
import sys
from pathlib import Path


#!/usr/bin/env python3

"""
Script Name: script.py
Description: Convert JSONL format from model predictions to fix patch format.
             Extracts org, repo, and issue number from instance_id.
Author: Your Name
Date: YYYY-MM-DD
"""

INSTANCE_ID_PATTERN = re.compile(r"^(.+?)__(.+?)-(\d+)$")


def parse_instance_id(instance_id: str) -> tuple[str, str, int]:
    """
    Parse instance_id to extract org, repo, and number.

    Args:
        instance_id: String in format "org__repo-number"

    Returns:
        Tuple of (org, repo, number)

    Raises:
        ValueError: If instance_id doesn't match expected format
    """
    match = INSTANCE_ID_PATTERN.match(instance_id)
    if not match:
        raise ValueError(f"Invalid instance_id format: {instance_id}. Expected format: `[org]__[repo]-[number]`")

    org, repo, number = match.groups()
    return org, repo, int(number)


def convert_entry(entry: dict, input_type: str = "model") -> dict:
    """
    Convert a single entry from input schema to output schema.

    Args:
        entry: Dict with keys: model_name_or_path, instance_id, model_patch (model)
               or org, repo, number, fix_patch (benchmark)
        input_type: "model" (default) or "benchmark"

    Returns:
        Dict with keys: org, repo, number, fix_patch (and model_name_or_path for model type)
    """
    org, repo, number = parse_instance_id(entry["instance_id"])

    if input_type == "benchmark":
        return {
            "org": org,
            "repo": repo,
            "number": number,
            "fix_patch": entry["fix_patch"]
        }

    return {
        "org": org,
        "repo": repo,
        "number": number,
        "model_name_or_path": entry["model_name_or_path"],
        "fix_patch": entry["model_patch"]
    }


def convert_jsonl(input_path: str, output_path: str, input_type: str = "model") -> None:
    """
    Convert JSONL file from input schema to output schema.

    Args:
        input_path: Path to input JSONL file
        output_path: Path to output JSONL file
        input_type: "model" (default) or "benchmark"
    """
    input_file = Path(input_path)
    output_file = Path(output_path)

    if not input_file.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    # Create output directory if it doesn't exist
    output_file.parent.mkdir(parents=True, exist_ok=True)

    converted_count = 0
    error_count = 0

    with input_file.open('r', encoding='utf-8') as infile, \
         output_file.open('w', encoding='utf-8') as outfile:

        for line_num, line in enumerate(infile, 1):
            line = line.strip()
            if not line:
                continue

            try:
                entry = json.loads(line)
                converted_entry = convert_entry(entry, input_type)
                outfile.write(json.dumps(converted_entry) + '\n')
                converted_count += 1

            except (json.JSONDecodeError, KeyError, ValueError) as e:
                print(f"Error processing line {line_num}: {e}")
                error_count += 1
                continue

    print(f"Conversion complete!")
    print(f"  Converted: {converted_count} entries")
    print(f"  Errors: {error_count} entries")
    print(f"  Output: {output_path}")


def main():
    """
    Main function of the script.
    """
    parser = argparse.ArgumentParser(
        description=
        "Convert JSONL format from model predictions (all_pred.jsonl from trajectories) to fix patch format expected by multi_swe_bench evaluation."
    )
    parser.add_argument(
        "-i", "--input",
        required=True,
        help="Path to input JSONL file"
    )
    parser.add_argument(
        "-o", "--output",
        required=True,
        help="Path to output JSONL file"
    )
    parser.add_argument(
        "-t", "--input-type",
        choices=["model", "benchmark"],
        default="model",
        help="Input format: 'model' (all_preds.jsonl from MSWE-agent, default) or 'benchmark' (benchmark JSONL with fix_patch)"
    )

    args = parser.parse_args()

    try:
        convert_jsonl(args.input, args.output, args.input_type)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()