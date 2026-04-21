from dataclasses import dataclass
from typing import List, Optional
from common.codecocoon import CodeCocoonResult


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
class MorphResult:
    succeeded: bool
    last_commit_sha: Optional[str] = None
    metamorphic_patch: Optional[str] = None
    codecocoon_result: Optional[CodeCocoonResult] = None


@dataclass
class EnvVar:
    name: str
    value: str | None

@dataclass
class EnvEntry:
    instance_id: str
    envs: List[EnvVar]
