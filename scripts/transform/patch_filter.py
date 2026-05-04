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
from typing import List, Optional, Tuple


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


# ── Public entry point ─────────────────────────────────────────────────────────

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
