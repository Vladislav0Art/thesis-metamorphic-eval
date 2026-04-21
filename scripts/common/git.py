import os
import re
import tempfile
from typing import List, Optional
from common.cli import run_cli_command
from common.fs import read_jsonl, write_jsonl



def clone_repository(
    repo_url: str,
    target_dir: str,
    sha: str,
    logger,
) -> bool:
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


def apply_patch(repo_dir: str, patch: str, logger) -> bool:
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

def create_diff(repo_dir: str, logger) -> Optional[str]:
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



def commit_all_changes(repo_dir: str, message: str, logger) -> bool:
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


def diff_between_commits(
    repo_dir: str,
    base: str,
    another: str,
    logger,
) -> Optional[str]:
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


def branch_exists(repo_dir: str, branch_name: str, logger) -> bool:
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


def delete_branch(repo_dir: str, branch_name: str, logger) -> bool:
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




def checkout_branch(
        repo_dir: str,
        branch_name: str,
        logger,
        create: bool = False,
        base_ref: str = None,
    ) -> bool:
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


def commit_changes(
    repo_dir: str,
    branch_name: str,
    message: str,
    logger,
) -> bool:
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


def extract_changed_files(patch: str, logger) -> List[str]:
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
