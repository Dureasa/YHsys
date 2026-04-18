"""Tokenizer for SysY-like YHC language."""

from __future__ import annotations

from compiler.utils.errors import LexError, SourceLocation

from .tokens import Token, TokenKind

KEYWORDS = {"int", "main", "if", "else", "while", "return"}

THREE_CHAR_OPS = set()
TWO_CHAR_OPS = {
    "==",
    "!=",
    "<=",
    ">=",
    "&&",
    "||",
    "+=",
    "-=",
    "*=",
    "/=",
    "%=",
    "++",
    "--",
    "<<",
    ">>",
}
ONE_CHAR_SYMBOLS = set("(){}[];=,+-*/%<>!&|^~")


def _decode_string_literal(body: str, loc: SourceLocation) -> str:
    out: list[str] = []
    i = 0
    while i < len(body):
        ch = body[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        i += 1
        if i >= len(body):
            raise LexError("invalid escape at end of string literal", loc)
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
            raise LexError(f"unsupported escape '\\{esc}'", loc)
        i += 1
    return "".join(out)


def tokenize(source: str) -> list[Token]:
    tokens: list[Token] = []
    i = 0
    line = 1
    col = 1
    n = len(source)

    def cur_loc() -> SourceLocation:
        return SourceLocation(line, col)

    while i < n:
        ch = source[i]

        if ch in " \t\r":
            i += 1
            col += 1
            continue
        if ch == "\n":
            i += 1
            line += 1
            col = 1
            continue

        if source.startswith("//", i):
            while i < n and source[i] != "\n":
                i += 1
                col += 1
            continue
        if ch == "#":
            while i < n and source[i] != "\n":
                i += 1
                col += 1
            continue

        start = cur_loc()

        if ch == '"':
            i += 1
            col += 1
            raw: list[str] = []
            escaped = False
            while i < n:
                c = source[i]
                if c == "\n":
                    if not escaped:
                        raise LexError("unterminated string literal", start)
                    line += 1
                    col = 1
                if escaped:
                    raw.append(c)
                    escaped = False
                    i += 1
                    col += 1
                    continue
                if c == "\\":
                    escaped = True
                    raw.append(c)
                    i += 1
                    col += 1
                    continue
                if c == '"':
                    break
                raw.append(c)
                i += 1
                col += 1

            if i >= n or source[i] != '"':
                raise LexError("unterminated string literal", start)

            i += 1
            col += 1
            body = "".join(raw)
            tokens.append(Token(TokenKind.STRING, _decode_string_literal(body, start), start))
            continue

        if i + 3 <= n and source[i : i + 3] in THREE_CHAR_OPS:
            value = source[i : i + 3]
            tokens.append(Token(TokenKind.SYMBOL, value, start))
            i += 3
            col += 3
            continue

        if i + 2 <= n and source[i : i + 2] in TWO_CHAR_OPS:
            value = source[i : i + 2]
            tokens.append(Token(TokenKind.SYMBOL, value, start))
            i += 2
            col += 2
            continue

        if ch in ONE_CHAR_SYMBOLS:
            tokens.append(Token(TokenKind.SYMBOL, ch, start))
            i += 1
            col += 1
            continue

        if ch.isdigit():
            j = i
            while j < n and source[j].isdigit():
                j += 1
            value = source[i:j]
            tokens.append(Token(TokenKind.INT, value, start))
            col += j - i
            i = j
            continue

        if ch.isalpha() or ch == "_":
            j = i
            while j < n and (source[j].isalnum() or source[j] == "_"):
                j += 1
            ident = source[i:j]
            kind = TokenKind.KEYWORD if ident in KEYWORDS else TokenKind.IDENT
            tokens.append(Token(kind, ident, start))
            col += j - i
            i = j
            continue

        raise LexError(f"unexpected character '{ch}'", start)

    tokens.append(Token(TokenKind.EOF, "", SourceLocation(line, col)))
    return tokens
