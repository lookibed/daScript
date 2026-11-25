# dasBison Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`.

**A diff under `bison/` that adds a `require` of a module other than one under `bison/`, one under
`daslib/`, a builtin module the daslang executable registers itself (such as `strings` or
`math`), dasLR1's `lr1/lr1_lalr`, or - in `bison/bison_parser.das` and `bison/bison_macro.das`
only - dasFlex's `flex/flex` or `flex/flex_macro`, is a defect** - the module is reused by
programs that load nothing else under `modules/` but dasLR1 and dasFlex.

**A diff that makes `lr_parse` take an action from `alt`, or report `expected` other than through
the reduce chains from the stack, is a defect** (`ARCHITECTURE.md#driver`).

**A diff that lets `resolve_precedence` take an action out of a cell without recording it in that
cell's `PrecCell` (`removed`, or `kept` for a default's loser), or resolve a cell by default
without counting it in `PrecReport.by_default`, is a defect** - the report is the only record
of what precedence and the default decided (`ARCHITECTURE.md#precedence`).

**A diff that changes the expected counts of `tests/c11_tests.das` (479 states, 2 conflicts) names
the reason in its description** - they are what dasLR1's core builds for the C11 grammar the
example parses.

**A diff that makes a `[bison]` function, or anything the code it generates calls, build or
resolve LALR tables when the program runs is a defect** - the macro builds them at compile time
and emits them as globals (`ARCHITECTURE.md#compile-time-tables`).

**A diff that lets `[bison]` accept a grammar with a conflict yacc's default resolved without the
compile warning, other than when `expected` equals the shift/reduce count and no reduce/reduce
conflict is left, is a defect** (`ARCHITECTURE.md#compile-time-tables`).

**A diff that lets a `[bison]` grammar name a symbol that is neither a rule nor a token, or give
two names one token kind, without a compile error at the rule's line is a defect**
(`ARCHITECTURE.md#macro`).

**A diff that lets two actions of one rule return different types, or a production pass on a
value of another type than its rule's, compile without an error at the rule's line is a defect** -
the value stacks are typed by each rule's first action (`ARCHITECTURE.md#values`).

**A diff that makes the generated driver pass an action's arguments as calls in the argument list,
rather than as locals popped last symbol first, is a defect** - argument evaluation order is not
defined, and two pops from one stack would swap (`ARCHITECTURE.md#macro-driver`).

**A diff that makes a `[bison]` parse error report a position, a token name or an expected set
other than the refused token's, the grammar's names, and the reduce chains' set, or return without
setting `failed`, is a defect** (`ARCHITECTURE.md#macro-errors`).

**A diff that gives a front end - the `%bison~` reader or a new one - its own table builder,
precedence resolution or driver, rather than handing its grammar to `[bison]`'s back end, is a
defect** - both forms of a grammar must give the same tables, values and errors
(`ARCHITECTURE.md#reader`).

**A diff that makes `bison_reader_source` put a line of its output anywhere but on the line of the
text it came from, or makes the reader's text end anywhere but at the first `%%`, is a defect** -
the output holds the text's lines, the closing `}` on the `%%` line, and diagnostics land on the
wrong line otherwise (`ARCHITECTURE.md#reader`).

**Weakening the censuses in `REVIEW.das` - every `bison/*.das` registered in `.das_module` and every
name registered there on disk, every test file in `tests/` named by a `das_lane_dastest_target` in
`CMakeLists.txt` - is a defect.**
