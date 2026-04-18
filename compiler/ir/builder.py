"""Lower semantic AST into linear IR."""

from __future__ import annotations

from compiler.frontend.ast.nodes import (
    ArrayAccessExpr,
    AssignStmt,
    BinaryExpr,
    Block,
    BuiltinCallStmt,
    EmptyStmt,
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
from compiler.frontend.semantic.analyzer import SymbolInfo

from .ir_types import IRConstant, IRInstruction, IRModule, IRSymbol


class IRBuilder:
    def __init__(self, symbols: dict[str, SymbolInfo]):
        self.module = IRModule()
        self.module.symbols = [IRSymbol(name=s.name, size=s.size) for s in symbols.values()]
        self.label_id = 0
        self.const_id = 0
        self.has_return = False

    def fresh_label(self, prefix: str) -> str:
        self.label_id += 1
        return f"{prefix}_{self.label_id}"

    def add(self, op: str, **args) -> None:
        self.module.instructions.append(IRInstruction(op=op, args=args))

    def add_const_string(self, text: str) -> str:
        cid = f"str{self.const_id}"
        self.const_id += 1
        self.module.constants.append(IRConstant(cid=cid, text=text, size=len(text.encode("utf-8"))))
        return cid

    def lower_lvalue(self, lval: LValue) -> dict:
        if lval.index is None:
            return {"kind": "var", "name": lval.name}
        return {"kind": "array", "name": lval.name, "index": self.lower_expr(lval.index)}

    def lower_expr(self, expr) -> dict:
        if isinstance(expr, IntLiteral):
            return {"kind": "int", "value": expr.value}
        if isinstance(expr, VariableExpr):
            return {"kind": "var", "name": expr.name}
        if isinstance(expr, ArrayAccessExpr):
            return {"kind": "array", "name": expr.name, "index": self.lower_expr(expr.index)}
        if isinstance(expr, UnaryExpr):
            return {"kind": "unary", "op": expr.op, "operand": self.lower_expr(expr.operand)}
        if isinstance(expr, BinaryExpr):
            return {
                "kind": "binop",
                "op": expr.op,
                "lhs": self.lower_expr(expr.lhs),
                "rhs": self.lower_expr(expr.rhs),
            }
        raise ValueError(f"unsupported expression type: {type(expr)}")

    def lower_assign(self, stmt: AssignStmt) -> None:
        target = self.lower_lvalue(stmt.target)
        rhs = self.lower_expr(stmt.expr)
        if stmt.op == "=":
            self.add("assign", target=target, expr=rhs)
            return

        op_map = {
            "+=": "+",
            "-=": "-",
            "*=": "*",
            "/=": "/",
            "%=": "%",
        }
        bin_expr = {"kind": "binop", "op": op_map[stmt.op], "lhs": target, "rhs": rhs}
        self.add("assign", target=target, expr=bin_expr)

    def lower_incdec(self, stmt: IncDecStmt) -> None:
        target = self.lower_lvalue(stmt.target)
        delta = 1 if stmt.op == "++" else -1
        expr = {
            "kind": "binop",
            "op": "+",
            "lhs": target,
            "rhs": {"kind": "int", "value": delta},
        }
        self.add("assign", target=target, expr=expr)

    def lower_if(self, stmt: IfStmt) -> None:
        then_label = self.fresh_label("if_then")
        else_label = self.fresh_label("if_else")
        end_label = self.fresh_label("if_end")

        self.add("if_goto", cond=self.lower_expr(stmt.cond), label=then_label)
        self.add("goto", label=else_label)
        self.add("label", name=then_label)
        self.lower_block(stmt.then_block)
        self.add("goto", label=end_label)
        self.add("label", name=else_label)

        if stmt.else_branch is not None:
            if isinstance(stmt.else_branch, Block):
                self.lower_block(stmt.else_branch)
            else:
                self.lower_stmt(stmt.else_branch)
        self.add("label", name=end_label)

    def lower_while(self, stmt: WhileStmt) -> None:
        cond_label = self.fresh_label("while_cond")
        body_label = self.fresh_label("while_body")
        end_label = self.fresh_label("while_end")

        self.add("label", name=cond_label)
        self.add("if_goto", cond=self.lower_expr(stmt.cond), label=body_label)
        self.add("goto", label=end_label)
        self.add("label", name=body_label)
        self.lower_block(stmt.body)
        self.add("goto", label=cond_label)
        self.add("label", name=end_label)

    def lower_call(self, stmt: BuiltinCallStmt) -> None:
        if stmt.name == "print_str":
            cid = self.add_const_string(stmt.arg_string or "")
            self.add("sys_write_const", fd=1, const=cid, size=len((stmt.arg_string or "").encode("utf-8")))
            return
        if stmt.name == "print_int":
            self.add("sys_write_expr", expr=self.lower_expr(stmt.arg_expr))
            return
        if stmt.name == "pause":
            self.add("sys_pause_expr", expr=self.lower_expr(stmt.arg_expr))
            return
        raise ValueError(f"unsupported builtin {stmt.name}")

    def lower_stmt(self, stmt) -> None:
        if isinstance(stmt, VarDecl):
            target = {"kind": "var", "name": stmt.name}
            if stmt.size is not None:
                self.add("array_zero", name=stmt.name, size=stmt.size)
                return
            init_expr = self.lower_expr(stmt.init) if stmt.init is not None else {"kind": "int", "value": 0}
            self.add("assign", target=target, expr=init_expr)
            return
        if isinstance(stmt, AssignStmt):
            self.lower_assign(stmt)
            return
        if isinstance(stmt, IncDecStmt):
            self.lower_incdec(stmt)
            return
        if isinstance(stmt, BuiltinCallStmt):
            self.lower_call(stmt)
            return
        if isinstance(stmt, IfStmt):
            self.lower_if(stmt)
            return
        if isinstance(stmt, WhileStmt):
            self.lower_while(stmt)
            return
        if isinstance(stmt, ReturnStmt):
            self.add("sys_exit_expr", expr=self.lower_expr(stmt.expr))
            self.has_return = True
            return
        if isinstance(stmt, EmptyStmt):
            return
        raise ValueError(f"unsupported statement type: {type(stmt)}")

    def lower_block(self, block: Block) -> None:
        for stmt in block.statements:
            self.lower_stmt(stmt)

    def finalize(self) -> IRModule:
        if not self.has_return:
            self.add("sys_exit_expr", expr={"kind": "int", "value": 0})
        self.module.symbols = sorted(self.module.symbols, key=lambda s: s.name)
        return self.module


def lower_program(program: Program, symbols: dict[str, SymbolInfo]) -> dict:
    builder = IRBuilder(symbols)
    builder.lower_block(program.body)
    module = builder.finalize()
    return module.to_dict()
