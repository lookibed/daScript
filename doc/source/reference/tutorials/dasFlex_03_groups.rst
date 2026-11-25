.. _tutorial_dasFlex_groups:

=======================================
FLEX-03 --- Capture Groups
=======================================

.. index::
    single: Tutorial; Flex
    single: Tutorial; Lexer
    single: Tutorial; dasFlex
    single: Tutorial; Capture Groups

A config lexer that reads the parts of a token its regex captures.  You
will learn:

- ``group(n)`` and ``group_span(n)`` in a rule body
- A group that takes no part in the match
- The same calls in a ``%flex~`` action

Groups in a Rule Body
=====================

The parentheses of a rule's regex are capture groups.  In the body,
``lx |> group(n)`` is the text of group ``n`` (group 0 is the token) and
``lx |> group_span(n)`` its byte range in the input.  The automaton finds
the token as always; the first group call on a token runs the rule's
regex once over it, and the next calls reuse that match.  Rules that
never call ``group`` pay nothing for groups.

A group that may take no part in the match, such as ``(-)?``, gives ``""``
and the span ``range(0, 0)`` when it does not:

.. code-block:: das

   enum CTok {
       SECTION = 1
       STRING = 2
       NUMBER = 3
   }

   var private settings : table<string; string>
   var private section = ""

   [flex]
   def config_lexer(var lx : FlexLexer) : bool {
       rule("\\[([A-Za-z_]+)\\]") {
           section = lx |> group(1)
           lx |> emit(CTok.SECTION)
       }
       rule("([A-Za-z_][A-Za-z0-9_]*) *= *\"([^\"]*)\"") {
           settings["{section}.{lx |> group(1)}"] = lx |> group(2)
           lx |> emit(CTok.STRING)
       }
       rule("([A-Za-z_][A-Za-z0-9_]*) *= *(-)?([0-9]+)") {
           let sign = empty(lx |> group(2)) ? "" : "minus "
           settings["{section}.{lx |> group(1)}"] = "{sign}{lx |> group(3)} at {lx |> group_span(3)}"
           lx |> emit(CTok.NUMBER)
       }
       rule("#[^\\n]*") {
       }
       rule("[ \\t\\r\\n]+") {
       }
   }

Groups in the Text Form
=======================

In a ``%flex~`` action ``group(n)`` names the lexer implicitly, like
``emit``.  A definition ``{NAME}`` expands as a non-capturing group, so
``n`` counts only the parentheses the rule writes:

.. das-doc: skip
.. code-block:: text

   %flex~ pair_lexer : CTok
   NAME    [A-Za-z_][A-Za-z0-9_]*
   %rules
   {NAME}=([0-9]+)     { print("  {group(0)}: value {group(1)}\n"); emit(NUMBER) }
   [ ]+
   %%

.. seealso::

   Full source: :download:`tutorials/dasFlex/03_groups.das <../../../../tutorials/dasFlex/03_groups.das>`

   Previous tutorial: :ref:`tutorial_dasFlex_flex_reader`
