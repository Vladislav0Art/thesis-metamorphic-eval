import argparse
import subprocess



description="""
This script accepts jsonl file with benchmarks and applies transformations via Code Codecoccoon.
The result patches after transformation are added into the entries of the given jsonl file and
save into the output file.

Arguments:
  -i, --input: Path to the input jsonl file containing benchmarks.
  -o, --output: Path to the output jsonl file where transformed benchmarks will be saved.
  -s, --strategy: The transformation strategy name
                  (the resulting transformations will be saved as entry['strategy']['metamorphic_base_patch'] and
                   entry['strategy']['metamorphic_fix_patch']).
  -c, --codecoccoon: Filepath to the Code Codecoccoon repository (its headless mode will be executed).
  -r, --repos: Filepath which the repositories from the input should be cloned into.

Usage:
python transform.py -i path/to/input.jsonl -o path/to/output.jsonl -s transformation_strategy_name -c path/to/codecoccoon
"""



def run_cli_command(command, args):
    """
    Runs a given CLI command with arguments and returns its output, error, and return code.

    Args:
        command (str): The CLI command to execute.
        args (list): A list of arguments for the command.

    Returns:
        tuple: A tuple containing stdout (str), stderr (str), and return code (int).
    """
    try:
        result = subprocess.run(
            [command] + args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False
        )
        return result.stdout, result.stderr, result.returncode
    except Exception as e:
        return "", str(e), -1



def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('-i', '--input', type=str, required=True,
                        help="Path to the input jsonl file containing benchmarks")
    parser.add_argument('-o', '--output', type=str, required=True,
                        help="Path to the output jsonl file where transformed benchmarks will be saved.")
    parser.add_argument('-s', '--strategy', type=str, help="""
        The transformation strategy name (the resulting transformations will be saved as
        entry['strategy']['metamorphic_base_patch'] and entry['strategy']['metamorphic_fix_patch']).
    """)
    parser.add_argument('-c', "--codecoccoon", type=str, help="Filepath to the Code Codecoccoon repository (its headless mode will be executed).")
    parser.add_argument('-r', '--repos', type=str, help="Filepath which the repositories from the input should be cloned into")

    args = parser.parse_args()

    print(f"""
    Given arguments:
      --input: {args.input}
      --output: {args.output}
      --strategy: {args.strategy}
      --codecoccoon: {args.codecoccoon}
      --repos: {args.repos}
    """)

    # Step 1: read entries from the input jsonl file one by one
    # Step 2: for each entry:
    #     - clone the repo into the given directory (if not already cloned)
    #     - extract filepaths of the changed files in the diffs (entry['fix_patch'] and entry['test_patch'])
    #     - generate codecocoon.yml file for the entry:
    #         - projectRoot: str = repos/entry['instance_id']
    #         - files: [str] = [filepaths of the changed files]
    #         - transformations: for now, default to renaming transformations
    #
    # Step 3: on the base commit of the entry:
    #     - execute CodeCoccoon in headless mode with the generated codecocoon.yml file
    #     - save the diff into entry['strategy']['metamorphic_base_patch']
    #
    #  Step 4: after fixing the bug of the entry:
    #     - apply entry['fix_patch'] and entry['test_patch'] to the repo
    #     - commit the changes into a separate branch (so that the diff after executing CodeCoccoon contains only the transformation)
    #     - execute CodeCoccoon in the headless mode with the same codecocoon.yml file
    #     - save the diff into entry['strategy']['metamorphic_fix_patch']
    #
    # Step 5: save the updated entries into the output jsonl file
    #
    # NOTES:
    # 1. Command to execute CodeCocoon: `./gradlew headless -Pcodecocoon.config=/path/to/codecocoon-config.yml` (wuth filepath to the codecoon.yml file generated for the entry)
    # 2. The output of the codecoon should also be saved into the resulting output jsonl as entry['strategy']['metamorphic_base_patch_log'] and entry['strategy']['metamorphic_fix_patch_log'] for the base and fix commits, respectively. This is important for debugging purposes. Also, save all transformation execute into the log file of this script!
    # 3. The schema of the input jsonl entries contains the following fields:
    """
    {
        "org": "mockito",
        "repo": "mockito",
        "number": 3129,
        "state": "closed",
        "base": {
            "label": "mockito:main",
            "ref": "main",
            "sha": "edc624371009ce981bbc11b7d125ff4e359cff7e"
        },
        "fix_patch": "string (git diff format)",
        "test_patch": "string (git diff format)",
        "instance_id": "string"
    }
    """
    # So, you need to build a github URL, clone the repo, and switch into the base commit mentioned in entry['base']['sha'].




if __name__ == "__main__":
    main()
