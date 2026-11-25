=====================================
The *dasBison* parser generator
=====================================

**dasBison** is an LALR(1) parser generator for daslang: a ``[bison]``
function holds the grammar as rules, the tables are built by dasLR1's core
when the module compiles, and the function becomes a typed parser over the
tokens of a dasFlex lexer.

Example
~~~~~~~

.. code-block:: das

    require flex/flex_macro
    require bison/bison_macro

    enum CTok {
        NUM = 256           // punctuators need no member: the lexer emits their byte
    }

    [flex]
    def calc_lex(var lx : FlexLexer) : bool {
        rule("[0-9]+(\\.[0-9]+)?") {
            lx |> emit(CTok.NUM)
        }
        rule("[\\-+*/()]") {
            lx |> emit(first_character(text(lx)))
        }
        rule("[ \\t\\r\\n]+") {
        }
    }

    [bison(tokens = CTok, lexer = calc_lex)]
    def calc(var p : Parser) : float {
        prec_left("+", "-")             // yacc order: a later line binds tighter
        prec_left("*", "/")
        rule("expr", "expr '+' expr") <| $(a, b : float) => a + b
        rule("expr", "expr '-' expr") <| $(a, b : float) => a - b
        rule("expr", "expr '*' expr") <| $(a, b : float) => a * b
        rule("expr", "expr '/' expr") <| $(a, b : float) => a / b
        rule("expr", "'(' expr ')'") <| $(e : float) => e
        rule("expr", "NUM") <| $(t : FlexToken) => to_float(text(p.lexer, t))
        root("expr")
    }

    def main() {
        var p : Parser
        parser_open(p, "(1 + 2) * 3", "input.txt")
        let v = calc(p)                 // 9
        if (p.failed) {
            print("{p.err}\n")          // input.txt:1:4: unexpected ..., expected one of: ...
        }
    }

- A right-hand side is text: a rule's name, a member of the ``tokens`` enum
  (its value is the kind), a quoted character (the token whose kind is that
  byte), ``""`` for epsilon, a trailing ``%prec NAME``. ``prec_left`` /
  ``prec_right`` / ``prec_nonassoc`` take token names or characters;
  ``root`` defaults to the first rule.
- The action's arguments are the values of the symbols that carry one, in
  order - rules that yield, and named tokens as their ``FlexToken`` - or none
  at all. A rule's type is what its actions return; a rule with no action
  passes its one value on; a rule whose actions return nothing yields no
  value. The root's value is the function's result.
- A conflict precedence leaves to yacc's default is a compile warning in
  ``bison -v`` words, unless ``[bison(expected = N)]`` (yacc's ``%expect``)
  names the shift/reduce count.
- A refused token sets ``p.failed``, ``p.line``, ``p.col`` and ``p.err``
  (``file:line:col: unexpected TOKEN, expected one of: a, b, c``) and the
  function returns the default value.

The yacc-like text form
~~~~~~~~~~~~~~~~~~~~~~~

The calculator with a unary minus, at module level - ``%bison~`` writes a
``[bison]`` function like the one above:

.. code-block:: text

    %bison~ calc : float, tokens = CTok, lexer = calc_lex
    %left '+' '-'
    %left '*' '/'
    %right UMINUS
    %expect 0
    %rules
    expr : expr '+' expr          { $$ = $1 + $3 }
         | expr '-' expr          { $$ = $1 - $3 }
         | expr '*' expr          { $$ = $1 * $3 }
         | expr '/' expr          { $$ = $1 / $3 }
         | '-' expr %prec UMINUS  { $$ = -$2 }
         | '(' expr ')'           { $$ = $2 }
         | NUM                    { $$ = to_float(text(p.lexer, $1)) }
         ;
    %%

- The header names the parser, its result type, the token enum and the
  lexer. Before ``%rules``: ``%left`` / ``%right`` / ``%nonassoc``,
  ``%expect N``, ``%start NAME`` (else the first rule is the root),
  ``%type <Type> names``. The text ends at ``%%``.
- ``$n`` is the n-th symbol of the right-hand side, quoted characters
  counted; reading one that carries no value is a compile error.
  ``$$ = value`` returns the rule's value. The root's type is the header's;
  another rule an action reads by ``$n`` needs ``%type``.
- The reader's errors, ``[bison]``'s errors at a rule and daslang's inside
  an action point at the line of the text.

Tables without the macro
~~~~~~~~~~~~~~~~~~~~~~~~

``bison/prec`` resolves the conflicts of tables dasLR1's core built, as yacc
does, into a copy, and ``bison/lr_parse`` runs them:

.. code-block:: das

    require bison/prec
    require bison/lr_parse

    def main() {
        var gb : BisonBuilder           // the core's LalrBuilder plus the precedence lines
        let plus = term_id(gb, "+")
        let star = term_id(gb, "*")
        let num = term_id(gb, "num")
        let e = rule_id(gb, "E")
        add_production(gb, e, [rule_sym(e), term_sym(plus), rule_sym(e)])
        add_production(gb, e, [rule_sym(e), term_sym(star), rule_sym(e)])
        add_production(gb, e, [term_sym(num)])
        prec_left(gb, [plus])           // %left '+'
        prec_left(gb, [star])           // %left '*' - a later line binds tighter
        let tables <- build_lalr(gb, e) // 4 shift/reduce conflicts, all kept
        let res <- resolve_precedence(tables, gb)
        print("{res.report.by_precedence} resolved, {res.tables.conflicts} left\n")
        print(format_report(res.report)) // the unresolved cells, as bison -v lists them
        let r <- lr_parse(res.tables, [num, plus, num, star, num])
        if (!r.ok) {
            print("{r.err} at token {r.pos}, expected {r.expected}\n")
        }
    }

- ``resolve_precedence(tables, gb)`` returns ``PrecResult``: ``tables``, a
  resolved copy (the input is not changed), and ``report``:
  ``by_precedence``, ``by_default``, ``nonassoc_errors``, bison's
  ``shift_reduce`` / ``reduce_reduce`` counts, and one ``PrecCell`` per
  conflicting cell.
- ``lr_parse(tables, tokens)`` runs one stack (the first action of a
  conflicting cell) and returns the reductions, or the position, state,
  refused terminal and the exact expected set.

Tutorials: ``tutorials/dasBison/`` - the calculator as ``[bison]`` rules and
in ``%bison~`` form. A C11 parser over dasFlex's C lexer, with a driver that
parses preprocessed files: ``modules/dasBison/examples/c11/``.
