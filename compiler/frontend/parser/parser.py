"""Recursive descent parser with SysY-like precedence."""

from __future__ import annotations

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
    Param,
    Program,
    ReturnStmt,
    UnaryExpr,
    VarDecl,
    VariableExpr,
    WhileStmt,
)
from compiler.frontend.lexer.tokens import Token, TokenKind
from compiler.utils.errors import ParserError


class Parser:
    def __init__(self, tokens: list[Token]):
        self.tokens = tokens
        self.pos = 0

    def cur(self) -> Token:
        return self.tokens[self.pos]

    def bump(self) -> Token:
        tok = self.tokens[self.pos]
        self.pos += 1
        return tok

    def peek(self, offset: int = 1) -> Token:
        idx = min(self.pos + offset, len(self.tokens) - 1)
        return self.tokens[idx]

    def match(self, kind: TokenKind, value: str | None = None) -> Token | None:
        tok = self.cur()
        if tok.kind != kind:
            return None
        if value is not None and tok.value != value:
            return None
        self.pos += 1
        return tok

    def expect(self, kind: TokenKind, value: str | None = None) -> Token:
        tok = self.cur()
        if tok.kind != kind or (value is not None and tok.value != value):
            want = f"{kind.name}:{value}" if value is not None else kind.name
            got = f"{tok.kind.name}:{tok.value}"
            raise ParserError(f"expected {want}, got {got}", tok.loc)
        self.pos += 1
        return tok

    def parse_program(self) -> Program:
        functions: list[FunctionDef] = []
        first_loc = self.cur().loc
        while self.cur().kind != TokenKind.EOF:
            functions.append(self.parse_function_def())
        self.expect(TokenKind.EOF)
        if not functions:
            raise ParserError("expected function definition", first_loc)
        return Program(functions=functions, loc=first_loc)

    def parse_function_def(self) -> FunctionDef:
        start = self.expect(TokenKind.KEYWORD, "int")
        name = self.expect_function_name()
        self.expect(TokenKind.SYMBOL, "(")
        params = self.parse_param_list()
        self.expect(TokenKind.SYMBOL, ")")
        body = self.parse_block()
        return FunctionDef(name=name.value, params=params, body=body, loc=start.loc)

    def expect_function_name(self) -> Token:
        tok = self.cur()
        if tok.kind == TokenKind.IDENT or (tok.kind == TokenKind.KEYWORD and tok.value == "main"):
            self.pos += 1
            return tok
        raise ParserError("expected function name", tok.loc)

    def parse_param_list(self) -> list[Param]:
        params: list[Param] = []
        if self.cur().kind == TokenKind.SYMBOL and self.cur().value == ")":
            return params
        while True:
            self.expect(TokenKind.KEYWORD, "int")
            name = self.expect(TokenKind.IDENT)
            params.append(Param(name=name.value, loc=name.loc))
            if not self.match(TokenKind.SYMBOL, ","):
                break
        return params

    def parse_block(self) -> Block:
        lbrace = self.expect(TokenKind.SYMBOL, "{")
        statements = []
        while not self.match(TokenKind.SYMBOL, "}"):
            if self.cur().kind == TokenKind.EOF:
                raise ParserError("unterminated block", self.cur().loc)
            statements.append(self.parse_statement())
        return Block(statements=statements, loc=lbrace.loc)

    def parse_statement(self):
        tok = self.cur()
        if tok.kind == TokenKind.SYMBOL and tok.value == ";":
            self.bump()
            return EmptyStmt(loc=tok.loc)
        if tok.kind == TokenKind.KEYWORD and tok.value == "int":
            return self.parse_var_decl()
        if tok.kind == TokenKind.KEYWORD and tok.value == "if":
            return self.parse_if()
        if tok.kind == TokenKind.KEYWORD and tok.value == "while":
            return self.parse_while()
        if tok.kind == TokenKind.KEYWORD and tok.value == "return":
            return self.parse_return()
        if tok.kind == TokenKind.IDENT:
            if tok.value in ("print_int", "print_str", "pause"):
                return self.parse_builtin_call()
            if self.peek().kind == TokenKind.SYMBOL and self.peek().value == "(":
                expr = self.parse_call_expr()
                self.expect(TokenKind.SYMBOL, ";")
                return ExprStmt(expr=expr, loc=tok.loc)
            return self.parse_assignment_or_incdec()
        raise ParserError(f"unsupported statement start '{tok.value}'", tok.loc)

    def parse_var_decl(self) -> VarDecl:
        kw = self.expect(TokenKind.KEYWORD, "int")
        name = self.expect(TokenKind.IDENT)
        size: int | None = None
        init: Expression | None = None

        if self.match(TokenKind.SYMBOL, "["):
            size_tok = self.expect(TokenKind.INT)
            size = int(size_tok.value)
            self.expect(TokenKind.SYMBOL, "]")

        if self.match(TokenKind.SYMBOL, "="):
            init = self.parse_expression()
        self.expect(TokenKind.SYMBOL, ";")
        return VarDecl(name=name.value, size=size, init=init, loc=kw.loc)

    def parse_if(self) -> IfStmt:
        kw = self.expect(TokenKind.KEYWORD, "if")
        self.expect(TokenKind.SYMBOL, "(")
        cond = self.parse_expression()
        self.expect(TokenKind.SYMBOL, ")")
        then_block = self.parse_stmt_as_block()

        else_branch = None
        if self.match(TokenKind.KEYWORD, "else"):
            if self.cur().kind == TokenKind.KEYWORD and self.cur().value == "if":
                else_branch = self.parse_if()
            else:
                else_branch = self.parse_stmt_as_block()

        return IfStmt(cond=cond, then_block=then_block, else_branch=else_branch, loc=kw.loc)

    def parse_while(self) -> WhileStmt:
        kw = self.expect(TokenKind.KEYWORD, "while")
        self.expect(TokenKind.SYMBOL, "(")
        cond = self.parse_expression()
        self.expect(TokenKind.SYMBOL, ")")
        body = self.parse_stmt_as_block()
        return WhileStmt(cond=cond, body=body, loc=kw.loc)

    def parse_stmt_as_block(self) -> Block:
        if self.cur().kind == TokenKind.SYMBOL and self.cur().value == "{":
            return self.parse_block()
        stmt = self.parse_statement()
        return Block(statements=[stmt], loc=stmt.loc)

    def parse_return(self) -> ReturnStmt:
        kw = self.expect(TokenKind.KEYWORD, "return")
        expr = self.parse_expression()
        self.expect(TokenKind.SYMBOL, ";")
        return ReturnStmt(expr=expr, loc=kw.loc)

    def parse_builtin_call(self) -> BuiltinCallStmt:
        name = self.expect(TokenKind.IDENT)
        self.expect(TokenKind.SYMBOL, "(")
        if name.value == "print_str":
            s = self.expect(TokenKind.STRING)
            self.expect(TokenKind.SYMBOL, ")")
            self.expect(TokenKind.SYMBOL, ";")
            return BuiltinCallStmt(name="print_str", arg_expr=None, arg_string=s.value, loc=name.loc)

        arg_expr = self.parse_expression()
        self.expect(TokenKind.SYMBOL, ")")
        self.expect(TokenKind.SYMBOL, ";")
        return BuiltinCallStmt(name=name.value, arg_expr=arg_expr, arg_string=None, loc=name.loc)

    def parse_lvalue(self) -> LValue:
        ident = self.expect(TokenKind.IDENT)
        index = None
        if self.match(TokenKind.SYMBOL, "["):
            index = self.parse_expression()
            self.expect(TokenKind.SYMBOL, "]")
        return LValue(name=ident.value, index=index, loc=ident.loc)

    def parse_assignment_or_incdec(self):
        target = self.parse_lvalue()
        tok = self.cur()
        if tok.kind == TokenKind.SYMBOL and tok.value in ("++", "--"):
            self.bump()
            self.expect(TokenKind.SYMBOL, ";")
            return IncDecStmt(target=target, op=tok.value, loc=tok.loc)
        if tok.kind == TokenKind.SYMBOL and tok.value in ("=", "+=", "-=", "*=", "/=", "%="):
            self.bump()
            expr = self.parse_expression()
            self.expect(TokenKind.SYMBOL, ";")
            return AssignStmt(target=target, op=tok.value, expr=expr, loc=tok.loc)
        raise ParserError("expected assignment or increment/decrement", tok.loc)

    def parse_call_expr(self) -> CallExpr:
        name = self.expect(TokenKind.IDENT)
        self.expect(TokenKind.SYMBOL, "(")
        args: list[Expression] = []
        if not (self.cur().kind == TokenKind.SYMBOL and self.cur().value == ")"):
            while True:
                args.append(self.parse_expression())
                if not self.match(TokenKind.SYMBOL, ","):
                    break
        self.expect(TokenKind.SYMBOL, ")")
        return CallExpr(name=name.value, args=args, loc=name.loc)

    def parse_expression(self) -> Expression:
        return self.parse_logical_or()

    def parse_logical_or(self) -> Expression:
        expr = self.parse_logical_and()
        while self.match(TokenKind.SYMBOL, "||"):
            op_tok = self.tokens[self.pos - 1]
            rhs = self.parse_logical_and()
            expr = BinaryExpr("||", expr, rhs, op_tok.loc)
        return expr

    def parse_logical_and(self) -> Expression:
        expr = self.parse_bitwise_or()
        while self.match(TokenKind.SYMBOL, "&&"):
            op_tok = self.tokens[self.pos - 1]
            rhs = self.parse_bitwise_or()
            expr = BinaryExpr("&&", expr, rhs, op_tok.loc)
        return expr

    def parse_bitwise_or(self) -> Expression:
        expr = self.parse_bitwise_xor()
        while self.match(TokenKind.SYMBOL, "|"):
            op_tok = self.tokens[self.pos - 1]
            rhs = self.parse_bitwise_xor()
            expr = BinaryExpr("|", expr, rhs, op_tok.loc)
        return expr

    def parse_bitwise_xor(self) -> Expression:
        expr = self.parse_bitwise_and()
        while self.match(TokenKind.SYMBOL, "^"):
            op_tok = self.tokens[self.pos - 1]
            rhs = self.parse_bitwise_and()
            expr = BinaryExpr("^", expr, rhs, op_tok.loc)
        return expr

    def parse_bitwise_and(self) -> Expression:
        expr = self.parse_equality()
        while self.match(TokenKind.SYMBOL, "&"):
            op_tok = self.tokens[self.pos - 1]
            rhs = self.parse_equality()
            expr = BinaryExpr("&", expr, rhs, op_tok.loc)
        return expr

    def parse_equality(self) -> Expression:
        expr = self.parse_relational()
        while True:
            tok = self.cur()
            if tok.kind == TokenKind.SYMBOL and tok.value in ("==", "!="):
                self.bump()
                rhs = self.parse_relational()
                expr = BinaryExpr(tok.value, expr, rhs, tok.loc)
                continue
            break
        return expr

    def parse_relational(self) -> Expression:
        expr = self.parse_shift()
        while True:
            tok = self.cur()
            if tok.kind == TokenKind.SYMBOL and tok.value in ("<", "<=", ">", ">="):
                self.bump()
                rhs = self.parse_shift()
                expr = BinaryExpr(tok.value, expr, rhs, tok.loc)
                continue
            break
        return expr

    def parse_shift(self) -> Expression:
        expr = self.parse_additive()
        while True:
            tok = self.cur()
            if tok.kind == TokenKind.SYMBOL and tok.value in ("<<", ">>"):
                self.bump()
                rhs = self.parse_additive()
                expr = BinaryExpr(tok.value, expr, rhs, tok.loc)
                continue
            break
        return expr

    def parse_additive(self) -> Expression:
        expr = self.parse_multiplicative()
        while True:
            tok = self.cur()
            if tok.kind == TokenKind.SYMBOL and tok.value in ("+", "-"):
                self.bump()
                rhs = self.parse_multiplicative()
                expr = BinaryExpr(tok.value, expr, rhs, tok.loc)
                continue
            break
        return expr

    def parse_multiplicative(self) -> Expression:
        expr = self.parse_unary()
        while True:
            tok = self.cur()
            if tok.kind == TokenKind.SYMBOL and tok.value in ("*", "/", "%"):
                self.bump()
                rhs = self.parse_unary()
                expr = BinaryExpr(tok.value, expr, rhs, tok.loc)
                continue
            break
        return expr

    def parse_unary(self) -> Expression:
        tok = self.cur()
        if tok.kind == TokenKind.SYMBOL and tok.value in ("+", "-", "!", "~"):
            self.bump()
            operand = self.parse_unary()
            return UnaryExpr(tok.value, operand, tok.loc)
        return self.parse_primary()

    def parse_primary(self) -> Expression:
        tok = self.cur()
        if tok.kind == TokenKind.INT:
            self.bump()
            return IntLiteral(value=int(tok.value), loc=tok.loc)
        if tok.kind == TokenKind.IDENT:
            if self.peek().kind == TokenKind.SYMBOL and self.peek().value == "(":
                return self.parse_call_expr()
            self.bump()
            if self.match(TokenKind.SYMBOL, "["):
                index = self.parse_expression()
                self.expect(TokenKind.SYMBOL, "]")
                return ArrayAccessExpr(name=tok.value, index=index, loc=tok.loc)
            return VariableExpr(name=tok.value, loc=tok.loc)
        if tok.kind == TokenKind.SYMBOL and tok.value == "(":
            self.bump()
            expr = self.parse_expression()
            self.expect(TokenKind.SYMBOL, ")")
            return expr
        raise ParserError("expected primary expression", tok.loc)
