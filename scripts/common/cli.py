import subprocess
import threading
import logging

logger = logging.getLogger(__name__)


def run_cli_command(command, args, cwd=None, env=None):
    """
    Runs a CLI command and returns (stdout, stderr, returncode) after it exits.

    Output is buffered and returned; not streamed.  Use ``run_cli_command_streaming``
    for long-running processes where you want live log output.
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
            cwd=cwd,
            env=env,
        )

        return result.stdout, result.stderr, result.returncode
    except Exception as e:
        logger.error(f"Command execution failed: {e}")
        return "", str(e), -1


def run_cli_command_streaming(command, args, cwd=None, env=None, log_level=logging.INFO):
    """
    Runs a CLI command and streams stdout/stderr to the logger line-by-line
    as the process runs, rather than waiting for it to finish.

    Both streams are forwarded at ``log_level`` (default INFO) so they appear
    in evaluate.log and the console in real time.

    Args:
        command:   Executable path or name.
        args:      List of arguments.
        cwd:       Working directory for the subprocess.
        env:       Environment dict for the subprocess.
        log_level: Logger level for streamed lines (default logging.INFO).

    Returns:
        tuple: (stdout_text, stderr_text, returncode)
               Full captured text is also returned for error-message use,
               even though each line was already logged live.
    """
    full_command = [command] + args
    logger.debug(f"Executing (streaming): {' '.join(full_command)}")

    stdout_lines: list[str] = []
    stderr_lines: list[str] = []

    try:
        proc = subprocess.Popen(
            full_command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,          # line-buffered
            cwd=cwd,
            env=env,
        )
    except Exception as e:
        logger.error(f"Command execution failed: {e}")
        return "", str(e), -1

    def _stream(pipe, lines: list[str], prefix: str):
        for line in pipe:
            stripped = line.rstrip("\n")
            lines.append(stripped)
            logger.log(log_level, "%s%s", prefix, stripped)

    t_out = threading.Thread(target=_stream, args=(proc.stdout, stdout_lines, ""))
    t_err = threading.Thread(target=_stream, args=(proc.stderr, stderr_lines, "[stderr] "))
    t_out.start()
    t_err.start()
    t_out.join()
    t_err.join()

    proc.wait()

    return "\n".join(stdout_lines), "\n".join(stderr_lines), proc.returncode
