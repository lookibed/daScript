options gen2
options indenting = 4
options strict_smart_pointers = true

module lr_parse shared public

require lr1/lr1_lalr public

// The deterministic driver over the tables of `lr1/lr1_lalr`: one
// stack, the primary action of a cell, the exact expected set on a
// refusal. A `[bison]` parser's emitted driver reads the same walk.

//! What `lr_parse` found: acceptance, or where it stopped and what it
//! would have taken there.
struct LrParse {
    ok : bool
    pos : int                   //!< the refused token's index; `length(tokens)` at the end of input
    state : int                 //!< the state that refused it
    token : int                 //!< the refused terminal id (`eof` at the end of input)
    expected : array<int>       //!< terminal ids the parser would have taken at `pos`, ascending,
                                //!< from the stack the refused token was read on
    reductions : array<int>     //!< the productions reduced, in order (indexes into `prods`)
    err : string
}

// the action a single stack takes on `term`: the primary action of
// its cell
def private cell_action(t : LalrTables; state, term : int) : int =>
    t.action[state * t.nterms + term]

// reduce `stack` by production `p`; false when the goto is missing
def private reduce_on(t : LalrTables; var stack : array<int>; p : int) : bool {
    stack |> resize(length(stack) - length(t.prods[p].rhs))
    let to = t.goto_nt[stack[length(stack) - 1] * t.nrules + t.prods[p].lhs]
    return false if (to < 0)
    stack |> push(to)
    return true
}

//! The most reductions `lr_parse` runs between two shifts.
let LR_MAX_REDUCES = 1000000

// whether `term` would be shifted or accepted from `stack` after its
// reduce chain
def private lr_takes(action, goto_nt, lhs, len : array<int>; nterms, nrules : int;
                     stack : array<int>; term : int) : bool {
    var inscope probe := stack
    for (_ in range(LR_MAX_REDUCES)) {
        let a = action[probe[length(probe) - 1] * nterms + term]
        return a > 0 if (a >= 0)
        let p = -1 - a
        let depth = length(probe) - len[p]
        let to = goto_nt[probe[depth - 1] * nrules + lhs[p]]
        return false if (to < 0)
        probe |> resize(depth + 1)
        probe[depth] = to
    }
    return false
}

//! The left-hand side and the length of every production of `t`: the
//! per-production columns `lr_expected` and a `[bison]` parser's
//! driver read.
def prod_columns(t : LalrTables) : tuple<lhs : array<int>; len : array<int>> =>
    <- (lhs <- [for (pr in t.prods); pr.lhs], len <- [for (pr in t.prods); length(pr.rhs)])

//! The terminals some reduce chain from `stack` ends in a shift or
//! accept for, ascending: the tables as flat arrays (`action`,
//! `goto_nt`, the left-hand side and length of every production,
//! `nterms`, `nrules`), so `lr_parse` and a `[bison]` parser's
//! emitted globals share one walk.
def lr_expected(action, goto_nt, lhs, len : array<int>; nterms, nrules : int;
                stack : array<int>) : array<int> =>
    <- [for (x in range(nterms)); x;
        where lr_takes(action, goto_nt, lhs, len, nterms, nrules, stack, x)]

//! Before a reduce cuts `stack` down to `depth`: every state under
//! `low` the cut removes goes to `saved`, last removed first, and
//! `low` follows the cut. `low` is `length(stack)` and `saved` empty
//! when a token is read, so `stack[0 .. low)` and `saved` keep the
//! stack it was read on.
def lr_keep_popped(stack : array<int>; var low : int&; var saved : array<int>; depth : int) {
    while (low > depth) {
        low--
        saved |> push(stack[low])
    }
}

//! The state stack as it stood when the current token was read:
//! `stack[0 .. low)`, then the states `lr_keep_popped` saved, in
//! stack order.
def lr_stack_at_read(stack : array<int>; low : int; saved : array<int>) : array<int> {
    var out : array<int>
    out |> reserve(low + length(saved))
    for (i in range(low)) {
        out |> push(stack[i])
    }
    for (k in range(length(saved))) {
        out |> push(saved[length(saved) - 1 - k])
    }
    return <- out
}

//! Run the tables over `tokens` (terminal ids, the end of input
//! implied) with one stack, taking the primary action of a
//! conflicting cell (`action`, never `alt`).
[arch(at="../ARCHITECTURE.md#driver")]
def lr_parse(t : LalrTables; tokens : array<int>) : LrParse {
    var res : LrParse
    if (!empty(t.err)) {
        res.err = t.err
        return <- res
    }
    var stack : array<int>
    stack |> push(0)
    var pos = 0
    var reduces = 0
    var low = 1
    var saved : array<int>
    while (true) {
        let term = pos < length(tokens) ? tokens[pos] : t.eof
        let top = stack[length(stack) - 1]
        let known = pos >= length(tokens) || (term >= 0 && term < t.eof)
        let a = known ? cell_action(t, top, term) : 0
        if (a == ACCEPT) {
            res.ok = true
            return <- res
        } elif (a > 0) {
            stack |> push(a - 1)
            pos++
            reduces = 0
            low = length(stack)
            saved |> clear()
        } elif (a < 0 && reduces < LR_MAX_REDUCES) {
            res.reductions |> push(-1 - a)
            reduces++
            lr_keep_popped(stack, low, saved, length(stack) - length(t.prods[-1 - a].rhs))
            if (!reduce_on(t, stack, -1 - a)) {
                res.err = "no goto after reducing {describe_prod(t, -1 - a)}"
                return <- res
            }
        } else {
            res.pos = pos
            res.state = top
            res.token = term
            var inscope cols <- prod_columns(t)
            var inscope at_read <- lr_stack_at_read(stack, low, saved)
            res.expected <- lr_expected(t.action, t.goto_nt, cols.lhs, cols.len, t.nterms, t.nrules,
                                        at_read)
            let why = a < 0 ? "reduce loop" : "unexpected terminal {term}"
            res.err = "{why} in state {top}"
            return <- res
        }
    }
    return <- res
}
