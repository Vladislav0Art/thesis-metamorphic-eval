import argparse
import json
import os
import re
import yaml
import tempfile
import logging
from pathlib import Path
from dataclasses import dataclass
from typing import Dict, List, Tuple, Optional
from dotenv import dotenv_values
from default.defaults import DEFAULT_CODE_COCCOON_TRANSFORMATIONS
from common.cli import run_cli_command
from common.logger import configure_logging
from common.fs import read_jsonl, write_jsonl


description="""
This script accepts jsonl file with benchmarks and applies transformations via CodeCocoon-Plugin.
The result patches after transformation are added into the entries of the given jsonl file and
save into the output file.

Arguments:
  -i, --input: Path to the input JSONL file containing benchmarks.
  -o, --output: Path to the output jsonl file where transformed benchmarks will be saved.
  -s, --strategy: The transformation strategy name
                  (the resulting transformations will be saved as entry['strategy']['metamorphic_base_patch'] and
                   entry['strategy']['metamorphic_fix_patch']).
  -c, --codecoccoon: Filepath to the Code Codecoccoon repository (its headless mode will be executed).
  -e, --env_filepath: Filepath to a file with key-value pairs defining environment variables to be set when executing CodeCocoon (e.g., to provide credentials for private repositories) (default: None).
  -r, --repos: Filepath which the repositories from the input should be cloned into.
  --transform_test_files: Whether to also transform test files changed in the test patch (`test_patch` field in every benchmark) (default: False).
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
        # flushing so that the process where we run CodeCocoon sees this file
        f.flush()
        os.fsync(f.fileno())
        logger.info(f"Generated codecocoon config at {output_path} with content:\n```\n{yaml.dump(config)}\n```")





@dataclass
class Patch:
    """
    Represents a patch to be applied to the repository.
        - name: str (used for logging purposes to identify the patch)
        - content: str (the actual patch content in git diff format)
    """
    name: str
    content: str

@dataclass
class CodeCocoonResult:
    stdout: str
    stderr: str
    return_code: int

@dataclass
class MorphResult:
    succeeded: bool
    last_commit_sha: Optional[str] = None
    metamorphic_patch: Optional[str] = None
    codecocoon_result: Optional[CodeCocoonResult] = None




def execute_codecocoon(
    codecocoon_dir: str,
    config_path: str,
    env_vars: Dict[str, str | None],
) -> CodeCocoonResult:
    """Execute CodeCocoon in headless mode."""
    logger.info(f"Executing CodeCocoon with config {config_path}")
    stdout, stderr, code = run_cli_command(
        './gradlew',
        ['headless', f'-Pcodecocoon.config={config_path}'],
        cwd=codecocoon_dir,
        # merge current environment with additional env vars
        env={**os.environ, **env_vars},
    )
    return CodeCocoonResult(
        stdout=stdout,
        stderr=stderr,
        return_code=code,
    )


def insert_metamorphic_log(
    strategy_entry: Dict,
    label: str,
    applied_to: str,
    result: CodeCocoonResult | None,
):
    """
    Inserts a log entry for a metamorphic transformation result into the strategy entry dict.

    The insertion will have the following structure (appended into the "logs" array):
    ```
    strategy_entry["logs"] = [
        {
            "applied_to": applied_to,  # e.g., 'base' or 'test'
            "label": label,
            "result": {
                "stdout": result['stdout'],
                "stderr": result['stderr'],
                "return_code": result['return_code']
            }
        }
    ]
    ```
    If the "logs" array does not exist in strategy_entry, it will be created.

    Arguments:
      - strategy_entry: The strategy dict to append the log into (one element of `entry['metamorphic']`).
      - label: any string literal meaningful for the log.
      - applied_to: A string indicating whether this log is for the 'base' (i.e., on the base commit)
                    or 'test' (i.e., after applying the test patch) transformation.
      - result: A `CodeCocoonResult` containing the result of the transformation execution, with keys:
                - "stdout": The standard output from executing CodeCocoon.
                - "stderr": The standard error from executing CodeCocoon.
                - "return_code": The return code from executing CodeCocoon.
    """
    if "logs" not in strategy_entry:
        strategy_entry["logs"] = []

    log_entry = {
        "applied_to": applied_to,
        "label": label,
        "result": result.__dict__ if result is not None else None,
    }
    strategy_entry["logs"].append(log_entry)
    logger.info("Successfully inserted metamorphic log entry applied to '%s'", applied_to)


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

        logger.info(f"Successfully committed changes: `{message}`")
        return True
    except Exception as e:
        logger.error(f"Commit failed: {e}")
        return False


def diff_between_commits(repo_dir: str, base: str, another: str) -> Optional[str]:
    """
    Generate a git diff between two commits.

    Args:
        repo_dir: Path to the git repository
        base: Base commit SHA or reference
        another: Another commit SHA or reference to compare against base

    Returns:
        The diff as a string, or None if the operation fails
    """
    try:
        logger.debug(f"Creating diff between '{base}' and '{another}'")
        stdout, stderr, code = run_cli_command('git', ['diff', base, another], cwd=repo_dir)
        if code != 0:
            logger.error(f"Failed to create diff between commits: {stderr}")
            return None
        logger.info(f"Successfully created diff between '{base}' and '{another}'")
        return stdout
    except Exception as e:
        logger.error(f"Diff creation failed: {e}")
        return None



def morph(
    repo_dir: str,
    patches: List[Patch], # List of `(patch_name (used for logging only), patch_content)` tuples
    env_vars: Dict[str, str | None],
    branch: str,
    metamorphic_commit_msg: str,
    codecocoon_dir: str,
    config_path: str,
) -> MorphResult:
    """
    Apply patches, run CodeCocoon transformations, and commit the results.

    This function performs the following steps:
    1. Checkout the specified branch (create if doesn't exist)
    2. Apply patches in order (no-op if empty list)
    3. Commit applied patches separately (if any)
    4. Run CodeCocoon transformations
    5. Collect metamorphic changes as a diff patch
    6. Commit the metamorphic changes
    7. Return the final commit SHA and metamorphic patch

    The key insight is that patches are committed separately before running CodeCocoon, so they don't pollute the metamorphic diff.

    Args:
        repo_dir: Path to the git repository
        patches: List of patches (as strings in git diff format) to apply before transformation
        env_vars: Environment variables for CodeCocoon execution
        branch: Branch name to work on
        metamorphic_commit_msg: Commit message for the metamorphic changes
        codecocoon_dir: Path to CodeCocoon repository
        config_path: Path to codecocoon.yml config file

    Returns:
        `MorphResult` with all values set on success, otherwise `MorphResult(succeeded=False)` with error details in logs.
    """
    try:
        # Step 1: Checkout branch (create if doesn't exist)
        logger.info(f"Checking out branch '{branch}'")
        branch_existed = branch_exists(repo_dir, branch)

        if not branch_existed:
            # Create new branch from current HEAD
            if not checkout_branch(repo_dir, branch, create=True):
                logger.error(f"Failed to create and checkout branch '{branch}'")
                return MorphResult(succeeded=False)
        else:
            # Just checkout existing branch
            if not checkout_branch(repo_dir, branch, create=False):
                logger.error(f"Failed to checkout existing branch '{branch}'")
                return MorphResult(succeeded=False)

        # Step 2 & 3: Apply patches and commit them (if any)
        if len(patches) > 0:
            logger.info(f"Applying {len(patches)} patch(es) to branch '{branch}'")
            for i, patch in enumerate(patches, 1):
                if not apply_patch(repo_dir, patch.content):
                    logger.error(f"Failed to apply patch `{patch.name}` ({i}/{len(patches)})")
                    return MorphResult(succeeded=False)

            # Commit the applied patches
            applied_patches_str = ', '.join([p.name for p in patches])
            patches_commit_msg = f"[transform.py] Applied patches: {applied_patches_str}"
            if not commit_all_changes(repo_dir, patches_commit_msg):
                logger.error("Failed to commit applied patches")
                return MorphResult(succeeded=False)
            logger.info(f"Successfully applied and committed {len(patches)} patch(es)")
        else:
            logger.info("No patches to apply, proceeding to transformations")

        # Step 4: Run CodeCocoon
        logger.info(f"Executing CodeCocoon transformations on branch '{branch}'")
        codecocoon_result: CodeCocoonResult = execute_codecocoon(codecocoon_dir, config_path, env_vars)

        if codecocoon_result.return_code != 0:
            logger.error(f"CodeCocoon execution failed: {stderr}")
            return MorphResult(succeeded=False, codecocoon_result=codecocoon_result)

        logger.info(f"CodeCocoon execution successful")

        # Step 5: Collect metamorphic diff
        metamorphic_patch = create_diff(repo_dir)
        if not metamorphic_patch:
            logger.warning("No metamorphic changes detected: The metamorphic patch is empty")
            metamorphic_patch = ""

        # Step 6: Commit metamorphic changes
        if not commit_all_changes(repo_dir, metamorphic_commit_msg):
            logger.error("Failed to commit metamorphic changes")
            return MorphResult(succeeded=False, codecocoon_result=codecocoon_result)

        # Step 7: Get the last commit SHA
        stdout, stderr, code = run_cli_command('git', ['rev-parse', 'HEAD'], cwd=repo_dir)
        if code != 0:
            logger.error(f"Failed to get commit SHA: {stderr}")
            return MorphResult(succeeded=False, codecocoon_result=codecocoon_result)

        last_commit_sha = stdout.strip()
        logger.info(f"Metamorphic transformation complete. Last commit: {last_commit_sha}")

        return MorphResult(
            succeeded=True,
            last_commit_sha=last_commit_sha,
            metamorphic_patch=metamorphic_patch,
            codecocoon_result=codecocoon_result,
        )
    except Exception as e:
        logger.error(f"Morph operation failed: {e}", exc_info=True)
        return MorphResult(succeeded=False)


def process_entry(
    entry: Dict,
    strategy: str,
    codecocoon_dir: str,
    transformations: List[Dict],
    repos_dir: str,
    env_vars: Dict[str, str | None],
    transform_test_files: bool,
    override: bool,
) -> Dict:
    """Process a single entry through the transformation pipeline."""
    instance_id = entry['instance_id']
    logger.info(f"Processing entry: {instance_id}")

    # Initialize metamorphic array if not present
    if "metamorphic" not in entry:
        entry["metamorphic"] = []

    # Strategy entry dict — built up locally and appended to entry["metamorphic"] once
    # we know base morphing succeeded (to avoid partial empty entries on early failures).
    strategy_entry = {"strategy": strategy}

    try:
        # Step 1: Clone repository
        repo_url = build_github_url(entry['org'], entry['repo'])

        # repo_dir=repos_dir/strategy/instance_id/repo
        repo_dir = os.path.join(repos_dir, strategy, instance_id, "repo")
        base_sha = entry['base']['sha']

        if not clone_repository(repo_url, repo_dir, base_sha):
            logger.error(f"Failed to clone repository for {instance_id}")
            return entry

        # Step 1.5: Check if branches exist and handle override
        base_branch = f"{strategy}-base-transformation"
        test_branch = f"{strategy}-test-transformation"
        fix_branch  = f"{strategy}-fix-transformation"

        base_exists = branch_exists(repo_dir, base_branch)
        test_exists = branch_exists(repo_dir, test_branch)
        fix_exists = branch_exists(repo_dir, fix_branch)

        if (base_exists or test_exists or fix_exists) and not override:
            logger.info(
                f"Branches for strategy '{strategy}' already exist. "
                f"Skipping transformation (use --override to regenerate)."
            )
            return entry

        if override and (base_exists or test_exists or fix_exists):
            logger.info(f"Override enabled: Deleting existing branches for strategy '{strategy}'")
            if base_exists and not delete_branch(repo_dir, base_branch):
                logger.error(f"Failed to delete base branch '{base_branch}'")
                return entry
            if test_exists and not delete_branch(repo_dir, test_branch):
                logger.error(f"Failed to delete test branch '{test_branch}'")
                return entry
            if fix_exists and not delete_branch(repo_dir, fix_branch):
                logger.error(f"Failed to delete test branch '{fix_branch}'")
                return entry

        # Step 2: Extract changed files
        # NOTE: based on `transform_test_files` flag, apply transformations to files from either:
        #         1) fix patch only (default behavior)
        #         2) both fix and test patches (if `transform_test_files` is True)
        fix_files = extract_changed_files(entry.get('fix_patch', ''))
        test_files = extract_changed_files(entry.get('test_patch', ''))

        if transform_test_files:
            # transform files from the test patch as well
            files_to_transform = list(set(fix_files + test_files))
            logger.info(f"Transforming files FROM BOTH FIX AND TEST PATCHES for {instance_id}")
        else:
            # transform only files modified by the fix patch (default behavior)
            files_to_transform = list(set(fix_files))
            logger.info(f"Transforming files modified ONLY BY FIX PATCH for {instance_id}")

        if not files_to_transform:
            logger.warning(f"No files found in patches for {instance_id}")
            return entry

        files_to_transform_joined = ''.join([f"\n     - {file}" for file in files_to_transform])
        logger.info(f"Extracted {len(files_to_transform)} unique changed files:{files_to_transform_joined}")

        # Step 3: Generate CodeCocoon config
        # config_path=repos_dir/strategy/instance_id/codecocoon.yml
        config_path = os.path.join(repos_dir, strategy, instance_id, "codecocoon.yml")
        os.makedirs(os.path.dirname(config_path), exist_ok=True)
        generate_codecocoon_config(
            project_root=repo_dir,
            files=files_to_transform,
            transformations=transformations,
            output_path=config_path,
        )

        # Step 4: Apply metamorphic modifications to base commit
        logger.info(f"\n===== STEP 1: Applying metamorphic modifications to base commit =====")

        # Ensure we're on base commit before starting
        if not checkout_branch(repo_dir, base_sha, create=False):
            logger.error(f"Failed to checkout base SHA {base_sha}")
            return entry

        base_morph_result: MorphResult = morph(
            repo_dir=repo_dir,
            patches=[],
            env_vars=env_vars,
            branch=base_branch,
            metamorphic_commit_msg="Apply metamorphic modifications on: base commit",
            codecocoon_dir=codecocoon_dir,
            config_path=config_path,
        )

        if base_morph_result.succeeded is False:
            logger.error("Failed to apply base metamorphic transformations")
            return entry

        # assing variables
        metamorphic_base_commit: str = base_morph_result.last_commit_sha
        metamorphic_base_patch: str = base_morph_result.metamorphic_patch

        # Base morph succeeded — commit strategy_entry to the metamorphic array.
        # From this point on any early return still preserves partially-stored fields.
        entry["metamorphic"].append(strategy_entry)

        # Store repo reference (path + branch names) for external tooling / debugging
        strategy_entry["repo"] = {
            "instance_id": instance_id,
            "path": repo_dir,
            "branches": {
                "base": base_branch,
                "test": test_branch,
                "fix": fix_branch,
            },
        }

        # Store base transformation results
        strategy_entry['metamorphic_base_patch'] = metamorphic_base_patch
        strategy_entry['metamorphic_base_commit'] = metamorphic_base_commit
        # saving CodeCocoon logs for base transformation
        insert_metamorphic_log(
            strategy_entry=strategy_entry,
            label="base_metamorphic_transformation_log",
            applied_to="base",
            result=base_morph_result.codecocoon_result,
        )

        logger.info(f"Base metamorphic transformation complete. Commit: {metamorphic_base_commit}")

        # Step 5: Apply test_patch and then metamorphic modifications
        logger.info(f"\n===== STEP 2: Applying test_patch + metamorphic modifications =====")

        # Checkout base commit again before applying test patch
        if not checkout_branch(repo_dir, base_sha, create=False):
            logger.error(f"Failed to checkout base SHA {base_sha}")
            return entry

        test_patch = entry.get('test_patch', '')

        test_morph_result: MorphResult = morph(
            repo_dir=repo_dir,
            patches=[Patch(name="test_patch", content=test_patch)] if test_patch else [],
            env_vars=env_vars,
            branch=test_branch,
            metamorphic_commit_msg="Apply metamorphic modifications on: base commit + test_patch (pre-committed)",
            codecocoon_dir=codecocoon_dir,
            config_path=config_path,
        )

        if test_morph_result.succeeded is False:
            logger.error("Failed to apply test metamorphic transformations")
            return entry

        metamorphic_test_commit = test_morph_result.last_commit_sha
        _metamorphic_test_patch = test_morph_result.metamorphic_patch

        logger.info(f"Test metamorphic transformation complete. Commit: {metamorphic_test_commit}")

        # Store metadata in strategy entry for reference
        strategy_entry['_metamorphic_test_patch'] = _metamorphic_test_patch
        strategy_entry['metamorphic_test_commit'] = metamorphic_test_commit
        # save CodeCocoon logs for test transformation
        insert_metamorphic_log(
            strategy_entry=strategy_entry,
            label="test_metamorphic_transformation_log",
            applied_to="test",
            result=test_morph_result.codecocoon_result,
        )

        # Step 6: Generate new_morphed_test_patch as diff between two metamorphic commits
        logger.info(f"\n===== STEP 3: Generating new_morphed_test_patch =====")

        # NOTE: this patch should be applied instead of test_patch when evaluating
        #       on the metamorphed version of the benchmark.
        # This final `new_morphed_test_patch` represents the difference between
        # the base metamorphic state and the test + metamorphic state.
        new_morphed_test_patch = diff_between_commits(
            repo_dir=repo_dir,
            base=metamorphic_base_commit,
            another=metamorphic_test_commit,
        )

        if not new_morphed_test_patch:
            logger.error("Failed to generate new_morphed_test_patch")
            return entry

        # save the original test patch as well for reference
        strategy_entry['original_test_patch'] = test_patch
        # store the generated new_morphed_test_patch (replaces test_patch)
        strategy_entry['new_morphed_test_patch'] = new_morphed_test_patch

        # Step 4: Apply fix_patch and then metamorphic modifications
        logger.info(f"\n===== STEP 4: Applying fix_patch + metamorphic modifications =====")

        # Checkout base commit again before applying fix patch
        if not checkout_branch(repo_dir, base_sha, create=False):
            logger.error(f"Failed to checkout base SHA {base_sha}")
            return entry

        fix_patch = entry.get('fix_patch', '')

        fix_morph_result: MorphResult = morph(
            repo_dir=repo_dir,
            patches=[Patch(name="fix_patch", content=fix_patch)] if fix_patch else [],
            env_vars=env_vars,
            branch=fix_branch,
            metamorphic_commit_msg="Apply metamorphic modifications on: base commit + fix_patch (pre-committed)",
            codecocoon_dir=codecocoon_dir,
            config_path=config_path,
        )

        if fix_morph_result.succeeded is False:
            logger.error("Failed to apply fix metamorphic transformations")
            return entry

        metamorphic_fix_commit = fix_morph_result.last_commit_sha
        _metamorphic_fix_patch = fix_morph_result.metamorphic_patch

        logger.info(f"Fix metamorphic transformation complete. Commit: {metamorphic_fix_commit}")

        # Store metadata in strategy entry for reference
        strategy_entry['_metamorphic_fix_patch'] = _metamorphic_fix_patch
        strategy_entry['metamorphic_fix_commit'] = metamorphic_fix_commit
        # save CodeCocoon logs for fix transformation
        insert_metamorphic_log(
            strategy_entry=strategy_entry,
            label="fix_metamorphic_transformation_log",
            applied_to="fix",
            result=fix_morph_result.codecocoon_result,
        )

        # Step 5: Generate new_morphed_fix_patch as diff between two metamorphic commits
        logger.info(f"\n===== STEP 5: Generating new_morphed_fix_patch =====")

        # This final `new_morphed_fix_patch` represents the difference between
        # the base metamorphic state and the fix + metamorphic state.
        new_morphed_fix_patch = diff_between_commits(
            repo_dir=repo_dir,
            base=metamorphic_base_commit,
            another=metamorphic_fix_commit,
        )

        if not new_morphed_fix_patch:
            logger.error("Failed to generate new_morphed_fix_patch")
            return entry

        # save the original fix patch as well for reference
        strategy_entry['original_fix_patch'] = fix_patch
        # store the generated new_morphed_fix_patch (replaces fix_patch)
        strategy_entry['new_morphed_fix_patch'] = new_morphed_fix_patch

        logger.info(f"\n===== STEP 6: Replacing test_patch/fix_patch with morphed versions and save metamorphic_base_patch into 'base' =====")

        # base: sha -> sha + metamorphic_base_patch (MSWE-agent and multi_swe_bench should apply the patch manually)
        # test: test_patch -> new_morphed_test_patch
        # fix:  fix_patch  -> new_morphed_fix_patch
        entry['base']['metamorphic_base_patch'] = metamorphic_base_patch
        entry['test_patch'] = new_morphed_test_patch
        entry['fix_patch'] = new_morphed_fix_patch

        logger.info(f"Successfully completed all transformations for {instance_id}")
        logger.info(f"  Base branch: {base_branch}")
        logger.info(f"  Test branch: {test_branch}")
        logger.info(f"  Fix branch:  {fix_branch}")
        logger.info(f"  Generated new_morphed_test_patch (replaces test_patch)")
        logger.info(f"  Generated new_morphed_fix_patch  (replaces fix_patch)")

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


def make_absolute_path(path: str) -> str:
    """Convert a relative path to an absolute path."""
    return os.path.abspath(path)


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

    parser.add_argument('-e', "--env_filepath", type=str, default=None,
                        help="Filepath to a file with key-value pairs defining environment variables to be set when executing CodeCocoon (e.g., to provide credentials for private repositories) (default: None)")

    parser.add_argument('-r', '--repos', type=str, help="Filepath which the repositories from the input should be cloned into")
    parser.add_argument('-t', '--transformations', type=str, default=None, help="Filepath to a JSON file with transformations definitions. The file should contain a list of objects with `id` and `config` entries where the config is transformation-specific. Defaults to a config defined inn `default/defaults.py` when missing.")
    # bool arguments
    parser.add_argument('--transform_test_files', action='store_true', default=False,
                        help="Whether to also transform test files changed in the test patch (`test_patch` field in every benchmark) (default: False)")
    parser.add_argument('--override', action='store_true', default=False,
                        help="Override existing transformation results if branches already exist (default: False)")


    args = parser.parse_args()


    # Convert paths to absolute if they are relative
    args.repos = make_absolute_path(args.repos)
    args.input = make_absolute_path(args.input)
    args.output = make_absolute_path(args.output)
    args.codecoccoon = make_absolute_path(args.codecoccoon)
    if args.env_filepath:
        args.env_filepath = make_absolute_path(args.env_filepath)
    if args.transformations:
        args.transformations = make_absolute_path(args.transformations)


    # Validate arguments
    if not os.path.exists(args.input):
        logger.error(f"Input file does not exist: {args.input}")
        return

    if not os.path.exists(args.codecoccoon):
        logger.error(f"CodeCocoon directory does not exist: {args.codecoccoon}")
        return

    # Create repos directory if it doesn't exist
    os.makedirs(args.repos, exist_ok=True)

    logger.info(f"""Given arguments (converted to absolute paths if needed):
      --input: {args.input}
      --output: {args.output}
      --strategy: {args.strategy}
      --codecoccoon: {args.codecoccoon}
      --transformations: {args.transformations}
      --repos: {args.repos}
      --env_filepath: {args.env_filepath}
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

    # loading additional environment variables from the provided file (if any)
    # and setting them in the environment for when we execute CodeCocoon later
    if args.env_filepath is not None:
        if not os.path.exists(args.env_filepath):
            logger.error(f"Provided `env_filepath` does not exist: {args.env_filepath}")
            return
        if not os.path.isfile(args.env_filepath):
            logger.error(f"Provided `env_filepath` is not a file: {args.env_filepath}")
            return
        env_vars = dotenv_values(args.env_filepath)

        env_keys_str = ', '.join(list(env_vars.keys()))
        logger.info(f"Successfully loaded {len(env_vars)} environment variables from {args.env_filepath}: {env_keys_str}")
    else:
        logger.info("`env_filepath` not provided: No additional ENV variables loaded")
        env_vars = {}

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
            env_vars=env_vars,
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
