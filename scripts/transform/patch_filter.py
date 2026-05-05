"""
Filter unwanted import-related noise from git unified diff patches.

CodeCocoon runs inside the IntelliJ platform whose import optimizer fires
automatically and cannot be disabled.  It produces two kinds of noise:

  1. Import reordering  — the same set of imports, shuffled in order.
     Both base and test/fix patches then touch the same context lines,
     causing `git apply` conflicts.

  2. Wildcard import removal  — IntelliJ collapses `import pkg.*;` into
     explicit imports (or just removes the wildcard), breaking compilation
     when explicit replacements are not added.

`filter_import_changes()` is the public entry point.  It returns a
`PatchFilterResult` with the cleaned patch and an audit list of every
change that was removed.
"""

import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple


# ── Regexes ────────────────────────────────────────────────────────────────────

_HUNK_HEADER_RE = re.compile(
    r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)'
)
_IMPORT_RE   = re.compile(r'^import(\s+static)?\s+\S')
_WILDCARD_RE = re.compile(r'^import(\s+static)?\s+\S+\.\*\s*;')


# ── Data types ─────────────────────────────────────────────────────────────────

@dataclass
class HunkLine:
    line_type: str  # 'context' | 'added' | 'removed' | 'meta'
    content: str    # content after the prefix char; for 'meta', the whole raw line


@dataclass
class Hunk:
    old_start: int
    old_count: int
    new_start: int
    new_count: int
    trailing: str        # text after @@ -a,b +c,d @@ (e.g. method name)
    lines: List[HunkLine]

    def header(self) -> str:
        old_c = f",{self.old_count}" if self.old_count != 1 else ""
        new_c = f",{self.new_count}" if self.new_count != 1 else ""
        trail = self.trailing  # already includes leading space if non-empty
        return f"@@ -{self.old_start}{old_c} +{self.new_start}{new_c} @@{trail}"

    def render(self) -> str:
        parts = [self.header()]
        for line in self.lines:
            if line.line_type == 'context':
                parts.append(' ' + line.content)
            elif line.line_type == 'added':
                parts.append('+' + line.content)
            elif line.line_type == 'removed':
                parts.append('-' + line.content)
            else:  # meta (e.g. "\ No newline at end of file")
                parts.append(line.content)
        return '\n'.join(parts)

    def net_change(self) -> int:
        added   = sum(1 for l in self.lines if l.line_type == 'added')
        removed = sum(1 for l in self.lines if l.line_type == 'removed')
        return added - removed

    def has_changes(self) -> bool:
        return any(l.line_type in ('added', 'removed') for l in self.lines)


@dataclass
class FileDiff:
    header_lines: List[str]  # diff --git, index, ---, +++
    hunks: List[Hunk]

    def file_path(self) -> str:
        for line in self.header_lines:
            m = re.match(r'^diff --git a/(.+) b/.+$', line)
            if m:
                return m.group(1)
        return ''

    def render(self) -> str:
        parts = list(self.header_lines)
        for hunk in self.hunks:
            parts.append(hunk.render())
        return '\n'.join(parts)


@dataclass
class ImportFix:
    """Records one unwanted import change that was stripped from the patch."""
    problem_type: str           # 'import_reorder' | 'wildcard_import_removal'
    file: str                   # relative path from the diff header
    original_hunk_header: str   # @@ line as it appeared before filtering
    removed_block: Optional[str] = None         # set when the entire hunk was dropped
    removed_lines: List[str]    = field(default_factory=list)  # '-import ...' lines removed


@dataclass
class PatchFilterResult:
    filtered_patch: str
    fixes: List[ImportFix] = field(default_factory=list)


# ── Parsing ────────────────────────────────────────────────────────────────────

def _parse_hunk_line(raw: str) -> HunkLine:
    if raw.startswith('+') and not raw.startswith('+++'):
        return HunkLine('added',   raw[1:])
    if raw.startswith('-') and not raw.startswith('---'):
        return HunkLine('removed', raw[1:])
    if raw.startswith(' '):
        return HunkLine('context', raw[1:])
    # "\ No newline at end of file" and any other unexpected prefix
    return HunkLine('meta', raw)


def _parse_patch(patch: str) -> List[FileDiff]:
    """Parse a git unified diff into a list of FileDiff objects."""
    lines = patch.split('\n')
    file_diffs: List[FileDiff] = []
    i = 0
    n = len(lines)

    while i < n:
        if not lines[i].startswith('diff --git'):
            i += 1
            continue

        # Consume the 'diff --git' line first, then collect remaining header lines
        # (index, ---, +++) until the first hunk or the next file section.
        header_lines: List[str] = [lines[i]]
        i += 1
        while i < n and not lines[i].startswith('@@ ') and not lines[i].startswith('diff --git'):
            header_lines.append(lines[i])
            i += 1

        # Collect hunks
        hunks: List[Hunk] = []
        while i < n and not lines[i].startswith('diff --git'):
            if not lines[i].startswith('@@ '):
                i += 1
                continue

            m = _HUNK_HEADER_RE.match(lines[i])
            if not m:
                i += 1
                continue

            old_start = int(m.group(1))
            old_count = int(m.group(2)) if m.group(2) is not None else 1
            new_start = int(m.group(3))
            new_count = int(m.group(4)) if m.group(4) is not None else 1
            trailing  = m.group(5)      # may be "" or " method_name ..."
            i += 1

            hunk_lines: List[HunkLine] = []
            while i < n and not lines[i].startswith('@@ ') and not lines[i].startswith('diff --git'):
                if lines[i] != '':
                    hunk_lines.append(_parse_hunk_line(lines[i]))
                # preserve truly blank separator lines between hunks as context
                else:
                    hunk_lines.append(HunkLine('context', ''))
                i += 1

            hunks.append(Hunk(
                old_start=old_start, old_count=old_count,
                new_start=new_start, new_count=new_count,
                trailing=trailing,   lines=hunk_lines,
            ))

        if header_lines:
            file_diffs.append(FileDiff(header_lines=header_lines, hunks=hunks))

    return file_diffs


# ── Detection ──────────────────────────────────────────────────────────────────

def _compute_import_blocks(hunk: Hunk) -> Tuple[List[Dict], List[Dict]]:
    """Return ``(original_block, current_block)`` for a reorder hunk.

    Each block is a list of ``{"line": int, "import": str}`` dicts covering
    *every* import visible in that version of the file window, including context
    lines that didn't change.  Line numbers are absolute (from the hunk header).

    ``original_block`` — import order as it was before CodeCocoon (old-file).
    ``current_block``  — import order as it is now in the file (new-file); this
    is what the agent will see when it opens the file.
    """
    original: List[Dict] = []
    current:  List[Dict] = []
    old_line = hunk.old_start
    new_line = hunk.new_start

    for l in hunk.lines:
        if l.line_type == 'context':
            if _IMPORT_RE.match(l.content.lstrip()):
                original.append({"line": old_line, "import": l.content})
                current.append( {"line": new_line, "import": l.content})
            old_line += 1
            new_line += 1
        elif l.line_type == 'removed':
            if _IMPORT_RE.match(l.content.lstrip()):
                original.append({"line": old_line, "import": l.content})
            old_line += 1
        elif l.line_type == 'added':
            if _IMPORT_RE.match(l.content.lstrip()):
                current.append({"line": new_line, "import": l.content})
            new_line += 1
        # meta lines ("\ No newline at end of file") don't advance line counters

    return original, current


def _is_import_reorder(hunk: Hunk) -> bool:
    """Return True iff every changed line is an import AND removed-set == added-set."""
    changed = [l for l in hunk.lines if l.line_type in ('added', 'removed')]
    if not changed:
        return False
    if not all(_IMPORT_RE.match(l.content.lstrip()) for l in changed):
        return False
    added_set   = frozenset(l.content for l in changed if l.line_type == 'added')
    removed_set = frozenset(l.content for l in changed if l.line_type == 'removed')
    return added_set == removed_set


def _wildcard_removal_indices(hunk: Hunk) -> List[int]:
    """Return indices of removed lines that are wildcard import statements."""
    return [
        i for i, l in enumerate(hunk.lines)
        if l.line_type == 'removed' and _WILDCARD_RE.match(l.content.lstrip())
    ]


def _expand_with_adjacent_blank_removals(
    hunk_lines: List[HunkLine],
    base_indices: List[int],
) -> set:
    """Expand base_indices to also cover consecutive blank removed lines that
    are directly adjacent (before or after) to each base index.

    IntelliJ removes blank lines between import groups as part of the same
    import-optimizer pass, so those blank removals are equally noise.
    """
    result = set(base_indices)
    n = len(hunk_lines)
    for idx in base_indices:
        j = idx + 1
        while j < n and hunk_lines[j].line_type == 'removed' and hunk_lines[j].content.strip() == '':
            result.add(j)
            j += 1
        j = idx - 1
        while j >= 0 and hunk_lines[j].line_type == 'removed' and hunk_lines[j].content.strip() == '':
            result.add(j)
            j -= 1
    return result


# ── Per-hunk filtering ─────────────────────────────────────────────────────────

def _filter_hunk(
    hunk: Hunk,
    file_path: str,
) -> Tuple[Optional[Hunk], List[ImportFix]]:
    """
    Inspect one hunk and strip import noise.

    Returns (filtered_hunk_or_None, fixes).
    None means the entire hunk was eliminated.
    """
    fixes: List[ImportFix] = []
    original_header = hunk.header()

    # ── Rule 1: pure import reorder → drop entire hunk ────────────────────────
    if _is_import_reorder(hunk):
        fixes.append(ImportFix(
            problem_type='import_reorder',
            file=file_path,
            original_hunk_header=original_header,
            removed_block=hunk.render(),
        ))
        return None, fixes

    # ── Rule 2: wildcard import removal → drop those lines plus adjacent blanks ──
    wc_indices = _wildcard_removal_indices(hunk)
    if not wc_indices:
        return hunk, fixes

    # Expand to include blank removed lines immediately adjacent to each wildcard;
    # IntelliJ removes those as part of the same import-cleanup pass.
    drop_set = _expand_with_adjacent_blank_removals(hunk.lines, wc_indices)

    removed_lines = [
        f"-{hunk.lines[i].content}" if hunk.lines[i].content.strip() else "-<blank line>"
        for i in sorted(drop_set)
    ]
    fixes.append(ImportFix(
        problem_type='wildcard_import_removal',
        file=file_path,
        original_hunk_header=original_header,
        removed_lines=removed_lines,
    ))

    # Convert the filtered lines to context instead of dropping them.
    # Dropping them would shrink old_count, making the hunk header disagree
    # with the actual file (those lines still exist) and causing git apply to fail.
    # Converting to context keeps old_count correct while leaving the lines untouched.
    filtered_lines = [
        HunkLine('context', l.content) if i in drop_set else l
        for i, l in enumerate(hunk.lines)
    ]

    new_old_count = sum(
        1 for l in filtered_lines if l.line_type in ('context', 'removed')
    )
    new_new_count = sum(
        1 for l in filtered_lines if l.line_type in ('context', 'added')
    )

    filtered_hunk = Hunk(
        old_start=hunk.old_start,
        old_count=new_old_count,
        new_start=hunk.new_start,
        new_count=new_new_count,
        trailing=hunk.trailing,
        lines=filtered_lines,
    )

    if not filtered_hunk.has_changes():
        # The hunk contained only wildcard/blank removals → nothing left to apply.
        # Drop it entirely (net change is the same as converting all to context).
        fixes[0].removed_block = hunk.render()
        return None, fixes

    return filtered_hunk, fixes


# ── Public entry points ────────────────────────────────────────────────────────

def collect_unwanted_hunks(patch: str, logger=None) -> List[Dict]:
    """Return a list of structured dicts describing every import-noise hunk in *patch*.

    Each dict carries enough information for an AI agent to locate and revert
    the noise in the source files:

      - ``file``            relative path of the affected file
      - ``hunk_type``       ``"import_reorder"``, ``"wildcard_import_removal"``, or
                            ``"import_cross_hunk_move"``
      - ``description``     human-readable explanation of the problem and the fix
      - ``hunk_header``     the ``@@ ... @@`` line as it appears in the diff
      - ``old_start_line``  first line of the old-file window
      - ``old_line_count``  number of lines in the old-file window
      - ``new_start_line``  first line of the new-file window
      - ``new_line_count``  number of lines in the new-file window
      - ``action``          one-sentence instruction for the agent
      - ``full_hunk_diff``  the complete rendered hunk text (for reference)

    Import-reorder dicts also carry:
      - ``original_import_block``  all imports in the hunk window BEFORE CodeCocoon
      - ``current_import_block``   all imports in the hunk window as they are NOW

    Wildcard-removal dicts also carry:
      - ``removed_wildcards``  import lines (and blank lines as "") that were removed

    Cross-hunk-move dicts also carry:
      - ``cross_move_role``   ``"spurious_addition"`` or ``"missing_import"``
      - ``moved_imports``     list of import lines participating in the move
    """
    if not patch:
        return []

    file_diffs = _parse_patch(patch)
    result: List[Dict] = []

    for file_diff in file_diffs:
        file_path = file_diff.file_path()
        flagged_hunk_indices: set = set()

        # ── Pass 1: per-hunk noise (reorders and wildcard removals) ──────────────
        for hunk_idx, hunk in enumerate(file_diff.hunks):
            if _is_import_reorder(hunk):
                flagged_hunk_indices.add(hunk_idx)
                original_import_block, current_import_block = _compute_import_blocks(hunk)
                first_orig_line    = original_import_block[0]["line"] if original_import_block else hunk.old_start
                first_current_line = current_import_block[0]["line"]  if current_import_block  else hunk.new_start
                result.append({
                    "id": f"hunk-{len(result)}",
                    "file": file_path,
                    "hunk_type": "import_reorder",
                    "description": (
                        "IntelliJ's import optimizer reshuffled existing imports without adding "
                        "or removing any statement. The exact same set of import lines appears in "
                        "a different order. This is noise: the file must be restored to use the "
                        "ORIGINAL import order. "
                        f"'original_import_block' lists ALL imports in this region as they were "
                        f"BEFORE CodeCocoon (starting at line {first_orig_line} in the original file), "
                        f"including context lines whose absolute positions did not change. "
                        f"'current_import_block' lists the SAME imports as they appear NOW in the "
                        f"file (starting at line {first_current_line}). "
                        "The import sets are identical — only the order differs."
                    ),
                    "hunk_header": hunk.header(),
                    "old_start_line": hunk.old_start,
                    "old_line_count": hunk.old_count,
                    "new_start_line": hunk.new_start,
                    "new_line_count": hunk.new_count,
                    "original_import_block": original_import_block,
                    "current_import_block":  current_import_block,
                    "action": (
                        f"In the file '{file_path}', locate the import block starting around "
                        f"line {first_current_line} (as shown in 'current_import_block') and "
                        "reorder the imports so they appear in the exact sequence given by "
                        "'original_import_block'. "
                        "Do not add or remove any import statement — only change their order."
                    ),
                    "full_hunk_diff": hunk.render(),
                })
                continue

            wc_indices = _wildcard_removal_indices(hunk)
            if wc_indices:
                flagged_hunk_indices.add(hunk_idx)
                drop_set = _expand_with_adjacent_blank_removals(hunk.lines, wc_indices)
                # Include blank lines (as "") so the agent knows to restore them too.
                # Adjacent blank lines between import groups are removed by IntelliJ alongside
                # the wildcard import and must also be added back.
                removed_wildcards = [
                    hunk.lines[i].content
                    for i in sorted(drop_set)
                ]
                result.append({
                    "id": f"hunk-{len(result)}",
                    "file": file_path,
                    "hunk_type": "wildcard_import_removal",
                    "description": (
                        "IntelliJ's import optimizer removed one or more wildcard import "
                        "statements (e.g., 'import static pkg.*;') and any adjacent blank "
                        "separator lines. These must all be restored: entries in "
                        "'removed_wildcards' with an empty string (\"\") represent blank "
                        "lines that were also removed and must be added back alongside the "
                        "import statements."
                    ),
                    "hunk_header": hunk.header(),
                    "old_start_line": hunk.old_start,
                    "old_line_count": hunk.old_count,
                    "new_start_line": hunk.new_start,
                    "new_line_count": hunk.new_count,
                    "removed_wildcards": removed_wildcards,
                    "action": (
                        "In the file, add back every entry in 'removed_wildcards' to the "
                        "import section, preserving their relative order. Import lines "
                        "contain the import statement text; empty-string entries (\"\") "
                        "represent blank separator lines. Position them where they originally "
                        "appeared (around line new_start_line). Do not modify any other "
                        "imports."
                    ),
                    "full_hunk_diff": hunk.render(),
                })

        # ── Pass 2: cross-hunk import move detection ──────────────────────────────
        # When IntelliJ moves an import far enough that git creates two separate hunks
        # (one adding it at the new position, one removing it from the original), neither
        # hunk individually satisfies _is_import_reorder.  Detect them here by finding
        # imports that appear in both the global added-set and removed-set of UNFLAGGED hunks.
        file_added_imports:   set = set()
        file_removed_imports: set = set()
        for hunk_idx, hunk in enumerate(file_diff.hunks):
            if hunk_idx in flagged_hunk_indices:
                continue  # already accounted for by pass 1
            for line in hunk.lines:
                if line.line_type == 'added' and _IMPORT_RE.match(line.content.lstrip()):
                    file_added_imports.add(line.content)
                elif line.line_type == 'removed' and _IMPORT_RE.match(line.content.lstrip()):
                    file_removed_imports.add(line.content)

        cross_moved = file_added_imports & file_removed_imports
        if cross_moved:
            for hunk_idx, hunk in enumerate(file_diff.hunks):
                if hunk_idx in flagged_hunk_indices:
                    continue

                changed = [l for l in hunk.lines if l.line_type in ('added', 'removed')]
                if not changed:
                    continue

                # All non-blank changed lines must be imports in cross_moved.
                # A hunk with any real (non-moved) change is not pure import noise.
                non_blank = [l for l in changed if l.content.strip()]
                if not non_blank:
                    continue
                if not all(_IMPORT_RE.match(l.content.lstrip()) for l in non_blank):
                    continue
                if not all(l.content in cross_moved for l in non_blank):
                    continue

                flagged_hunk_indices.add(hunk_idx)
                added_imps   = [l.content for l in non_blank if l.line_type == 'added']
                removed_imps = [l.content for l in non_blank if l.line_type == 'removed']

                if added_imps and not removed_imps:
                    role = "spurious_addition"
                    moved = added_imps
                    role_desc = (
                        "it spuriously adds the import(s) at a new position — "
                        "this insertion must be reverted (the import should not be here)"
                    )
                    action_detail = (
                        f"REMOVE the following import(s) from around line {hunk.new_start} "
                        "— IntelliJ's optimizer inserted them here while moving them away "
                        "from their original location: "
                        + ", ".join(f"'{i}'" for i in moved)
                    )
                elif removed_imps and not added_imps:
                    role = "missing_import"
                    moved = removed_imps
                    role_desc = (
                        "it incorrectly removes the import(s) from their original position "
                        "— this removal must be reverted (the import should stay here)"
                    )
                    action_detail = (
                        f"ADD BACK the following import(s) at around line {hunk.new_start} "
                        "— IntelliJ's optimizer removed them from here while moving them "
                        "to a new location: "
                        + ", ".join(f"'{i}'" for i in moved)
                    )
                else:
                    role = "mixed"
                    moved = list({l.content for l in non_blank})
                    role_desc = "it mixes additions and removals of cross-hunk moved imports"
                    action_detail = (
                        f"Revert the import changes around line {hunk.new_start} — "
                        "these are cross-hunk import moves by IntelliJ's optimizer"
                    )

                result.append({
                    "id": f"hunk-{len(result)}",
                    "file": file_path,
                    "hunk_type": "import_cross_hunk_move",
                    "cross_move_role": role,
                    "moved_imports": moved,
                    "description": (
                        "IntelliJ's import optimizer moved import statement(s) between two "
                        "distant locations in the file, producing two separate diff hunks that "
                        "cannot be detected as a single reorder. Together they form a "
                        "cross-hunk import move that must be reverted. "
                        f"This hunk is the '{role}' side of the move: {role_desc}."
                    ),
                    "hunk_header": hunk.header(),
                    "old_start_line": hunk.old_start,
                    "old_line_count": hunk.old_count,
                    "new_start_line": hunk.new_start,
                    "new_line_count": hunk.new_count,
                    "action": (
                        f"In the file '{file_path}': {action_detail}. "
                        "Do not modify any other imports."
                    ),
                    "full_hunk_diff": hunk.render(),
                })

    if logger and result:
        logger.info(
            f"collect_unwanted_hunks: found {len(result)} import-noise hunk(s) "
            f"across {len({h['file'] for h in result})} file(s)"
        )
    return result


def filter_import_changes(
    patch: str,
    logger=None,
    patch_label: str = '',
) -> PatchFilterResult:
    """
    Strip import reorders and wildcard import removals from a git unified diff.

    Args:
        patch:       The git unified diff string to filter.
        logger:      Optional logger; when provided, each fix and a summary line
                     are logged at INFO level.
        patch_label: Human-readable label for this patch, e.g. 'base patch',
                     'test patch', 'fix patch'.  Included in the summary log line.

    Returns PatchFilterResult with the cleaned patch and an audit list of
    every ImportFix that was applied.
    """
    if not patch:
        return PatchFilterResult(filtered_patch=patch)

    file_diffs  = _parse_patch(patch)
    all_fixes:  List[ImportFix] = []
    result_fds: List[FileDiff]  = []

    for file_diff in file_diffs:
        file_path = file_diff.file_path()
        new_hunks: List[Hunk] = []
        new_file_offset = 0  # cumulative new-file line offset within this file

        for hunk in file_diff.hunks:
            original_net = hunk.net_change()

            # Apply cumulative new-file offset to this hunk's +start
            adjusted_hunk = Hunk(
                old_start=hunk.old_start,
                old_count=hunk.old_count,
                new_start=hunk.new_start + new_file_offset,
                new_count=hunk.new_count,
                trailing=hunk.trailing,
                lines=hunk.lines,
            )

            filtered_hunk, fixes = _filter_hunk(adjusted_hunk, file_path)
            all_fixes.extend(fixes)

            if filtered_hunk is not None:
                new_hunks.append(filtered_hunk)
                new_file_offset += filtered_hunk.net_change() - original_net
            else:
                # Hunk removed entirely; its net effect vanishes
                new_file_offset += 0 - original_net

        if new_hunks:
            result_fds.append(FileDiff(header_lines=file_diff.header_lines, hunks=new_hunks))
        elif file_diff.hunks and logger:
            logger.info(f"  File '{file_path}' removed entirely (all hunks filtered)")

    if logger and all_fixes:
        for fix in all_fixes:
            logger.info(f"  [{fix.problem_type}] {fix.file}: {fix.original_hunk_header}")
            if fix.removed_lines:
                for rl in fix.removed_lines:
                    logger.info(f"    removed: {rl}")
        label = f"[{patch_label}] " if patch_label else ""
        logger.info(f"{label}Filtered {len(all_fixes)} import noise fix(es)")

    # Reconstruct patch string; preserve trailing newline if original had one
    parts = [fd.render() for fd in result_fds]
    filtered_patch = '\n'.join(parts)
    if patch.endswith('\n') and filtered_patch and not filtered_patch.endswith('\n'):
        filtered_patch += '\n'

    return PatchFilterResult(filtered_patch=filtered_patch, fixes=all_fixes)
