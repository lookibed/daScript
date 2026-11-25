.. _tutorial_dasFlex_flex_reader:

=======================================
FLEX-02 --- The %flex~ Text Form
=======================================

.. index::
    single: Tutorial; Flex
    single: Tutorial; Lexer
    single: Tutorial; dasFlex
    single: Tutorial; Reader Macro

The JSON lexer of :ref:`tutorial_dasFlex_json_tokens`, written as
flex-like text instead of ``rule()`` calls.  You will learn:

- The header that names the scanner and the token enum
- Start conditions, quoted literals and definitions
- The action vocabulary

The Text Form
=============

``%flex~ name : Enum`` at module level declares the scanner
``def name(var lx : FlexLexer) : bool`` --- the same function ``[flex]``
would generate, through the same table builder.  Before ``%rules``:
``%x`` / ``%s`` declare exclusive and inclusive start conditions, and
``NAME regex`` a definition that ``{NAME}`` expands.  After it, one rule
per line: an optional ``<CONDITION>``, the pattern --- ``"..."`` is
literal text, the rest is ``daslib/regex`` --- and the action, daslang
code in braces.  A rule with no action skips what it matched.  The text
ends at ``%%``:

.. das-doc: skip
.. code-block:: text

   %flex~ json_lexer : JTok
   %x COMMENT
   DIGITS  [0-9]+
   %rules
   [ \t\r\n]+
   \{                                              { emit(LBRACE) }
   \}                                              { emit(RBRACE) }
   \[                                              { emit(LBRACKET) }
   \]                                              { emit(RBRACKET) }
   ":"                                             { emit(COLON) }
   ","                                             { emit(COMMA) }
   "true"                                          { emit(TRUE) }
   "false"                                         { emit(FALSE) }
   "null"                                          { emit(NULL) }
   -?(0|[1-9][0-9]*)(\.{DIGITS})?([eE][+-]?{DIGITS})?  { emit(NUMBER) }
   \"([^"\\]|\\.)*\"                               { emit(STRING) }
   "/*"                                            { begin(COMMENT) }
   <COMMENT>"*/"                                   { begin(INITIAL) }
   <COMMENT>[^*]+
   <COMMENT>\*
   %%

Actions
=======

In an action ``emit(NAME)`` emits a member of the header's enum,
``emit(expr)`` any int kind, ``begin(NAME)`` switches the condition, and
``lx`` is the lexer (``text(lx)``, ``lx.symbols``).  Actions are ordinary
daslang, type-checked like any other code, and an error in one --- or a
bad regex, an unknown condition or token --- is reported at the line the
rule is written on.

The generated function is called exactly like the ``[flex]`` one:

.. das-doc: fragment
.. code-block:: das

   var lx : FlexLexer
   flex_open(lx, src, "demo.json")
   while (json_lexer(lx)) {
       print("{lx.tok.kind} {text(lx)} at {lx.tok.line}:{lx.tok.col}\n")
   }

.. seealso::

   Full source: :download:`tutorials/dasFlex/02_flex_reader.das <../../../../tutorials/dasFlex/02_flex_reader.das>`

   Previous tutorial: :ref:`tutorial_dasFlex_json_tokens`

   Next tutorial: :ref:`tutorial_dasFlex_groups`
