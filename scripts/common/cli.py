import subprocess
import threading
import logging
from pathlib import Path
from typing import Optional

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


def run_cli_command_streaming(
    command,
    args,
    cwd=None,
    env=None,
    log_file: Optional[Path] = None,
    stream_stderr: bool = False,
):
    """
    Run a CLI command and handle its output streams as it runs.

    Output routing
    --------------
    stdout  → ``log_file`` only (never forwarded to the evaluate.py logger).
    stderr  → ``log_file`` always; also forwarded to the evaluate.py logger
              at WARNING level when ``stream_stderr=True``.

    This keeps the main evaluate.log free of the agent's/harness's verbose
    stdout while still making stderr visible there when desired.

    Args:
        command:       Executable path or name.
        args:          List of arguments.
        cwd:           Working directory for the subprocess.
        env:           Environment dict for the subprocess.
        log_file:      Path to a file where stdout and stderr are written.
                       The file is created (or appended to) automatically.
                       Pass ``None`` to discard stdout entirely.
        stream_stderr: If ``True``, each stderr line is also emitted via
                       ``logger.warning()`` so it appears in evaluate.log.
                       Default ``False`` (silence: stderr only in log_file).

    Returns:
        tuple: (stdout_text, stderr_text, returncode)
               Full captured text is returned for error-message use even
               though lines were already written to log_file.
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

    def _drain(pipe, lines: list[str], prefix: str, to_logger: bool, fh):
        """Read *pipe* line-by-line; write each line to fh and optionally to logger."""
        for line in pipe:
            stripped = line.rstrip("\n")
            lines.append(stripped)
            if fh is not None:
                fh.write(line if line.endswith("\n") else line + "\n")
                fh.flush()
            if to_logger:
                logger.warning("%s%s", prefix, stripped)

    if log_file is not None:
        log_file = Path(log_file)
        log_file.parent.mkdir(parents=True, exist_ok=True)
        fh = open(log_file, "a", encoding="utf-8")
    else:
        fh = None

    try:
        t_out = threading.Thread(
            target=_drain,
            args=(proc.stdout, stdout_lines, "", False, fh),
        )
        t_err = threading.Thread(
            target=_drain,
            args=(proc.stderr, stderr_lines, "[stderr] ", stream_stderr, fh),
        )
        t_out.start()
        t_err.start()
        t_out.join()
        t_err.join()
        proc.wait()
    finally:
        if fh is not None:
            fh.close()

    return "\n".join(stdout_lines), "\n".join(stderr_lines), proc.returncode
