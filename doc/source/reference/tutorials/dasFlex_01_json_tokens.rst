.. _tutorial_dasFlex_json_tokens:

=======================================
FLEX-01 --- JSON Tokens
=======================================

.. index::
    single: Tutorial; Flex
    single: Tutorial; Lexer
    single: Tutorial; dasFlex
    single: Tutorial; Start Conditions

This tutorial introduces the ``flex`` module --- a lexer generator for
daslang.  Rules are regular expressions in a ``[flex]`` function; the
macro builds one deterministic automaton for all of them when the module
compiles, and the function becomes the scanner.  You will learn:

- Writing a lexer as a ``[flex]`` function of rules
- Emitting a token kind, skipping whitespace, the longest match
- A start condition for a multi-line comment
- Reading the token's text and position, and the error a bad byte produces

Setup
=====

Import the macro module::

   require flex/flex_macro

The token kinds are an enum of your own --- ``emit`` stores ``int(kind)``:

.. code-block:: das

   enum JTok {
       LBRACE = 1
       RBRACE = 2
       LBRACKET = 3
       RBRACKET = 4
       COLON = 5
       COMMA = 6
       STRING = 7
       NUMBER = 8
       TRUE = 9
       FALSE = 10
       NULL = 11
   }

Rules
=====

One ``rule`` per token.  The regex is a string in ``daslib/regex``
syntax; the block is the action and runs with ``lx`` --- the function's
own parameter --- in scope.  A block that does not emit is a skip.  The
longest match wins, and when two rules match the same longest text the
one written first wins, so ``true`` sits above any catch-all word rule.

A start condition declared ``exclusive`` holds rules that alone are
active while the lexer is in it; ``begin`` switches conditions:

.. code-block:: das

   [flex]
   def json_lexer(var lx : FlexLexer) : bool {
       rule("[ \\t\\r\\n]+") {
       }
       rule("\\\{") {
           lx |> emit(JTok.LBRACE)
       }
       rule("\\\}") {
           lx |> emit(JTok.RBRACE)
       }
       rule("\\[") {
           lx |> emit(JTok.LBRACKET)
       }
       rule("\\]") {
           lx |> emit(JTok.RBRACKET)
       }
       rule(":") {
           lx |> emit(JTok.COLON)
       }
       rule(",") {
           lx |> emit(JTok.COMMA)
       }
       rule("true") {
           lx |> emit(JTok.TRUE)
       }
       rule("false") {
           lx |> emit(JTok.FALSE)
       }
       rule("null") {
           lx |> emit(JTok.NULL)
       }
       rule("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?") {
           lx |> emit(JTok.NUMBER)
       }
       rule("\"([^\"\\\\]|\\\\.)*\"") {
           lx |> emit(JTok.STRING)
       }
       rule("/\\*") {
           lx |> begin("COMMENT")
       }
       condition("COMMENT", exclusive) {
           rule("\\*/") {
               lx |> begin("INITIAL")
           }
           rule("[^*]+") {
           }
           rule("\\*") {
           }
       }
   }

Running the Scanner
===================

``flex_open`` points the lexer at a string and names the input for error
messages.  Each call of the lexer function scans up to the next emitted
token and returns ``true``; ``lx.tok`` holds its kind, byte span, line and
column, and ``text(lx)`` builds the token's string only when asked.  The
function returns ``false`` at the end of input --- or on a byte no rule
accepts, with ``lx.failed`` set and the position in ``lx.err``:

.. code-block:: das

   var lx : FlexLexer
   flex_open(lx, "[1, 2.5e3, true]", "demo.json")
   while (json_lexer(lx)) {
       print("{lx.tok.kind} {text(lx)} at {lx.tok.line}:{lx.tok.col}\n")
   }
   print("end: failed={lx.failed}\n")

A byte that matches no rule ends the scan with an error naming the file,
the line, the column and the character, for example
``bad.json:2:5: unexpected '§'``.

.. seealso::

   Full source: :download:`tutorials/dasFlex/01_json_tokens.das <../../../../tutorials/dasFlex/01_json_tokens.das>`

   Next tutorial: :ref:`tutorial_dasFlex_flex_reader`
