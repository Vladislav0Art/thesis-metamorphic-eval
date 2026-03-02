import argparse
import json
import os
import re
import yaml
import tempfile
import logging
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from default.defaults import DEFAULT_CODE_COCCOON_TRANSFORMATIONS
from common.cli import run_cli_command
from common.logger import configure_logging
from common.fs import read_jsonl, write_jsonl

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
  --override: Whether to override existing transformation results if branches already exist (default: False).

Usage:
python transform.py -i path/to/input.jsonl -o path/to/output.jsonl -s transformation_strategy_name -c path/to/codecoccoon
"""

# Configure logging
configure_logging(log_filename="transform.log", level=logging.INFO)

logger = logging.getLogger(__name__)



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


def generate_codecocoon_config(
    project_root: str,
    files: List[str],
    transformations: List[Dict],
    output_path: str,
):
    """
    Generate a codecocoon.yml configuration file.

    Arguments:
        - project_root: The root directory of the project to be transformed (e.g., the cloned repository path).
        - files: A list of file paths (relative to project_root) that should be considered for transformations.
        - transformations: A list of transformation configurations to apply (each with an 'id' and 'config'; config should be transformation-specific).
        - output_path: The file path where the generated codecocoon.yml should be saved.
    """

    config = {
        'projectRoot': project_root,
        'files': files,
        'transformations': transformations
    }

    with open(output_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False)
        logger.info(f"Generated codecocoon config at {output_path} with content:\n```\n{yaml.dump(config)}\n```")



def execute_codecocoon(codecocoon_dir: str, config_path: str) -> Tuple[str, str, int]:
    """Execute CodeCocoon in headless mode."""
    logger.info(f"Executing CodeCocoon with config {config_path}")
    stdout, stderr, code = run_cli_command(
        './gradlew',
        ['headless', f'-Pcodecocoon.config={config_path}'],
        cwd=codecocoon_dir,
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


def branch_exists(repo_dir: str, branch_name: str) -> bool:
    """Check if a branch exists in the repository."""
    try:
        stdout, stderr, code = run_cli_command(
            'git', ['rev-parse', '--verify', branch_name], cwd=repo_dir,
        )
        exists = code == 0
        logger.debug(f"Branch '{branch_name}' exists: {exists}")
        return exists
    except Exception as e:
        logger.error(f"Failed to check branch existence: {e}")
        return False


def delete_branch(repo_dir: str, branch_name: str) -> bool:
    """Delete a branch from the repository."""
    try:
        # First checkout to a different branch (base SHA)
        stdout, stderr, code = run_cli_command('git', ['checkout', 'HEAD~0'], cwd=repo_dir)
        if code != 0:
            logger.error(f"Failed to detach HEAD: {stderr}")
            return False

        # Delete the branch
        stdout, stderr, code = run_cli_command('git', ['branch', '-D', branch_name], cwd=repo_dir)
        if code != 0:
            logger.error(f"Failed to delete branch '{branch_name}': {stderr}")
            return False

        logger.info(f"Successfully deleted branch '{branch_name}'")
        return True
    except Exception as e:
        logger.error(f"Branch deletion failed: {e}")
        return False


def checkout_branch(repo_dir: str, branch_name: str, create: bool = False, base_ref: str = None) -> bool:
    """Checkout a branch, optionally creating it from a base reference."""
    try:
        if create:
            if base_ref:
                # Checkout base reference first
                stdout, stderr, code = run_cli_command('git', ['checkout', base_ref], cwd=repo_dir)
                if code != 0:
                    logger.error(f"Failed to checkout base ref '{base_ref}': {stderr}")
                    return False

            # Create and checkout new branch
            stdout, stderr, code = run_cli_command('git', ['checkout', '-b', branch_name], cwd=repo_dir)
            if code != 0:
                logger.error(f"Failed to create branch '{branch_name}': {stderr}")
                return False
            logger.info(f"Created and checked out branch '{branch_name}'")
        else:
            # Just checkout existing branch
            stdout, stderr, code = run_cli_command('git', ['checkout', branch_name], cwd=repo_dir)
            if code != 0:
                logger.error(f"Failed to checkout branch '{branch_name}': {stderr}")
                return False
            logger.info(f"Checked out branch '{branch_name}'")

        return True
    except Exception as e:
        logger.error(f"Branch checkout failed: {e}")
        return False


def commit_all_changes(repo_dir: str, message: str) -> bool:
    """Stage and commit all changes in the repository."""
    try:
        # Add all changes
        stdout, stderr, code = run_cli_command('git', ['add', '-A'], cwd=repo_dir)
        if code != 0:
            logger.error(f"Failed to stage changes: {stderr}")
            return False

        # Check if there are changes to commit
        stdout, stderr, code = run_cli_command('git', ['diff', '--cached', '--exit-code'], cwd=repo_dir)
        if code == 0:
            logger.info("No changes to commit")
            return True

        # Commit changes
        stdout, stderr, code = run_cli_command('git', ['commit', '-m', message], cwd=repo_dir)
        if code != 0:
            logger.error(f"Failed to commit: {stderr}")
            return False

        logger.info(f"Successfully committed changes: {message}")
        return True
    except Exception as e:
        logger.error(f"Commit failed: {e}")
        return False


def check_and_handle_existing_branches(
    repo_dir: str,
    strategy: str,
    override: bool
) -> Tuple[bool, str, str]:
    """
    Check if strategy branches exist and handle according to override flag.
    Branches:
    - Base transformation branch: "{strategy}-base-transformation"
    - Fix transformation branch: "{strategy}-fix-transformation"

    Returns:
        Tuple[bool, str, str]: (should_continue, base_branch_name, fix_branch_name)
    """
    base_branch = f"{strategy}-base-transformation"
    fix_branch = f"{strategy}-fix-transformation"

    base_exists = branch_exists(repo_dir, base_branch)
    fix_exists = branch_exists(repo_dir, fix_branch)

    if base_exists or fix_exists:
        if not override:
            logger.info(
                f"Branches for strategy '{strategy}' already exist. "
                f"Skipping transformation (use --override to regenerate)."
            )
            return False, base_branch, fix_branch
        else:
            logger.info(f"IMPORTANT: Override enabled. Deleting existing branches for strategy '{strategy}'")
            if base_exists:
                if not delete_branch(repo_dir, base_branch):
                    logger.error(f"Failed to delete base branch '{base_branch}'")
                    return False, base_branch, fix_branch
            if fix_exists:
                if not delete_branch(repo_dir, fix_branch):
                    logger.error(f"Failed to delete fix branch '{fix_branch}'")
                    return False, base_branch, fix_branch

    return True, base_branch, fix_branch


def process_entry(
    entry: Dict,
    strategy: str,
    codecocoon_dir: str,
    transformations: List[Dict],
    repos_dir: str,
    transform_test_files: bool,
    override: bool,
) -> Dict:
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

        # Step 1.5: Check if branches exist and handle override
        should_continue, base_branch, fix_branch = check_and_handle_existing_branches(
            repo_dir, strategy, override
        )

        if not should_continue:
            logger.info(f"Skipping transformation for {instance_id} - branches already exist")
            return entry

        # Step 2: Extract changed files
        # NOTE: based on `transform_test_files` flag, apply transformations to files from either:
        #         1) fix patch only (default behavior)
        #         2) both fix and test patches
        fix_files = extract_changed_files(entry.get('fix_patch', ''))
        test_files = extract_changed_files(entry.get('test_patch', ''))

        if transform_test_files is True:
            # transform files from the test patch as well
            files_to_transform = list(set(fix_files + test_files))
            logger.info(f"Transforming files FROM BOTH FIX AND TEST PATCHES for {instance_id}")
        else:
            # transform only files modified by the fix patch (default behavior)
            files_to_transform = list(set(fix_files))
            logger.info(f"Transforming files modified ONLY BY FIX PATCH for {instance_id}")


        files_to_transform_joined = ''.join(list(map(lambda file: f"\n     - {file}", files_to_transform)))
        logger.info(f"Extracted {len(files_to_transform)} unique changed files for {instance_id}:{files_to_transform_joined}")

        if not files_to_transform:
            logger.warning(f"No files found in patches for {instance_id}")
            return entry

        # Step 3: Generate CodeCocoon config

        # config_path=repos_dir/instance_id/codecocoon.yml
        config_path = os.path.join(repos_dir, instance_id, "codecocoon.yml")
        generate_codecocoon_config(
            project_root=repo_dir,
            files=files_to_transform,
            transformations=transformations,
            output_path=config_path,
        )

        # ===== PART 1: BASE TRANSFORMATION =====
        logger.info(f"Starting base transformation for {instance_id}")

        # Create base transformation branch from base SHA
        if not checkout_branch(repo_dir, base_branch, create=True, base_ref=base_sha):
            logger.error(f"Failed to create base transformation branch for {instance_id}")
            return entry

        # Execute CodeCocoon on base commit
        logger.info(f"Executing CodeCocoon on base commit for {instance_id}")
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
            # Get the diff before committing
            base_diff = create_diff(repo_dir)
            if base_diff:
                metamorphic[strategy]['metamorphic_base_patch'] = base_diff
                logger.info(f"Base transformation diff captured for {instance_id}")
            else:
                logger.warning(f"Failed to create base diff for {instance_id}")

            # Commit the transformation changes
            if not commit_all_changes(repo_dir, f"(strategy={strategy}): Apply transformations to base commit"):
                logger.error(f"Failed to commit base transformations for {instance_id}")
                return entry

            logger.info(f"Base transformation successful and committed for {instance_id}")
        else:
            logger.error(f"CodeCocoon failed on base commit for {instance_id}: {stderr}")
            return entry

        # ===== PART 2: FIX TRANSFORMATION =====
        logger.info(f"Starting fix transformation for {instance_id}")

        # Create fix transformation branch from base SHA
        if not checkout_branch(repo_dir, fix_branch, create=True, base_ref=base_sha):
            logger.error(f"Failed to create fix transformation branch for {instance_id}")
            return entry

        # Apply fix and test patches
        if not apply_patch(repo_dir, entry.get('fix_patch', '')):
            logger.error(f"Failed to apply fix patch for {instance_id}")
            return entry

        if not apply_patch(repo_dir, entry.get('test_patch', '')):
            logger.error(f"Failed to apply test patch for {instance_id}")
            return entry

        # Commit fix and test patches
        if not commit_all_changes(repo_dir, "Apply fix and test patches"):
            logger.error(f"Failed to commit fix and test patches for {instance_id}")
            return entry

        # Execute CodeCocoon on fixed commit
        logger.info(f"Executing CodeCocoon on fix commit for {instance_id}")
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
            # Get the diff before committing
            fix_diff = create_diff(repo_dir)
            if fix_diff:
                metamorphic[strategy]['metamorphic_fix_patch'] = fix_diff
                logger.info(f"Fix transformation diff captured for {instance_id}")
            else:
                logger.warning(f"Failed to create fix diff for {instance_id}")

            # Commit the transformation changes
            if not commit_all_changes(repo_dir, f"(strategy={strategy}): Apply transformations to fixed commit"):
                logger.error(f"Failed to commit fix transformations for {instance_id}")
                return entry

            logger.info(f"Fix transformation successful and committed for {instance_id}")
        else:
            logger.error(f"CodeCocoon failed on fix commit for {instance_id}: {stderr}")
            return entry

        logger.info(f"Successfully completed all transformations for {instance_id}")
        logger.info(f"  Base branch: {base_branch}")
        logger.info(f"  Fix branch: {fix_branch}")

    except Exception as e:
        logger.error(f"Failed to process {instance_id}: {e}", exc_info=True)

    return entry

def load_codecoccoon_transformations(from_filepath: str | None) -> List[Dict] | None:
    def is_transformation_schema(transformation) -> bool:
        # NOTE: if transformation accepts zero config params, its config still needs to be defined
        #       as an empty dict (i.e., "config": {}) to be valid
        return isinstance(transformation, dict) and ('id' in transformation) and ('config' in transformation)

    if from_filepath is None:
        logger.info(
        f"No file with transformations provided, using default transformations:\n{json.dumps(DEFAULT_CODE_COCCOON_TRANSFORMATIONS, indent=3)}")
        return DEFAULT_CODE_COCCOON_TRANSFORMATIONS

    try:
        with open(from_filepath, 'r') as f:
            transformations = json.load(f)
        # validate that it is a list of dicts
        if not isinstance(transformations, list) or not all(is_transformation_schema(t) for t in transformations):
            raise ValueError(f"Transformations file must contain a JSON list of objects, got {transformations}")

        logger.info(f"Loaded transformations from file: {from_filepath}")
        return transformations
    except Exception as e:
        logger.error(f"Failed to load transformations file: {e}")
        return None


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
    parser.add_argument('-t', '--transformations', type=str, default=None, help="Filepath to a JSON file with transformations definitions. The file should contain a list of objects with `id` and `config` entries where the config is transformation-specific. Defaults to a config defined inn `default/defaults.py` when missing.")
    # bool arguments
    parser.add_argument('--transform_test_files', action='store_true', default=False,
                        help="Whether to also transform test files changed in the test patch (`test_patch` field in every benchmark) (default: False)")
    parser.add_argument('--override', action='store_true', default=False,
                        help="Override existing transformation results if branches already exist (default: False)")



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
      --transformations: {args.transformations}
      --repos: {args.repos}
      --transform_test_files: {args.transform_test_files}
      --override: {args.override}
    """)

    # CodeCocoon existence check (validate that the provided path is a directory and contains expected files)
    if not os.path.exists(args.codecoccoon):
        raise ValueError(f"CodeCocoon directory does not exist: {args.codecoccoon}. Directory path to the Code Codecoccoon Plugin repository expected (its headless mode will be executed) and should be provided via `--codecoccoon` argument.")
    if not os.path.isdir(args.codecoccoon):
        raise ValueError(f"Provided CodeCocoon path is not a directory: {args.codecoccoon}. Directory path to the Code Codecoccoon Plugin repository expected (its headless mode will be executed) and should be provided via `--codecoccoon` argument.")

    if args.strategy is None or len(args.strategy) <= 0:
        raise ValueError(f"Received malformed transformation strategy: '{args.strategy}'. Transformation strategy name must be provided via `--strategy` argument and should be a non-empty string (e.g., 'default')")


    transformations = load_codecoccoon_transformations(from_filepath=args.transformations)
    if transformations is None:
        logger.error("Failed to load transformations, terminating execution.")
        return

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

        processed_entry = process_entry(
            entry=entry,
            strategy=args.strategy,
            codecocoon_dir=args.codecoccoon,
            transformations=transformations,
            repos_dir=args.repos,
            transform_test_files=args.transform_test_files,
            override=args.override,
        )
        processed_entries.append(processed_entry)

        logger.info(f"====== ✅ Completed entry '{instance_id}' ({i}/{len(entries)}) ======")
        logger.info("==========================================================================")

    # Write output
    write_jsonl(args.output, processed_entries)
    logger.info("Processing complete!")


if __name__ == "__main__":
    main()
