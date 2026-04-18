#!/usr/bin/env python3
"""Compatibility wrapper for legacy frontend API."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from compiler.frontend.lexer.tokenizer import tokenize  # noqa: E402
from compiler.frontend.parser.parser import Parser  # noqa: E402
from compiler.utils.errors import ParserError as ParseError  # noqa: E402


def parse_source(source: str):
    return Parser(tokenize(source)).parse_program()


__all__ = ["ParseError", "parse_source"]
