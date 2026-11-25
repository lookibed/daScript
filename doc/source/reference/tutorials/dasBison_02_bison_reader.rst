.. _tutorial_dasBison_bison_reader:

=======================================
BISON-02 --- The %bison~ Text Form
=======================================

.. index::
    single: Tutorial; Bison
    single: Tutorial; Parser
    single: Tutorial; dasBison
    single: Tutorial; Reader Macro

The calculator of :ref:`tutorial_dasBison_calculator`, written as
yacc-like text instead of ``rule()`` calls.  You will learn:

- The header that names the parser, its result type, the token enum and the lexer
- ``%left`` / ``%right`` / ``%expect`` declarations, ``%prec``, and the rules section
- ``$$`` and ``$1`` .. ``$n`` in the actions, which are daslang code

The Text Form
=============

``%bison~ name : Type, tokens = Enum, lexer = scan`` at module level
declares the parser ``def name(var p : Parser) : Type`` --- the same
function ``[bison]`` generates: the reader writes that ``[bison]``
function and the macro builds it.  Before ``%rules``: the precedence
lines in yacc's order (a later line binds tighter), ``%expect N``, the
shift/reduce conflicts the grammar is meant to have, ``%start NAME`` and
``%type <Type> names``.  After it, yacc's rules:
``name : symbols { action } | ... ;``.  The first rule is the root, and
the text ends at ``%%``:

.. das-doc: skip
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

Actions
=======

In an action ``$n`` is the value of the n-th symbol of the right-hand
side --- a rule's value, or a named token's ``FlexToken`` --- and
``$$ = value`` returns the rule's value.  Quoted characters count in
``n`` but carry no value, so ``$2`` of ``expr '+' expr`` is an error.
``p`` is the parser.  The root's type is the header's; another rule an
action reads by ``$n`` needs ``%type``.  The reader's errors, the
grammar's errors and daslang's errors inside an action all point at the
line of the text.

The generated function is called exactly like the ``[bison]`` one:

.. das-doc: fragment
.. code-block:: das

   var p : Parser
   parser_open(p, "(1 + 2) * 3")
   print("{calc(p)}\n")
   // output: 9

.. seealso::

   Full source: :download:`tutorials/dasBison/02_bison_reader.das <../../../../tutorials/dasBison/02_bison_reader.das>`

   Previous tutorial: :ref:`tutorial_dasBison_calculator`
