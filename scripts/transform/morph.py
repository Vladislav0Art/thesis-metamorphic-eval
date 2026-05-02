import re
from dataclasses import dataclass, field
from typing import List, Dict
from common.cli import run_cli_command
from common.git import (
    apply_patch,
    create_diff,
    commit_all_changes,
    branch_exists,
    checkout_branch,
)
from common.codecocoon import CodeCocoonResult, execute_codecocoon
from transform.models import Patch, MorphResult


@dataclass
class TransformationSummary:
    succeeded:     int
    failed:        int
    skipped:       int
    succeeded_ids: List[str] = field(default_factory=list)
    failed_ids:    List[str] = field(default_factory=list)
    skipped_ids:   List[str] = field(default_factory=list)


def parse_transformation_summary(stdout: str) -> TransformationSummary | None:
    """Parse CodeCocoon's 'Transformation summary' block from stdout.

    Handles both the count line and the optional per-transformation ID lines:

        [TransformationService] Transformation summary: 1 succeeded, 0 failed, 1 skipped:
        [TransformationService]      - succeeded: move-file-into-suggested-directory-transformation/ai
        [TransformationService]      - failed:
        [TransformationService]      - skipped:   reorder-class-methods-transformation
    """
    count_match = re.search(
        r'Transformation summary:\s*(\d+)\s+succeeded,\s*(\d+)\s+failed,\s*(\d+)\s+skipped',
        stdout,
    )
    if not count_match:
        return None

    def _parse_ids(pattern: str) -> List[str]:
        m = re.search(pattern, stdout)
        if not m:
            return []
        return [s.strip() for s in m.group(1).split(',') if s.strip()]

    return TransformationSummary(
        succeeded=int(count_match.group(1)),
        failed=int(count_match.group(2)),
        skipped=int(count_match.group(3)),
        # Use [ \t]* (not \s*) so we never consume the newline on empty lines.
        succeeded_ids=_parse_ids(r'-\s+succeeded:[ \t]*([^\n]*)'),
        failed_ids=_parse_ids(r'-\s+failed:[ \t]*([^\n]*)'),
        skipped_ids=_parse_ids(r'-\s+skipped:[ \t]*([^\n]*)'),
    )


def morph(
    repo_dir: str,
    patches: List[Patch], # List of `(patch_name (used for logging only), patch_content)` tuples
    env_vars: Dict[str, str | None],
    branch: str,
    metamorphic_commit_msg: str,
    codecocoon_dir: str,
    config_path: str,
    logger,
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
        branch_existed = branch_exists(repo_dir, branch, logger)

        if not branch_existed:
            # Create new branch from current HEAD
            if not checkout_branch(repo_dir, branch, logger, create=True):
                logger.error(f"Failed to create and checkout branch '{branch}'")
                return MorphResult(succeeded=False)
        else:
            # Just checkout existing branch
            if not checkout_branch(repo_dir, branch, logger, create=False):
                logger.error(f"Failed to checkout existing branch '{branch}'")
                return MorphResult(succeeded=False)

        # Step 2 & 3: Apply patches and commit them (if any)
        if len(patches) > 0:
            logger.info(f"Applying {len(patches)} patch(es) to branch '{branch}'")
            for i, patch in enumerate(patches, 1):
                if not apply_patch(repo_dir, patch.content, logger):
                    logger.error(f"Failed to apply patch `{patch.name}` ({i}/{len(patches)})")
                    return MorphResult(succeeded=False)

            # Commit the applied patches
            applied_patches_str = ', '.join([p.name for p in patches])
            patches_commit_msg = f"[transform.py] Applied patches: {applied_patches_str}"
            if not commit_all_changes(repo_dir, patches_commit_msg, logger):
                logger.error("Failed to commit applied patches")
                return MorphResult(succeeded=False)
            logger.info(f"Successfully applied and committed {len(patches)} patch(es)")
        else:
            logger.info("No patches to apply, proceeding to transformations")

        # Step 4: Run CodeCocoon
        logger.info(f"Executing CodeCocoon transformations on branch '{branch}'")
        codecocoon_result: CodeCocoonResult = execute_codecocoon(
            codecocoon_dir,
            config_path,
            env_vars,
            logger,
        )

        if codecocoon_result.return_code != 0:
            logger.error(f"CodeCocoon execution failed: {codecocoon_result.stderr}")
            return MorphResult(succeeded=False, codecocoon_result=codecocoon_result)

        logger.info(f"CodeCocoon execution successful")

        # Step 5: Collect metamorphic diff
        metamorphic_patch = create_diff(repo_dir, logger)
        if not metamorphic_patch:
            logger.warning("No metamorphic changes detected: The metamorphic patch is empty")
            metamorphic_patch = ""

        # Step 6: Commit metamorphic changes
        if not commit_all_changes(repo_dir, metamorphic_commit_msg, logger):
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



def insert_metamorphic_log(
    strategy_entry: Dict,
    label: str,
    applied_to: str,
    result: CodeCocoonResult | None,
    logger,
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
