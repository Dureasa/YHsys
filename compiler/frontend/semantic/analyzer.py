"""Semantic checks for declarations, uses, and array correctness."""

from __future__ import annotations

from dataclasses import dataclass

from compiler.frontend.ast.nodes import (
    ArrayAccessExpr,
    AssignStmt,
    BinaryExpr,
    Block,
    BuiltinCallStmt,
    CallExpr,
    EmptyStmt,
    ExprStmt,
    Expression,
    FunctionDef,
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


@dataclass(frozen=True)
class FunctionInfo:
    name: str
    params: list[str]
    symbols: dict[str, SymbolInfo]
    has_return: bool


@dataclass(frozen=True)
class ProgramInfo:
    functions: list[FunctionInfo]

    def function(self, name: str) -> FunctionInfo:
        for func in self.functions:
            if func.name == name:
                return func
        raise KeyError(name)

    @property
    def main(self) -> FunctionInfo:
        return self.function("main")

    @property
    def symbols(self) -> dict[str, SymbolInfo]:
        return self.main.symbols


class SemanticAnalyzer:
    BUILTIN_NAMES = {"print_int", "print_str", "pause"}
    MAX_CALL_ARGS = 6

    def __init__(self):
        self.symbols: dict[str, SymbolInfo] = {}
        self.has_return = False
        self.function_arities: dict[str, int] = {}

    def analyze(self, program: Program) -> ProgramInfo:
        infos: list[FunctionInfo] = []
        saw_main = False

        for func in program.functions:
            if func.name in self.BUILTIN_NAMES:
                raise SemanticError(f"function name '{func.name}' conflicts with builtin", func.loc)
            if func.name in self.function_arities:
                raise SemanticError(f"redefinition of function '{func.name}'", func.loc)
            if len(func.params) > self.MAX_CALL_ARGS:
                raise SemanticError("function has too many parameters; RV32 ABI supports a0-a5", func.loc)
            if func.name == "main":
                if saw_main:
                    raise SemanticError("redefinition of function 'main'", func.loc)
                if func.params:
                    raise SemanticError("main must not have parameters", func.loc)
                saw_main = True

            self.function_arities[func.name] = len(func.params)
            infos.append(self._analyze_function(func))

        if not saw_main:
            raise SemanticError("program must define int main()", program.loc)

        return ProgramInfo(functions=infos)

    def _analyze_function(self, func: FunctionDef) -> FunctionInfo:
        self.symbols = {}
        self.has_return = False

        for param in func.params:
            if param.name in self.symbols:
                raise SemanticError(f"redefinition of parameter '{param.name}'", param.loc)
            self.symbols[param.name] = SymbolInfo(param.name, None)

        self._analyze_block(func.body)
        return FunctionInfo(
            name=func.name,
            params=[p.name for p in func.params],
            symbols=dict(self.symbols),
            has_return=self.has_return,
        )

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
        if isinstance(expr, CallExpr):
            if expr.name not in self.function_arities:
                raise SemanticError(f"call to undefined function '{expr.name}'", expr.loc)
            expected = self.function_arities[expr.name]
            if len(expr.args) != expected:
                raise SemanticError(
                    f"function '{expr.name}' expects {expected} arguments, got {len(expr.args)}",
                    expr.loc,
                )
            if len(expr.args) > self.MAX_CALL_ARGS:
                raise SemanticError("function call has too many arguments; RV32 ABI supports a0-a5", expr.loc)
            for arg in expr.args:
                self._check_expr(arg)
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
        if isinstance(stmt, ExprStmt):
            if not isinstance(stmt.expr, CallExpr):
                raise SemanticError("only function calls may be used as expression statements", stmt.loc)
            self._check_expr(stmt.expr)
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
