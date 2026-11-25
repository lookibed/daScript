.. _tutorial_dasBison_calculator:

=======================================
BISON-01 --- A Calculator
=======================================

.. index::
    single: Tutorial; Bison
    single: Tutorial; Parser
    single: Tutorial; dasBison
    single: Tutorial; LALR

This tutorial introduces the ``bison`` module --- a parser generator for
daslang.  A grammar is written as rules in a ``[bison]`` function; when
the module compiles, the macro builds its LALR(1) tables, stores them as
private globals, and turns the function into a typed parser over the
tokens of a ``[flex]`` lexer.  You will learn:

- A ``[flex]`` lexer whose token kinds are an enum and the bytes of punctuation
- A ``[bison]`` function: rules as right-hand-side strings, an action per rule, the root
- Precedence lines, and ``%prec`` for a unary minus
- Typed values: a rule's type is what its actions return
- The error a refused token produces, with the expected set

Setup
=====

Import the two macro modules::

   require flex/flex_macro
   require bison/bison_macro

The named tokens are an enum of your own.  A punctuator needs no member:
the lexer emits its byte, and the grammar writes it quoted (``'+'``).
The enum starts at 256 so its kinds never collide with those bytes:

.. code-block:: das

   enum CTok {
       NUM = 256
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

The Grammar
===========

``tokens`` names the enum whose members the rules may use, ``lexer`` the
``[flex]`` function the parser pulls tokens from.  Each rule is
``rule("lhs", "rhs")``: the right-hand side is text --- rule names, enum
members, quoted characters, ``""`` for an empty production, and a
trailing ``%prec NAME``.  The action block takes the values of the
symbols that carry one, in order: rules, and named tokens as their
``FlexToken``; quoted characters carry none.  The action's result is the
rule's value, so here every ``expr`` is a ``float`` and the function
returns one.

``prec_left`` / ``prec_right`` / ``prec_nonassoc`` are yacc's precedence
lines: each binds tighter than the one before it.  ``UMINUS`` is no token
the lexer emits --- it only names a level for ``%prec``.  ``root`` names
the start rule (the first rule's left-hand side when absent):

.. code-block:: das

   [bison(tokens = CTok, lexer = calc_lex)]
   def calc(var p : Parser) : float {
       prec_left("+", "-")
       prec_left("*", "/")
       prec_right("UMINUS")
       rule("expr", "expr '+' expr") <| $(a, b : float) => a + b
       rule("expr", "expr '-' expr") <| $(a, b : float) => a - b
       rule("expr", "expr '*' expr") <| $(a, b : float) => a * b
       rule("expr", "expr '/' expr") <| $(a, b : float) => a / b
       rule("expr", "'-' expr %prec UMINUS") <| $(e : float) => -e
       rule("expr", "'(' expr ')'") <| $(e : float) => e
       rule("expr", "NUM") <| $(t : FlexToken) => to_float(text(p.lexer, t))
       root("expr")
   }

``p`` is the function's own parameter: the ``NUM`` action reads the
token's text from the lexer's input.  A conflict that precedence leaves
to yacc's default is a compile warning in ``bison -v`` words, unless
``[bison(expected = N)]`` names the shift/reduce count.

Parsing
=======

``parser_open`` points the parser's lexer at a string; the function
parses it and returns the root's value:

.. code-block:: das

   for (src in ["1 + 2 * 3", "(1 + 2) * 3", "2 - 3 - 4", "-2 * -(3 + 1)"]) {
       var p : Parser
       parser_open(p, src)
       print("{src} = {calc(p)}\n")
   }
   // output:
   // 1 + 2 * 3 = 7
   // (1 + 2) * 3 = 9
   // 2 - 3 - 4 = -5
   // -2 * -(3 + 1) = 8

A token the tables refuse stops the parse: ``p.failed`` is set,
``p.err`` says where, what came and what the parser would have taken
there, and the function returns the default value:

.. code-block:: das

   var bad : Parser
   parser_open(bad, "1 +\n  * 2", "input.txt")
   let v = calc(bad)
   print("{v} {bad.err}\n")
   // output: 0 input.txt:2:3: unexpected '*', expected one of: '-', '(', NUM

.. seealso::

   Full source: :download:`tutorials/dasBison/01_calculator.das <../../../../tutorials/dasBison/01_calculator.das>`

   Next tutorial: :ref:`tutorial_dasBison_bison_reader`
