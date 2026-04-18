"""Compiler error types with source locations."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class SourceLocation:
    line: int
    column: int = 1

    def __str__(self) -> str:
        return f"line {self.line}:{self.column}"


class YHCError(Exception):
    """Base compiler error."""

    def __init__(self, message: str, location: SourceLocation | None = None):
        self.message = message
        self.location = location
        if location is None:
            super().__init__(message)
        else:
            super().__init__(f"{location}: {message}")


class LexError(YHCError):
    """Lexical analysis failure."""


class ParserError(YHCError):
    """Syntax analysis failure."""


class SemanticError(YHCError):
    """Semantic analysis failure."""


class CodegenError(YHCError):
    """Code generation failure."""
