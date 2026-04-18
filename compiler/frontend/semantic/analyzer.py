"""Semantic checks for declarations, uses, and array correctness."""

from __future__ import annotations

from dataclasses import dataclass

from compiler.frontend.ast.nodes import (
    ArrayAccessExpr,
    AssignStmt,
    BinaryExpr,
    Block,
    BuiltinCallStmt,
    EmptyStmt,
    Expression,
    IfStmt,
    IncDecStmt,
    IntLiteral,
    LValue,
    Program,
    ReturnStmt,
    UnaryExpr,
    VarDecl,
    VariableExpr,
    WhileStmt,
)
from compiler.utils.errors import SemanticError


@dataclass(frozen=True)
class SymbolInfo:
    name: str
    size: int | None  # None => scalar, int => array length

    @property
    def is_array(self) -> bool:
        return self.size is not None


class SemanticAnalyzer:
    def __init__(self):
        self.symbols: dict[str, SymbolInfo] = {}
        self.has_return = False

    def analyze(self, program: Program) -> dict[str, SymbolInfo]:
        self._analyze_block(program.body)
        return self.symbols

    def _declare(self, decl: VarDecl) -> None:
        if decl.name in self.symbols:
            raise SemanticError(f"redefinition of '{decl.name}'", decl.loc)
        if decl.size is not None and decl.size <= 0:
            raise SemanticError("array size must be positive", decl.loc)
        self.symbols[decl.name] = SymbolInfo(decl.name, decl.size)
        if decl.init is not None:
            if decl.size is not None:
                raise SemanticError("array declaration does not support scalar initializer", decl.loc)
            self._check_expr(decl.init)

    def _lookup(self, name: str, loc) -> SymbolInfo:
        sym = self.symbols.get(name)
        if sym is None:
            raise SemanticError(f"use of undeclared identifier '{name}'", loc)
        return sym

    def _check_lvalue(self, lval: LValue) -> SymbolInfo:
        sym = self._lookup(lval.name, lval.loc)
        if lval.index is None:
            if sym.is_array:
                raise SemanticError("array variable requires index", lval.loc)
            return sym
        if not sym.is_array:
            raise SemanticError("scalar variable cannot be indexed", lval.loc)
        self._check_expr(lval.index)
        return sym

    def _check_expr(self, expr: Expression) -> None:
        if isinstance(expr, IntLiteral):
            return
        if isinstance(expr, VariableExpr):
            sym = self._lookup(expr.name, expr.loc)
            if sym.is_array:
                raise SemanticError("array variable requires index", expr.loc)
            return
        if isinstance(expr, ArrayAccessExpr):
            sym = self._lookup(expr.name, expr.loc)
            if not sym.is_array:
                raise SemanticError("scalar variable cannot be indexed", expr.loc)
            self._check_expr(expr.index)
            return
        if isinstance(expr, UnaryExpr):
            self._check_expr(expr.operand)
            return
        if isinstance(expr, BinaryExpr):
            self._check_expr(expr.lhs)
            self._check_expr(expr.rhs)
            return
        raise SemanticError("unsupported expression node", getattr(expr, "loc", None))

    def _analyze_stmt(self, stmt) -> None:
        if isinstance(stmt, VarDecl):
            self._declare(stmt)
            return
        if isinstance(stmt, AssignStmt):
            self._check_lvalue(stmt.target)
            self._check_expr(stmt.expr)
            return
        if isinstance(stmt, IncDecStmt):
            self._check_lvalue(stmt.target)
            return
        if isinstance(stmt, BuiltinCallStmt):
            if stmt.name == "print_str":
                if stmt.arg_string is None:
                    raise SemanticError("print_str requires string literal", stmt.loc)
            else:
                if stmt.arg_expr is None:
                    raise SemanticError(f"{stmt.name} requires expression argument", stmt.loc)
                self._check_expr(stmt.arg_expr)
            return
        if isinstance(stmt, IfStmt):
            self._check_expr(stmt.cond)
            self._analyze_block(stmt.then_block)
            if stmt.else_branch is not None:
                if isinstance(stmt.else_branch, Block):
                    self._analyze_block(stmt.else_branch)
                else:
                    self._analyze_stmt(stmt.else_branch)
            return
        if isinstance(stmt, WhileStmt):
            self._check_expr(stmt.cond)
            self._analyze_block(stmt.body)
            return
        if isinstance(stmt, ReturnStmt):
            self._check_expr(stmt.expr)
            self.has_return = True
            return
        if isinstance(stmt, EmptyStmt):
            return
        raise SemanticError("unsupported statement node", getattr(stmt, "loc", None))

    def _analyze_block(self, block: Block) -> None:
        for stmt in block.statements:
            self._analyze_stmt(stmt)
