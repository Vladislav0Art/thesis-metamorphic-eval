import argparse
import subprocess
import json
import os
import re
import tempfile
import logging
from pathlib import Path
from typing import Dict, List, Tuple, Optional

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

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('transform.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


def run_cli_command(command, args, cwd=None):
    """
    Runs a given CLI command with arguments and returns its output, error, and return code.

    Args:
        command (str): The CLI command to execute.
        args (list): A list of arguments for the command.
        cwd (str): Working directory for the command.

    Returns:
        tuple: A tuple containing stdout (str), stderr (str), and return code (int).
    """
    try:
        full_command = [command] + args
        logger.debug(f"Executing: {' '.join(full_command)}")
        result = subprocess.run(
            full_command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            cwd=cwd
        )
        return result.stdout, result.stderr, result.returncode
    except Exception as e:
        logger.error(f"Command execution failed: {e}")
        return "", str(e), -1


def read_jsonl(filepath: str) -> List[Dict]:
    """Read entries from a JSONL file."""
    entries = []
    try:
        with open(filepath, 'r') as f:
            for line_num, line in enumerate(f, 1):
                try:
                    entries.append(json.loads(line.strip()))
                except json.JSONDecodeError as e:
                    logger.warning(f"Skipping malformed JSON at line {line_num}: {e}")
        logger.info(f"Read {len(entries)} entries from {filepath}")
        return entries
    except Exception as e:
        logger.error(f"Failed to read {filepath}: {e}")
        raise


def write_jsonl(filepath: str, entries: List[Dict]):
    """Write entries to a JSONL file."""
    try:
        with open(filepath, 'w') as f:
            for entry in entries:
                f.write(json.dumps(entry) + '\n')
        logger.info(f"Wrote {len(entries)} entries to {filepath}")
    except Exception as e:
        logger.error(f"Failed to write to {filepath}: {e}")
        raise


def extract_changed_files(patch: str) -> List[str]:
    """Extract file paths from a git diff patch."""
    files = []
    # Match lines like "diff --git a/path/to/file b/path/to/file"
    pattern = r'^diff --git a/(.*?) b/.*?$'
    for line in patch.split('\n'):
        match = re.match(pattern, line)
        if match:
            files.append(match.group(1))
    logger.debug(f"Extracted {len(files)} files from patch")
    return files


def clone_repository(repo_url: str, target_dir: str, sha: str) -> bool:
    """Clone a repository and checkout a specific commit."""
    try:
        if os.path.exists(target_dir):
            logger.info(f"Repository already exists at {target_dir}")
            # Ensure we're on the correct commit
            stdout, stderr, code = run_cli_command('git', ['checkout', sha], cwd=target_dir)
            if code != 0:
                logger.error(f"Failed to checkout {sha}: {stderr}")
                return False
            return True

        logger.info(f"Cloning {repo_url} to {target_dir}")
        stdout, stderr, code = run_cli_command('git', ['clone', repo_url, target_dir])
        if code != 0:
            logger.error(f"Failed to clone repository: {stderr}")
            return False

        stdout, stderr, code = run_cli_command('git', ['checkout', sha], cwd=target_dir)
        if code != 0:
            logger.error(f"Failed to checkout {sha}: {stderr}")
            return False

        logger.info(f"Successfully cloned and checked out {sha}")
        return True
    except Exception as e:
        logger.error(f"Repository cloning failed: {e}")
        return False


def apply_patch(repo_dir: str, patch: str) -> bool:
    """Apply a git patch to a repository."""
    try:
        # Write patch to temporary file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.patch', delete=False) as f:
            f.write(patch)
            patch_file = f.name

        try:
            stdout, stderr, code = run_cli_command('git', ['apply', patch_file], cwd=repo_dir)
            if code != 0:
                logger.error(f"Failed to apply patch: {stderr}")
                return False
            logger.debug(f"Patch applied successfully: {stdout}")
            return True
        finally:
            os.unlink(patch_file)
    except Exception as e:
        logger.error(f"Patch application failed: {e}")
        return False


def create_diff(repo_dir: str) -> Optional[str]:
    """Create a git diff of all changes in the repository."""
    try:
        stdout, stderr, code = run_cli_command('git', ['diff', 'HEAD'], cwd=repo_dir)
        if code != 0:
            logger.error(f"Failed to create diff: {stderr}")
            return None
        return stdout
    except Exception as e:
        logger.error(f"Diff creation failed: {e}")
        return None


def commit_changes(repo_dir: str, branch_name: str, message: str) -> bool:
    """Commit all changes to a new branch."""
    try:
        # Add all changes
        stdout, stderr, code = run_cli_command('git', ['add', '-A'], cwd=repo_dir)
        if code != 0:
            logger.error(f"Failed to stage changes: {stderr}")
            return False

        # Create and checkout new branch
        stdout, stderr, code = run_cli_command('git', ['checkout', '-b', branch_name], cwd=repo_dir)
        if code != 0:
            logger.error(f"Failed to create branch: {stderr}")
            return False

        # Commit changes
        stdout, stderr, code = run_cli_command('git', ['commit', '-m', message], cwd=repo_dir)
        if code != 0:
            logger.error(f"Failed to commit: {stderr}")
            return False

        logger.info(f"Changes committed to branch {branch_name}")
        return True
    except Exception as e:
        logger.error(f"Commit failed: {e}")
        return False


def generate_codecocoon_config(project_root: str, files: List[str], output_path: str):
    """Generate a codecocoon.yml configuration file."""
    config = {
        'projectRoot': project_root,
        'files': files,
        # TODO: provide a list of transformations to apply
        'transformations': [
            {
                'id': 'add-comment-transformation',
                'config': {
                    'message': 'Hello from `add-comment-transformation`!'
                }
            }
        ]
    }

    try:
        import yaml
        logger.info("`yaml` successfully imported. Using PyYAML to generate codecocoon config")
        with open(output_path, 'w') as f:
            yaml.dump(config, f, default_flow_style=False)
        logger.info(f"Generated codecocoon config at {output_path} with content:\n```\n{yaml.dump(config)}\n```")
    except ImportError:
        logger.info("Failed to import `yaml`. Fallack back to manual dumping of codecocoon config")
        # Fallback to manual YAML writing if PyYAML not available
        with open(output_path, 'w') as f:
            f.write(f"projectRoot: \"{project_root}\"\n")
            f.write(f"files:\n")
            for file in files:
                f.write(f"  - \"{file}\"\n")
            # TODO: provide a list of transformations to apply
            f.write("transformations:\n")
            f.write("  - id: \"add-comment-transformation\"\n")
            f.write("    config:\n")
            f.write("      message: \"Hello from `add-comment-transformation`!\"\n")
        logger.info(f"Generated codecocoon config at {output_path} (fallback)")


def execute_codecocoon(codecocoon_dir: str, config_path: str) -> Tuple[str, str, int]:
    """Execute CodeCocoon in headless mode."""
    logger.info(f"Executing CodeCocoon with config {config_path}")
    stdout, stderr, code = run_cli_command(
        './gradlew',
        ['headless', f'-Pcodecocoon.config={config_path}'],
        cwd=codecocoon_dir
    )
    return stdout, stderr, code


def insert_metamorphic_log(where: Dict, strategy: str, label: str, applied_to: str, result: Dict):
    """
    Inserts a log entry for a metamorphic transformation result.

    The insertion will have the following structure (appended into the "logs" array):
    ```
    where["strategy"]["logs"] = [
        {
            "applied_to": applied_to,  # e.g., 'base' or 'fix'
            "label": label,
            "result": {
                "stdout": result['stdout'],
                "stderr": result['stderr'],
                "return_code": result['return_code']
            }
        }
    ]
    ```
    If the "logs" array does not exist for the strategy, it will be created.

    Arguments:
      - where: The dictionary where the log should be inserted (should be `entry['metamorphic']`).
      - strategy: The transformation strategy name (any string, given as an input).
      - label: any string literal meaningful for the log.
      - applied_to: A string indicating whether this log is for the 'base' (i.e., on the base commit)
                    or 'fix' (i.e., after applying both test+fix patches) transformation.
      - result: A dictionary containing the result of the transformation execution, with keys:
                - "stdout": The standard output from executing CodeCocoon.
                - "stderr": The standard error from executing CodeCocoon.
                - "return_code": The return code from executing CodeCocoon.
    """
    if strategy not in where:
        where[strategy] = {}

    if "logs" not in where[strategy]:
        where[strategy]["logs"] = []

    log_entry = {
        "applied_to": applied_to,
        "label": label,
        "result": result
    }
    where[strategy]["logs"].append(log_entry)
    logger.info("Successfully inserted metamorphic log entry for strategy '%s' applied to '%s'", strategy, applied_to)


def build_github_url(org: str, repo: str) -> str:
    """Build GitHub repository URL."""
    return f"https://github.com/{org}/{repo}.git"


def process_entry(entry: Dict, strategy: str, codecocoon_dir: str, repos_dir: str) -> Dict:
    """Process a single entry through the transformation pipeline."""
    instance_id = entry['instance_id']
    logger.info(f"Processing entry: {instance_id}")

    # Initialize strategy dict if not present
    if "metamorphic" not in entry:
        entry["metamorphic"] = {}
    # Strategy-specific dict for storing transformation results
    metamorphic = entry["metamorphic"]

    if strategy not in metamorphic:
        metamorphic[strategy] = {}

    try:
        # Step 1: Clone repository
        repo_url = build_github_url(entry['org'], entry['repo'])

        # repo_dir=repos_dir/instance_id/repo
        repo_dir = os.path.join(repos_dir, instance_id, "repo")
        base_sha = entry['base']['sha']

        if not clone_repository(repo_url, repo_dir, base_sha):
            logger.error(f"Failed to clone repository for {instance_id}")
            return entry

        # Step 2: Extract changed files
        # TODO: should the test files be present in the yaml config for CodeCoccoon?
        fix_files = extract_changed_files(entry.get('fix_patch', ''))
        test_files = extract_changed_files(entry.get('test_patch', ''))
        all_files = list(set(fix_files + test_files))

        all_files_joined = ''.join(list(map(lambda file: f"\n   - {file}", all_files)))
        logger.info(f"Extracted {len(all_files)} unique changed files for {instance_id}:{all_files_joined}")

        if not all_files:
            logger.warning(f"No files found in patches for {instance_id}")
            return entry


        # Step 3: Generate CodeCocoon config

        # config_path=repos_dir/instance_id/codecocoon.yml
        config_path = os.path.join(repos_dir, instance_id, "codecocoon.yml")
        generate_codecocoon_config(repo_dir, all_files, config_path)

        # Step 4: Execute CodeCocoon on base commit
        logger.info(f"Transforming base commit for {instance_id}")
        stdout, stderr, code = execute_codecocoon(codecocoon_dir, config_path)
        insert_metamorphic_log(
            where=metamorphic,
            strategy=strategy,
            label='metamorphic_base_patch_log',
            applied_to='base',
            result={
                "stdout": stdout,
                "stderr": stderr,
                "return_code": code,
            }
        )

        if code == 0:
            base_diff = create_diff(repo_dir)
            if base_diff:
                metamorphic[strategy]['metamorphic_base_patch'] = base_diff
                logger.info(f"Base transformation successful for {instance_id}")
            else:
                logger.warning(f"Failed to create base diff for {instance_id}")
        else:
            logger.error(f"CodeCocoon failed on base commit for {instance_id}: {stderr}")


        # Step 5: Reset and apply fix/test patches
        stdout, stderr, code = run_cli_command('git', ['reset', '--hard', 'HEAD'], cwd=repo_dir)
        if code != 0:
            logger.error(f"Failed to reset repository for {instance_id}")
            return entry

        if not apply_patch(repo_dir, entry.get('fix_patch', '')):
            logger.error(f"Failed to apply fix patch for {instance_id}")
            return entry

        if not apply_patch(repo_dir, entry.get('test_patch', '')):
            logger.error(f"Failed to apply test patch for {instance_id}")
            return entry

        # Commit changes to separate branch
        if not commit_changes(repo_dir, f"fix-{instance_id}", "Apply fix and test patches"):
            logger.error(f"Failed to commit changes for {instance_id}")
            return entry

        # Step 6: Execute CodeCocoon on fixed commit
        logger.info(f"Transforming fix commit for {instance_id}")
        stdout, stderr, code = execute_codecocoon(codecocoon_dir, config_path)
        insert_metamorphic_log(
            where=metamorphic,
            strategy=strategy,
            label='metamorphic_fix_patch_log',
            applied_to='fix',
            result={
                "stdout": stdout,
                "stderr": stderr,
                "return_code": code,
            }
        )

        if code == 0:
            fix_diff = create_diff(repo_dir)
            if fix_diff:
                metamorphic[strategy]['metamorphic_fix_patch'] = fix_diff
                logger.info(f"Fix transformation successful for {instance_id}")
            else:
                logger.warning(f"Failed to create fix diff for {instance_id}")
        else:
            logger.error(f"CodeCocoon failed on fix commit for {instance_id}: {stderr}")

    except Exception as e:
        logger.error(f"Failed to process {instance_id}: {e}", exc_info=True)

    return entry


def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description=description, formatter_class=argparse.RawDescriptionHelpFormatter)
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

    # Validate arguments
    if not os.path.exists(args.input):
        logger.error(f"Input file does not exist: {args.input}")
        return

    if not os.path.exists(args.codecoccoon):
        logger.error(f"CodeCocoon directory does not exist: {args.codecoccoon}")
        return

    # Create repos directory if it doesn't exist
    os.makedirs(args.repos, exist_ok=True)

    logger.info(f"""Given arguments:
      --input: {args.input}
      --output: {args.output}
      --strategy: {args.strategy}
      --codecoccoon: {args.codecoccoon}
      --repos: {args.repos}
    """)

    # CodeCocoon existence check (validate that the provided path is a directory and contains expected files)
    if not os.path.exists(args.codecoccoon):
        raise ValueError(f"CodeCocoon directory does not exist: {args.codecoccoon}. Directory path to the Code Codecoccoon Plugin repository expected (its headless mode will be executed) and should be provided via `--codecoccoon` argument.")
    if not os.path.isdir(args.codecoccoon):
        raise ValueError(f"Provided CodeCocoon path is not a directory: {args.codecoccoon}. Directory path to the Code Codecoccoon Plugin repository expected (its headless mode will be executed) and should be provided via `--codecoccoon` argument.")

    if args.strategy is None or len(args.strategy) <= 0:
        raise ValueError(f"Received malformed transformation strategy: '{args.strategy}'. Transformation strategy name must be provided via `--strategy` argument and should be a non-empty string (e.g., 'default')")

    logger.info(f"Creating repos directory if doesn't exist already at: {args.repos}")
    Path(args.repos).mkdir(parents=True, exist_ok=True)

    # Read input entries
    entries = read_jsonl(args.input)

    # Process each entry
    processed_entries = []
    for i, entry in enumerate(entries, 1):
        instance_id = entry["instance_id"]
        logger.info("==========================================================================")
        logger.info(f"====== ⌛ Processing entry '{instance_id}' ({i}/{len(entries)}) ======")

        processed_entry = process_entry(entry, args.strategy, args.codecoccoon, args.repos)
        processed_entries.append(processed_entry)

        logger.info(f"====== ✅ Completed entry '{instance_id}' ({i}/{len(entries)}) ======")
        logger.info("==========================================================================")

    # Write output
    write_jsonl(args.output, processed_entries)
    logger.info("Processing complete!")


if __name__ == "__main__":
    main()
