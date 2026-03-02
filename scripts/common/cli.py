import subprocess
import logging

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
