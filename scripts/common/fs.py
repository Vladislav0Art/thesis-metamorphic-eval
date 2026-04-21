import json
import logging
import os
from typing import List, Dict


logger = logging.getLogger(__name__)

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


def append_jsonl(filepath: str, entry: Dict):
    """Append a single entry to a JSONL file (creates the file if it doesn't exist)."""
    try:
        with open(filepath, 'a') as f:
            f.write(json.dumps(entry) + '\n')
    except Exception as e:
        logger.error(f"Failed to append entry to {filepath}: {e}")
        raise


def make_absolute_path(path: str) -> str:
    """Convert a relative path to an absolute path."""
    return os.path.abspath(path)
