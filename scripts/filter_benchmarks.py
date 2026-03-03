import json
import argparse
from pathlib import Path


def filter_by_language(input_path, language, output_path, difficulty=None):
    """
    Filter JSONL file entries by programming language.

    Args:
        input_path: Path to input JSONL file
        language: Programming language to filter by (e.g., 'java', 'c', 'cpp')
        output_path: Path to output JSONL file
        difficulty: Optional difficulty level to filter by (e.g., 'easy', 'medium', 'hard')
    """
    input_file = Path(input_path)
    output_file = Path(output_path)

    if not input_file.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    # Create output directory if it doesn't exist
    output_file.parent.mkdir(parents=True, exist_ok=True)

    filtered_count = 0
    total_count = 0

    with open(input_file, 'r', encoding='utf-8') as infile, \
         open(output_file, 'w', encoding='utf-8') as outfile:

        for line in infile:
            total_count += 1
            try:
                entry = json.loads(line.strip())
                if entry.get('language') == language:
                    if difficulty is None or entry.get('difficulty') == difficulty:
                        outfile.write(json.dumps(entry) + '\n')
                        filtered_count += 1
            except json.JSONDecodeError as e:
                print(f"Warning: Skipping invalid JSON on line {total_count}: {e}")

    print(f"Processed {total_count} entries")
    print(f"Filtered {filtered_count} entries for language '{language}'" +
          (f" and difficulty '{difficulty}'" if difficulty else ""))
    print(f"Output written to: {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description='Filter JSONL file by programming language'
    )
    parser.add_argument(
        '-i', '--input_file',
        help='Path to input JSONL file',
        required=True
    )
    parser.add_argument(
        '-l', '--language',
        help='Programming language to filter by (e.g., java, c, cpp)',
        required=True
    )
    parser.add_argument(
        '-o', '--output_file',
        help='Path to output JSONL file',
        required=True
    )
    parser.add_argument(
        '-d', '--difficulty',
        help='Optional difficulty level to filter by (e.g., easy, medium, hard)',
        choices=['easy', 'medium', 'hard'],
        required=False
    )

    args = parser.parse_args()

    filter_by_language(args.input_file, args.language, args.output_file, args.difficulty)


if __name__ == '__main__':
    main()
