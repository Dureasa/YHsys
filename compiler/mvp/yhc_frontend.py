#!/usr/bin/env python3
"""Frontend for YHC (YHsys tiny compiler) source language."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class AstNode:
    op: str
    value: object
    line: int


class ParseError(Exception):
    pass


def _decode_string_literal(text: str, line: int) -> str:
    text = text.strip()
    if len(text) < 2 or text[0] != '"' or text[-1] != '"':
        raise ParseError(f"line {line}: string literal must be wrapped in double quotes")

    body = text[1:-1]
    out = []
    i = 0
    while i < len(body):
        ch = body[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue

        i += 1
        if i >= len(body):
            raise ParseError(f"line {line}: invalid escape at end of string")
        esc = body[i]
        if esc == "n":
            out.append("\n")
        elif esc == "t":
            out.append("\t")
        elif esc == "r":
            out.append("\r")
        elif esc == "\\":
            out.append("\\")
        elif esc == '"':
            out.append('"')
        else:
            raise ParseError(f"line {line}: unsupported escape \\{esc}")
        i += 1

    return "".join(out)


def _strip_comments(line: str) -> str:
    # Supports // and # comments, while preserving quoted string bodies.
    in_str = False
    escaped = False
    i = 0
    while i < len(line):
        ch = line[i]
        if in_str:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_str = False
            i += 1
            continue

        if ch == '"':
            in_str = True
            i += 1
            continue

        if ch == "#":
            return line[:i]

        if ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
            return line[:i]

        i += 1

    return line


def parse_source(source: str) -> list[AstNode]:
    nodes: list[AstNode] = []

    for line_no, raw in enumerate(source.splitlines(), start=1):
        line = _strip_comments(raw).strip()
        if not line:
            continue

        if not line.endswith(";"):
            raise ParseError(f"line {line_no}: statement must end with ';'")

        stmt = line[:-1].strip()
        if not stmt:
            continue

        if stmt.startswith("print "):
            text = _decode_string_literal(stmt[len("print "):], line_no)
            nodes.append(AstNode(op="print", value=text, line=line_no))
            continue

        if stmt.startswith("write "):
            text = _decode_string_literal(stmt[len("write "):], line_no)
            nodes.append(AstNode(op="print", value=text, line=line_no))
            continue

        if stmt.startswith("pause "):
            num = stmt[len("pause "):].strip()
            if not num.isdigit():
                raise ParseError(f"line {line_no}: pause argument must be a non-negative integer")
            nodes.append(AstNode(op="pause", value=int(num), line=line_no))
            continue

        if stmt.startswith("exit "):
            num = stmt[len("exit "):].strip()
            if not num.isdigit():
                raise ParseError(f"line {line_no}: exit argument must be a non-negative integer")
            nodes.append(AstNode(op="exit", value=int(num), line=line_no))
            continue

        raise ParseError(
            f"line {line_no}: unsupported statement '{stmt}'. "
            "supported: print/write string, pause N, exit N"
        )

    return nodes
