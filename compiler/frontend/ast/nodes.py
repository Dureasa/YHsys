"""Typed AST for the SysY-like YHC frontend."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

from compiler.utils.errors import SourceLocation


UnaryOp = Literal["+", "-", "!", "~"]
BinaryOp = Literal[
    "+",
    "-",
    "*",
    "/",
    "%",
    "<<",
    ">>",
    "<",
    "<=",
    ">",
    ">=",
    "==",
    "!=",
    "&",
    "^",
    "|",
    "&&",
    "||",
]
AssignOp = Literal["=", "+=", "-=", "*=", "/=", "%="]
IncDecOp = Literal["++", "--"]


@dataclass(frozen=True)
class IntLiteral:
    value: int
    loc: SourceLocation


@dataclass(frozen=True)
class VariableExpr:
    name: str
    loc: SourceLocation


@dataclass(frozen=True)
class ArrayAccessExpr:
    name: str
    index: "Expression"
    loc: SourceLocation


@dataclass(frozen=True)
class UnaryExpr:
    op: UnaryOp
    operand: "Expression"
    loc: SourceLocation


@dataclass(frozen=True)
class BinaryExpr:
    op: BinaryOp
    lhs: "Expression"
    rhs: "Expression"
    loc: SourceLocation


Expression = IntLiteral | VariableExpr | ArrayAccessExpr | UnaryExpr | BinaryExpr


@dataclass(frozen=True)
class LValue:
    name: str
    index: Expression | None
    loc: SourceLocation


BuiltinName = Literal["print_int", "print_str", "pause"]


@dataclass(frozen=True)
class VarDecl:
    name: str
    size: int | None
    init: Expression | None
    loc: SourceLocation


@dataclass(frozen=True)
class AssignStmt:
    target: LValue
    op: AssignOp
    expr: Expression
    loc: SourceLocation


@dataclass(frozen=True)
class IncDecStmt:
    target: LValue
    op: IncDecOp
    loc: SourceLocation


@dataclass(frozen=True)
class BuiltinCallStmt:
    name: BuiltinName
    arg_expr: Expression | None
    arg_string: str | None
    loc: SourceLocation


@dataclass(frozen=True)
class IfStmt:
    cond: Expression
    then_block: "Block"
    else_branch: "Block | IfStmt | None"
    loc: SourceLocation


@dataclass(frozen=True)
class WhileStmt:
    cond: Expression
    body: "Block"
    loc: SourceLocation


@dataclass(frozen=True)
class ReturnStmt:
    expr: Expression
    loc: SourceLocation


@dataclass(frozen=True)
class EmptyStmt:
    loc: SourceLocation


Statement = VarDecl | AssignStmt | IncDecStmt | BuiltinCallStmt | IfStmt | WhileStmt | ReturnStmt | EmptyStmt


@dataclass(frozen=True)
class Block:
    statements: list[Statement] = field(default_factory=list)
    loc: SourceLocation = field(default_factory=lambda: SourceLocation(1, 1))


@dataclass(frozen=True)
class Program:
    body: Block
    loc: SourceLocation = field(default_factory=lambda: SourceLocation(1, 1))
