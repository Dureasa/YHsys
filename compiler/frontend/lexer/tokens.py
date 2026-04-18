"""Token definitions for YHC lexer."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto

from compiler.utils.errors import SourceLocation


class TokenKind(Enum):
    KEYWORD = auto()
    IDENT = auto()
    INT = auto()
    STRING = auto()
    SYMBOL = auto()
    EOF = auto()


@dataclass(frozen=True)
class Token:
    kind: TokenKind
    value: str
    loc: SourceLocation
