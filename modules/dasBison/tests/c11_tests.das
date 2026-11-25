options gen2
options indenting = 4

require dastest/testing_boost public
require lr1/lr1
require bison/lr_parse
require bison/prec
require daslib/strings_boost
require daslib/fio
require daslib/module_path
require _grammar_c11
require ../examples/c11/c11_parser.das

// the C11 grammar with one terminal id per token and no byte layer:
// every byte set it uses is one byte, named by its token
def private c11_int_builder(t : T?; gb : GrammarBuilder) : BisonBuilder {
    var lb : BisonBuilder
    for (name in gb.rule_names) {
        rule_id(lb, name)
    }
    for (gp in gb.prods) {
        var inscope rhs : array<int>
        for (s in gp.rhs) {
            if (s.is_rule) {
                rhs |> push(rule_sym(s.rule))
                continue
            }
            var inscope bs <- [for (b in range(256)); b; where s.bytes[b]]
            t |> equal(length(bs), 1)
            let b = bs[0]
            rhs |> push(term_sym(term_id(lb, b >= 128 ? TOKEN_NAMES[b - 128] : "'{to_char(b)}'")))
        }
        add_production(lb, gp.lhs, rhs)
    }
    return <- lb
}

def private has_line(lines : array<string>; part1, part2 : string) : bool {
    for (l in lines) {
        return true if (find(l, part1) >= 0 && find(l, part2) >= 0)
    }
    return false
}

[test(description = "the C11 grammar with one integer terminal per token builds to 479 states and two conflicts, which resolve_precedence reports as two default shifts and the driver still parses through", timeout = 1200)]
def test_c11_int(t : T?) {
    var gb : GrammarBuilder
    let root = build_c11(gb)
    let lb <- c11_int_builder(t, gb)
    let tb <- build_lalr(lb, root)
    t |> equal(tb.err, "")
    t |> equal(tb.nterms, length(lb.term_names) + 1)
    t |> equal(tb.nstates, 479)
    t |> equal(tb.conflicts, 2)
    let lines <- describe_conflicts(tb)
    t |> success(has_line(lines, "on '(': shift", "reduce type_qualifier ::= ATOMIC"), "_Atomic (")
    let if_reduce = "reduce selection_statement ::= IF '(' expression ')' statement"
    t |> success(has_line(lines, "on ELSE: shift", if_reduce), "dangling else")
    let res <- resolve_precedence(tb, lb)
    t |> equal(res.report.by_default, 2)
    t |> equal(res.report.by_precedence, 0)
    t |> equal(res.report.nonassoc_errors, 0)
    t |> equal(res.report.shift_reduce, 2)
    t |> equal(res.report.reduce_reduce, 0)
    t |> equal(res.tables.conflicts, 2)
    t |> equal(tb.conflicts, 2)
    let text = ("State 38 conflicts: 1 shift/reduce\n" +
        "    '('  shift, and go to state 62\n" +
        "    '('  [reduce using rule 161 (type_qualifier ::= ATOMIC)]\n" +
        "State 443 conflicts: 1 shift/reduce\n" +
        "    ELSE  shift, and go to state 463\n" +
        ("    ELSE  [reduce using rule 254 (selection_statement ::= IF '(' expression ')' "
            + "statement)]\n"))
    t |> equal(format_report(res.report), text)
    let words = ("INT IDENTIFIER '(' ')' '\{' IF '(' IDENTIFIER ')' IF '(' IDENTIFIER ')' ';' ELSE "
        + "';' '\}'")
    let toks <- [for (w in split(words, " ")); lb.term_index?[w] ?? -1]
    let r <- lr_parse(res.tables, toks)
    t |> success(r.ok, r.err)
    let ifs <- [for (p in r.reductions); describe_prod(res.tables, p);
                where starts_with(describe_prod(res.tables, p), "selection_statement ::= IF")]
    t |> equal(ifs, ["selection_statement ::= IF '(' expression ')' statement ELSE statement",
                     "selection_statement ::= IF '(' expression ')' statement"])
    t |> success(
                 !lr_parse(res.tables,
                           [for (w in split("INT ';' ELSE", " ")); lb.term_index?[w] ?? -1]).ok)
}

// the `rule("lhs", "rhs")` calls of the [bison] C11 example as
// `lhs ::= rhs`, in source order, the braces the string literals
// escape read as braces; a call may break its line after the `,`
def private example_rules() : array<string> {
    let src = fread(path_join(get_this_module_dir(), "../examples/c11/c11_parser.das"))
    var out : array<string>
    for (i, call in count(), split(src, "\n    rule(\"")) {
        continue if (i == 0)
        var inscope parts <- split(call, "\"")
        out |> push(replace(replace("{parts[0]} ::= {parts[2]}", "\\\{", "\{"), "\\\}", "\}"))
    }
    return <- out
}

[test(description = "the C11 grammar of these tests and the [bison] C11 example are one grammar: the same productions, as lhs ::= rhs, in the same order", timeout = 1200)]
def test_c11_one_grammar(t : T?) {
    var gb : GrammarBuilder
    build_c11(gb)
    let lb <- c11_int_builder(t, gb)
    var inscope ours <- [for (p in lb.prods); build_string() $(var w) {
            w |> write("{lb.rule_names[p.lhs]} ::=")
            for (s in p.rhs) {
                w |> write(" ")
                w |> write(s < 0 ? lb.rule_names[-1 - s] : lb.term_names[s])
            }
        }]
    var inscope theirs <- example_rules()
    t |> equal(length(theirs), 274)
    t |> equal(ours, theirs)
}

//! the tokens a declaration can start with: what an identifier that
//! is no typedef name meets
let private DECLARATION_START = ("ATOMIC, TYPEDEF, EXTERN, STATIC, THREAD_LOCAL, AUTO, REGISTER, "
    + "VOID, CHAR, SHORT, INT, LONG, FLOAT, DOUBLE, SIGNED, UNSIGNED, BOOL, COMPLEX, IMAGINARY, "
    + "TYPEDEF_NAME, STRUCT, UNION, ENUM, CONST, RESTRICT, VOLATILE, INLINE, NORETURN, ALIGNAS, "
    + "STATIC_ASSERT")

[test(description = "a typedef name lexes as TYPEDEF_NAME from the token after its declarator: the declaration, a parameter and a result use it, and the same name undeclared is refused")]
def test_typedef_after_declaration(t : T?) {
    let r = parse_c11("typedef int T; T x; T twice(T a) \{ return a + a; \}")
    t |> success(r.accepted, r.err)
    t |> equal(r.decls, 3)
    t |> equal(r.typedefs, 1)
    t |> equal(parse_c11("T x;", "t.c").err,
               "t.c:1:1: unexpected IDENTIFIER, expected one of: {DECLARATION_START}")
}

[test(description = "a parameter list inside a typedef's declarator keeps its own specifier flag: the function pointer is a type, its parameter is not, and a declarator after a function type is one again")]
def test_typedef_through_parameters(t : T?) {
    t |> equal(parse_c11("typedef void (*handler)(int sig); handler h; sig x;", "h.c").err,
               ("h.c:1:46: unexpected IDENTIFIER, expected one of: {DECLARATION_START}, end of "
                   + "input"))
    let r = parse_c11("typedef int F(int), G; G g; F *fp;")
    t |> success(r.accepted, r.err)
    t |> equal(r.typedefs, 2)
}

[test(description = "a struct with a member list, a designated initializer and a typedef of the tagged type")]
def test_struct(t : T?) {
    let r = parse_c11("struct point \{ int x, y; \}; typedef struct point point_t; point_t q = \{ "
        + ".x = 1, .y = 2 \};")
    t |> success(r.accepted, r.err)
    t |> equal(r.decls, 3)
    t |> equal(r.typedefs, 1)
}

[test(description = "a function with an if / else if / else chain: the dangling else shifts, expected = 1")]
def test_if_else(t : T?) {
    let r = parse_c11("int sign(int v) \{ if (v < 0) return -1; else if (v > 0) return 1; else "
        + "return 0; \}")
    t |> success(r.accepted, r.err)
    t |> equal(r.decls, 1)
}

[test(description = "a for loop whose first clause is a declaration, beside a block declaration and a compound assignment")]
def test_for_declaration(t : T?) {
    let r = parse_c11("int sum(int n) \{ int s = 0; for (int i = 0; i < n; i++) \{ s += i; \} "
        + "return s; \}")
    t |> success(r.accepted, r.err)
    t |> equal(r.decls, 1)
}

[test(description = "_Atomic ( is the type specifier _Atomic(type-name), as C11 6.7.2.4 reads it; _Atomic without ( is the qualifier")]
def test_atomic(t : T?) {
    let r = parse_c11("_Atomic(int) counter; _Atomic int flag; _Atomic(int) *p;")
    t |> success(r.accepted, r.err)
    t |> equal(r.decls, 3)
}

[test(description = "the token stream drops GNU __attribute__ and __asm__ with their arguments and __extension__, and joins adjacent string literals into one token")]
def test_gnu_filter(t : T?) {
    let src = ("extern int f(int) __attribute__((nothrow)) __asm__(\"f\" \"g\"); __extension__ "
        + "typedef long long ll; ll v; char *s = \"a\" \"b\" \"c\";")
    let r = parse_c11(src)
    t |> success(r.accepted, r.err)
    t |> equal(r.decls, 4)
    t |> equal(c11_token_count(src), 21)
}

//! what a constant in an expression can meet: a postfix, a binary or
//! an assignment operator, `?`, `,`, `;`
let private AFTER_CONSTANT = ("'(', ',', '[', '.', PTR_OP, INC_OP, DEC_OP, '&', '*', '+', '-', "
    + "'/', '%', "
    + "LEFT_OP, RIGHT_OP, '<', '>', LE_OP, GE_OP, EQ_OP, NE_OP, '^', '|', AND_OP, OR_OP, '?', '=', "
    + "MUL_ASSIGN, DIV_ASSIGN, MOD_ASSIGN, ADD_ASSIGN, SUB_ASSIGN, LEFT_ASSIGN, RIGHT_ASSIGN, "
    + "AND_ASSIGN, XOR_ASSIGN, OR_ASSIGN, ';'")

[test(description = "a missing ; refuses the } at its line and column, naming every token the constant before it could meet, not only the ones left after the reduces the } ran")]
def test_malformed(t : T?) {
    let r = parse_c11("int f(void)\n\{\n    return 1\n\}\n", "bad.c")
    t |> success(!r.accepted)
    t |> equal(r.err, "bad.c:4:1: unexpected '\}', expected one of: {AFTER_CONSTANT}")
}

[test(description = "the preprocessed qsort comparator in tests/data parses from disk, found beside this test file")]
def test_qsort_file(t : T?) {
    let path = path_join(get_this_module_dir(), "data/qsort_cmp.i")
    let src = fread(path)
    t |> success(!empty(src), "{path} reads empty")
    let r = parse_c11(src, "qsort_cmp.i")
    t |> success(r.accepted, r.err)
    t |> equal(r.typedefs, 1)
    t |> equal(c11_token_count(src), 284)
}
