options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require lr1/lr1
require math
require strings
require daslib/strings_boost

// The LALR(1) engine on grammars assembled by hand: acceptance, the viable-prefix refusal, the next-byte
// set, probing whole strings, epsilon and left-recursive rules, and the verdicts on a conflicting and an
// ill-formed grammar.

def private range_set(lo, hi : int) : ByteSet {
    var bs : ByteSet
    for (b in range(lo, hi + 1)) {
        bs[b] = true
    }
    return bs
}

def private digits() : ByteSet => range_set('0', '9')

def private seq(var out : array<GrammarSym>; items : array<GrammarSym>) {
    out |> push_from(items)
}

// expr ::= expr "+" term | term ; term ::= digit+ (left recursive, with an epsilon-free plus)
def private arith() : Grammar {
    var gb : GrammarBuilder
    let expr = rule_id(gb, "expr")
    let term = rule_id(gb, "term")
    var p1 : array<GrammarSym>
    seq(p1, [sym_rule(expr), sym_byte('+'), sym_rule(term)])
    add_production(gb, expr, p1)
    var p2 : array<GrammarSym>
    seq(p2, [sym_rule(term)])
    add_production(gb, expr, p2)
    var p3 : array<GrammarSym>
    seq(p3, [sym_bytes(digits())])
    add_production(gb, term, p3)
    var p4 : array<GrammarSym>
    seq(p4, [sym_rule(term), sym_bytes(digits())])
    add_production(gb, term, p4)
    return <- build_grammar(gb, expr)
}

// s ::= a s | b s | '!' ; a ::= 'x' ; b ::= 'x'  - right recursion
// keeps every reading of every x on the stack, so k x's are 2^k live
// stacks over shared frames
def private forking_grammar() : Grammar {
    var gb : GrammarBuilder
    let s = rule_id(gb, "s")
    let a = rule_id(gb, "a")
    let b = rule_id(gb, "b")
    add_production(gb, s, [sym_rule(a), sym_rule(s)])
    add_production(gb, s, [sym_rule(b), sym_rule(s)])
    add_production(gb, s, [sym_byte('!')])
    add_production(gb, a, [sym_byte('x')])
    add_production(gb, b, [sym_byte('x')])
    return <- build_grammar(gb, s)
}

//! Step `b` until it is refused or `cap` were fed; the count fed.
def private feed_until_refused(g : Grammar; var st : LrStack; b : uint8; cap : int) : int {
    var fed = 0
    while (fed < cap && lr_step(g, st, b)) {
        fed++
    }
    return fed
}

[test(description = "A left-recursive sum grammar accepts its sentences and refuses the rest, refuses a second operator at once by the viable prefix, reports the next-byte set, and leaves the state unmoved after a refused probe.")]
def test_lr1_arith(t : T?) {
    t |> run("a left-recursive sum of numbers: sentences, refusals, the viable prefix") @(t : T?) {
        var g <- arith()
        t |> equal(g.err, "", "the grammar builds")
        t |> success(lr_matches(g, "42"), "one number")
        t |> success(lr_matches(g, "1+2+3+4+5"), "a sum")
        t |> success(lr_matches(g, "123+456"), "wider numbers")
        t |> success(!lr_matches(g, ""), "nothing is not a sentence")
        t |> success(!lr_matches(g, "+"), "a bare operator")
        t |> success(!lr_matches(g, "1+"), "a trailing operator is not complete")
        t |> success(!lr_matches(g, "12a45"), "a letter inside")
        var st <- lr_start(g)
        t |> success(lr_step_bytes(g, st, "12+"), "a valid prefix advances")
        t |> success(!lr_at_end(g, st), "... and is not complete after the operator")
        t |> success(!lr_step(g, st, uint8('+')), "the second operator is refused at once (viable prefix)")
        t |> success(lr_step(g, st, uint8('7')), "a digit continues")
        t |> success(lr_at_end(g, st), "... and completes the sentence")
        let nb = lr_next_bytes(g, st)
        t |> success(nb['+'] && nb['0'] && nb['9'] && !nb['a'] && !nb[' '], "after a number: an operator or another digit")
        t |> success(!lr_step_bytes(g, st, "+x"), "a refused probe leaves the stack where it was")
        t |> success(lr_at_end(g, st), "... still complete")
    }
}

[test(description = "A nested-list grammar with an epsilon production accepts the empty list and deep nesting, refuses a trailing comma or an unclosed list, and offers only a comma or the close after an item.")]
def test_lr1_epsilon_and_nesting(t : T?) {
    t |> run("optional pieces and nesting: list ::= '[' items? ']' ; items ::= item | items ',' item ; item ::= 'a' | list") @(t : T?) {
        var gb : GrammarBuilder
        let list = rule_id(gb, "list")
        let opt = rule_id(gb, "opt")
        let items = rule_id(gb, "items")
        let item = rule_id(gb, "item")
        var p : array<GrammarSym>
        seq(p, [sym_byte('['), sym_rule(opt), sym_byte(']')])
        add_production(gb, list, p)
        var e : array<GrammarSym>
        add_production(gb, opt, e)
        var o : array<GrammarSym>
        seq(o, [sym_rule(items)])
        add_production(gb, opt, o)
        var i1 : array<GrammarSym>
        seq(i1, [sym_rule(item)])
        add_production(gb, items, i1)
        var i2 : array<GrammarSym>
        seq(i2, [sym_rule(items), sym_byte(','), sym_rule(item)])
        add_production(gb, items, i2)
        var a : array<GrammarSym>
        seq(a, [sym_byte('a')])
        add_production(gb, item, a)
        var nested : array<GrammarSym>
        seq(nested, [sym_rule(list)])
        add_production(gb, item, nested)
        var g <- build_grammar(gb, list)
        t |> equal(g.err, "", "the grammar builds")
        t |> success(lr_matches(g, "[]"), "the empty list (an epsilon production)")
        t |> success(lr_matches(g, "[a]"), "one item")
        t |> success(lr_matches(g, "[a,a,[a,[]],a]"), "nesting")
        t |> success(!lr_matches(g, "[a,]"), "a trailing comma")
        t |> success(!lr_matches(g, "[[a]"), "an unclosed list")
        var st <- lr_start(g)
        t |> success(lr_step_bytes(g, st, "[a,[a"), "deep inside")
        let nb = lr_next_bytes(g, st)
        t |> success(nb[','] && nb[']'] && !nb['['] && !nb['a'], "after an item: a comma or the close")
    }
}

[test(description = "A reduce/reduce-ambiguous grammar builds with its conflict counted and named and still accepts exactly its language, a reachable unproductive rule fails the build by name, an unreachable one is ignored, and lr_accepts answers without moving the state.")]
def test_lr1_verdicts(t : T?) {
    t |> run("an ambiguous grammar reports its conflict and still accepts its language; an ill-formed one accepts nothing") @(t : T?) {
        // s ::= a | b ; a ::= 'x' ; b ::= 'x'  - a reduce/reduce conflict
        var gb : GrammarBuilder
        let s = rule_id(gb, "s")
        let a = rule_id(gb, "a")
        let b = rule_id(gb, "b")
        var p1 : array<GrammarSym>
        seq(p1, [sym_rule(a)])
        add_production(gb, s, p1)
        var p2 : array<GrammarSym>
        seq(p2, [sym_rule(b)])
        add_production(gb, s, p2)
        var x1 : array<GrammarSym>
        seq(x1, [sym_byte('x')])
        add_production(gb, a, x1)
        var x2 : array<GrammarSym>
        seq(x2, [sym_byte('x')])
        add_production(gb, b, x2)
        var g <- build_grammar(gb, s)
        t |> equal(g.err, "", "an ambiguous grammar still builds")
        t |> success(g.conflicts > 0 && find(g.first_conflict, "reduce/reduce") >= 0, "the conflict is counted and named: {g.first_conflict}")
        t |> success(lr_matches(g, "x") && !lr_matches(g, "xx"), "... and the acceptor forks through it: exactly the language")

        // loop ::= loop 'x' - derives no terminal string
        var gb2 : GrammarBuilder
        let loop = rule_id(gb2, "loop")
        var l : array<GrammarSym>
        seq(l, [sym_rule(loop), sym_byte('x')])
        add_production(gb2, loop, l)
        let g2 <- build_grammar(gb2, loop)
        t |> success(find(g2.err, "derives no terminal string") >= 0, "the unproductive rule is named: {g2.err}")

        // root ::= 'x' ; orphan ::= orphan 'y' - an unproductive rule the root never reaches is dead text, no defect
        var gb3 : GrammarBuilder
        let root = rule_id(gb3, "root")
        let orphan = rule_id(gb3, "orphan")
        var rx : array<GrammarSym>
        seq(rx, [sym_byte('x')])
        add_production(gb3, root, rx)
        var oy : array<GrammarSym>
        seq(oy, [sym_rule(orphan), sym_byte('y')])
        add_production(gb3, orphan, oy)
        let g3 <- build_grammar(gb3, root)
        t |> equal(g3.err, "", "an unreachable rule, productive or not, is ignored")
        t |> success(lr_matches(g3, "x") && !lr_matches(g3, "y"), "... and the language is the root's")
        // lr_accepts answers without moving the state
        var st <- lr_start(g3)
        t |> success(lr_accepts(g3, st, uint8('x')) && !lr_accepts(g3, st, uint8('y')), "lr_accepts: the next byte's verdict")
        t |> success(!lr_at_end(g3, st), "... with the state where it was")
        t |> success(lr_step(g3, st, uint8('x')) && lr_at_end(g3, st) && !lr_accepts(g3, st, uint8('x')), "after the sentence: at end, nothing more admitted")
    }
}

[test(description = "When the next byte would push the stack set past LR_MAX_STACKS the acceptor refuses it and keeps the set where it was, never dropping a live stack, while a sentence inside the cap completes - whether the set doubles per byte or grows by one.")]
def test_lr1_stack_cap(t : T?) {
    t |> run("a grammar whose alternatives multiply past LR_MAX_STACKS has its byte refused, never a stack dropped") @(t : T?) {
        // the set passes the cap on the ninth x
        let g <- forking_grammar()
        t |> equal(g.err, "", "the grammar builds")
        t |> success(g.conflicts > 0, "... with conflicts")
        var st <- lr_start(g)
        let fed = feed_until_refused(g, st, uint8('x'), 64)
        t |> success(fed > 0 && fed < 64, "the acceptor fed {fed} bytes before the set would pass the cap")
        t |> success(length(st.stacks) <= LR_MAX_STACKS, "the set never holds more than the cap ({length(st.stacks)})")
        t |> success(!lr_step(g, st, uint8('x')), "the refused byte stays refused")
        t |> success(!lr_at_end(g, st), "... and the set stands where it was, mid-sentence")
        var short <- lr_start(g)
        t |> success(lr_step_bytes(g, short, "xxxxx!") && lr_at_end(g, short), "a sentence inside the cap completes")
    }
    t |> run("a set that grows one stack a byte never passes the cap") @(t : T?) {
        // s ::= a 'e' ; a ::= 'x' a | b ; b ::= b 'x' | <empty>
        // after k x's, every split of them between the right-recursive
        // a and the left-recursive b is a stack: k + 1 stacks, one more
        // per byte
        var gb : GrammarBuilder
        let s = rule_id(gb, "s")
        let a = rule_id(gb, "a")
        let b = rule_id(gb, "b")
        add_production(gb, s, [sym_rule(a), sym_byte('e')])
        add_production(gb, a, [sym_byte('x'), sym_rule(a)])
        add_production(gb, a, [sym_rule(b)])
        add_production(gb, b, [sym_rule(b), sym_byte('x')])
        add_production(gb, b, [])
        let g <- build_grammar(gb, s)
        t |> equal(g.err, "", "the grammar builds")
        var st <- lr_start(g)
        var fed = 0
        var most = length(st.stacks)
        while (fed < 600 && lr_step(g, st, uint8('x'))) {
            fed++
            most = max(most, length(st.stacks))
        }
        t |> success(fed > 0 && fed < 600, "the acceptor fed {fed} bytes, then refused one")
        t |> success(most <= LR_MAX_STACKS, "the set never held more than the cap ({most})")
    }
}

[test(description = "4096 bytes of a right-recursive rule keep one stack whose every step pushes one frame over the previous top - no stack is copied, so a byte costs the same at depth 4096 as at depth 1 - and the whole string matches.")]
def test_lr1_deep_right_recursion(t : T?) {
    // root ::= 'a' root | 'a'
    var gb : GrammarBuilder
    let root = rule_id(gb, "root")
    add_production(gb, root, [sym_byte('a'), sym_rule(root)])
    add_production(gb, root, [sym_byte('a')])
    let g <- build_grammar(gb, root)
    t |> equal(g.err, "")
    var st <- lr_start(g)
    var pushed_once = true
    for (_ in range(4096)) {
        let prev = st.stacks[0]
        pushed_once = (pushed_once && lr_step(g, st, uint8('a')) && length(st.stacks) == 1
            && st.stacks[0].below == prev && st.stacks[0].depth == prev.depth + 1)
    }
    t |> success(pushed_once, "each byte pushed one frame on the previous top")
    t |> equal(st.stacks[0].depth, 4097, "the stack is 4096 frames over the start")
    t |> success(lr_at_end(g, st), "... and the sentence is complete")
    t |> success(lr_matches(g, repeat("a", 4096)), "lr_matches agrees")
}

// s ::= u 'y' ; u ::= a | c ; a ::= 'x' ; c ::= d ; d ::= 'x'
def private check_chains_of_two_lengths(t : T?) {
    var gb : GrammarBuilder
    let s = rule_id(gb, "s")
    let u = rule_id(gb, "u")
    let a = rule_id(gb, "a")
    let c = rule_id(gb, "c")
    let d = rule_id(gb, "d")
    add_production(gb, s, [sym_rule(u), sym_byte('y')])
    add_production(gb, u, [sym_rule(a)])
    add_production(gb, u, [sym_rule(c)])
    add_production(gb, a, [sym_byte('x')])
    add_production(gb, c, [sym_rule(d)])
    add_production(gb, d, [sym_byte('x')])
    let g <- build_grammar(gb, s)
    t |> success(empty(g.err) && g.conflicts > 0, "it builds, with a reduce/reduce cell")
    var st <- lr_start(g)
    t |> success(lr_step_bytes(g, st, "xy"), "x reduces to u in one step and in two")
    t |> equal(length(st.stacks), 1, "... and the two land as one stack")
    t |> equal(st.stacks[0].depth, 3, "... 'y' over u over the start, whichever chain made u")
    t |> success(lr_at_end(g, st), "... which completes the sentence")
}

// s ::= l p t | l q t ; t ::= n 'e' ; p ::= ; q ::=
// l ::= 'x' | 'x' 'x' ; n ::= 'x' | 'x' 'x'
def private check_chain_past_its_head(t : T?) {
    var gb : GrammarBuilder
    let s = rule_id(gb, "s")
    let l = rule_id(gb, "l")
    let p = rule_id(gb, "p")
    let q = rule_id(gb, "q")
    let tt = rule_id(gb, "t")
    let n = rule_id(gb, "n")
    add_production(gb, s, [sym_rule(l), sym_rule(p), sym_rule(tt)])
    add_production(gb, s, [sym_rule(l), sym_rule(q), sym_rule(tt)])
    add_production(gb, tt, [sym_rule(n), sym_byte('e')])
    add_production(gb, l, [sym_byte('x')])
    add_production(gb, l, [sym_byte('x'), sym_byte('x')])
    add_production(gb, p, [])
    add_production(gb, q, [])
    add_production(gb, n, [sym_byte('x')])
    add_production(gb, n, [sym_byte('x'), sym_byte('x')])
    let g <- build_grammar(gb, s)
    t |> equal(g.err, "", "the grammar builds")
    var st <- lr_start(g)
    t |> success(lr_step_bytes(g, st, "xxx"), "'xxx' splits at l, then at p or q")
    t |> equal(length(st.stacks), 4, "... four stacks")
    t |> success(lr_step(g, st, uint8('e')), "'e' reduces each split's n and t")
    t |> equal(length(st.stacks), 2, "... the p readings one stack, the q readings another")
    t |> success(lr_at_end(g, st), "... which complete the sentence")
}

// s ::= a 'e' ; a ::= 'x' a | u ; u ::= p | q ; p ::= 'z' ; q ::= 'z'
// on 'e' one reading walks u, then a down all 16384 x's - more frames
// than any other step in this file, so the slots grow - and only then
// does the other reading reach u
def private check_merge_after_slots_grow(t : T?) {
    var gb : GrammarBuilder
    let s = rule_id(gb, "s")
    let a = rule_id(gb, "a")
    let u = rule_id(gb, "u")
    let p = rule_id(gb, "p")
    let q = rule_id(gb, "q")
    add_production(gb, s, [sym_rule(a), sym_byte('e')])
    add_production(gb, a, [sym_byte('x'), sym_rule(a)])
    add_production(gb, a, [sym_rule(u)])
    add_production(gb, u, [sym_rule(p)])
    add_production(gb, u, [sym_rule(q)])
    add_production(gb, p, [sym_byte('z')])
    add_production(gb, q, [sym_byte('z')])
    let g <- build_grammar(gb, s)
    t |> success(empty(g.err) && g.conflicts > 0, "it builds, with a reduce/reduce cell")
    var st <- lr_start(g)
    t |> success(lr_step_bytes(g, st, repeat("x", 16384) + "z"), "16384 x's, then z")
    t |> success(lr_step(g, st, uint8('e')), "'e' reduces z as p and as q, each down to a")
    t |> equal(length(st.stacks), 1, "... and the two readings land as one stack")
    t |> success(lr_at_end(g, st), "... which completes the sentence")
}

[test(description = "Two readings that end in the same states are one stack - when they share every frame below their tops, when their frames differ two levels down, when reduce chains of different lengths reach one goto, when the match sits past the head of its slot's chain, and when the slots grow between the two - while two stacks that share only their depth and top state stay two, so neither reading's continuation is lost.")]
def test_lr1_stack_dedup(t : T?) {
    // s ::= u 'y' ; u ::= a | b ; a ::= 'x' ; b ::= 'x'
    t |> run("two reductions to one rule over a shared frame") @(t : T?) {
        var gb : GrammarBuilder
        let s = rule_id(gb, "s")
        let u = rule_id(gb, "u")
        let a = rule_id(gb, "a")
        let b = rule_id(gb, "b")
        add_production(gb, s, [sym_rule(u), sym_byte('y')])
        add_production(gb, u, [sym_rule(a)])
        add_production(gb, u, [sym_rule(b)])
        add_production(gb, a, [sym_byte('x')])
        add_production(gb, b, [sym_byte('x')])
        let g <- build_grammar(gb, s)
        t |> success(empty(g.err) && g.conflicts > 0, "it builds, with a reduce/reduce cell")
        var st <- lr_start(g)
        t |> success(lr_step_bytes(g, st, "xy"), "the readings fork on 'y' and rejoin at u")
        t |> equal(length(st.stacks), 1, "... as one stack")
        t |> success(lr_at_end(g, st), "... which completes the sentence")
    }
    // s ::= l n 'e' ; l ::= 'x' | 'x' 'x' ; n ::= 'x' | 'x' 'x'
    t |> run("the same states over different frames") @(t : T?) {
        var gb : GrammarBuilder
        let s = rule_id(gb, "s")
        let l = rule_id(gb, "l")
        let n = rule_id(gb, "n")
        add_production(gb, s, [sym_rule(l), sym_rule(n), sym_byte('e')])
        add_production(gb, l, [sym_byte('x')])
        add_production(gb, l, [sym_byte('x'), sym_byte('x')])
        add_production(gb, n, [sym_byte('x')])
        add_production(gb, n, [sym_byte('x'), sym_byte('x')])
        let g <- build_grammar(gb, s)
        t |> equal(g.err, "", "the grammar builds")
        var st <- lr_start(g)
        t |> success(lr_step_bytes(g, st, "xxx"), "'xxx' splits two ways: x|xx and xx|x")
        t |> equal(length(st.stacks), 2, "... two stacks, l reduced a byte apart")
        let tops := st.stacks
        let nb = lr_next_bytes(g, st)
        t |> success(nb['e'] && nb['x'] && !nb['y'], "the next bytes: the close, or one more x")
        t |> equal(tops, st.stacks, "... read without moving the set")
        t |> success(lr_step(g, st, uint8('e')), "'e' reduces both to l n, two frames apart")
        t |> equal(length(st.stacks), 1, "... and the two are one stack")
        t |> success(lr_at_end(g, st), "... which completes the sentence")
    }
    // s ::= a c 'e' | b c 'f' ; a ::= 'x' ; b ::= 'x' ; c ::= 'c'
    t |> run("the same depth and top state, different frames below") @(t : T?) {
        var gb : GrammarBuilder
        let s = rule_id(gb, "s")
        let a = rule_id(gb, "a")
        let b = rule_id(gb, "b")
        let c = rule_id(gb, "c")
        add_production(gb, s, [sym_rule(a), sym_rule(c), sym_byte('e')])
        add_production(gb, s, [sym_rule(b), sym_rule(c), sym_byte('f')])
        add_production(gb, a, [sym_byte('x')])
        add_production(gb, b, [sym_byte('x')])
        add_production(gb, c, [sym_byte('c')])
        let g <- build_grammar(gb, s)
        t |> equal(g.err, "", "the grammar builds")
        var st <- lr_start(g)
        t |> success(lr_step_bytes(g, st, "xc"), "'c' shifts onto both readings of x")
        t |> equal(length(st.stacks), 2, "... two stacks")
        let s0 = st.stacks[0]
        let s1 = st.stacks[1]
        t |> success(s0.depth == s1.depth && s0.state == s1.state, "... alike at the top")
        t |> success(lr_matches(g, "xce") && lr_matches(g, "xcf"), "neither merges into the other")
        t |> success(!lr_matches(g, "xcg"), "... and nothing else does")
    }
    t |> run("reduce chains of different lengths to one goto") @(t : T?) {
        check_chains_of_two_lengths(t)
    }
    t |> run("a slot chaining several stacks, the match not at its head") @(t : T?) {
        check_chain_past_its_head(t)
    }
    t |> run("readings that meet after the slots grew within the step") @(t : T?) {
        check_merge_after_slots_grow(t)
    }
}

[test(description = "A byte refused at LR_MAX_STACKS leaves the very same tops in the set, and a sentence one byte short of the cap completes.")]
def test_lr1_stack_cap_keeps_tops(t : T?) {
    let g <- forking_grammar()
    t |> equal(g.err, "")
    var st <- lr_start(g)
    let fed = feed_until_refused(g, st, uint8('x'), 64)
    let tops := st.stacks
    let n = length(tops)
    t |> success(n > 1 && n <= LR_MAX_STACKS, "the set stopped inside the cap ({n})")
    t |> success(!lr_step(g, st, uint8('x')), "the next x is refused")
    t |> equal(tops, st.stacks, "... leaving the same tops")
    t |> success(!lr_step(g, st, uint8('!')), "'!' is refused too: it forks the last x")
    t |> equal(tops, st.stacks, "... leaving the same tops")
    var short <- lr_start(g)
    let sentence = "{repeat("x", fed - 1)}!"
    t |> success(lr_step_bytes(g, short, sentence) && lr_at_end(g, short), "one x fewer completes")
}

[test(description = "Overlapping byte sets partition into three byte classes, and a set spanning two classes still matches through either of them.")]
def test_lr1_byte_classes(t : T?) {
    t |> run("overlapping byte sets partition into classes; a set spanning classes becomes alternatives") @(t : T?) {
        // root ::= hexdigit digit  - [0-9a-f] then [0-9]: the digits are one class, a-f another
        var gb : GrammarBuilder
        let root = rule_id(gb, "root")
        var hex : ByteSet = digits()
        for (c in range('a', 'f' + 1)) {
            hex[c] = true
        }
        var p : array<GrammarSym>
        seq(p, [sym_bytes(hex), sym_bytes(digits())])
        add_production(gb, root, p)
        var g <- build_grammar(gb, root)
        t |> equal(g.err, "", "the grammar builds")
        t |> equal(g.nclasses, 3, "digits, a-f, everything else")
        t |> success(lr_matches(g, "a7") && lr_matches(g, "37"), "both halves of the hex set lead to a digit")
        t |> success(!lr_matches(g, "7a") && !lr_matches(g, "g7"), "a letter second, or outside the set, is refused")
    }
}

// ===== the integer-terminal core =====

// `lhs ::= words` into `gb`: a word starting with an upper-case
// letter is a rule, any other a terminal
def private prod(var gb : LalrBuilder; lhs : string; text : string) {
    var rhs : array<int>
    for (w in split(text, " ")) {
        continue if (empty(w))
        let c = first_character(w)
        rhs |> push(c >= 'A' && c <= 'Z' ? rule_sym(rule_id(gb, w)) : term_sym(term_id(gb, w)))
    }
    add_production(gb, rule_id(gb, lhs), rhs)
}

def private tokens(gb : LalrBuilder; text : string) : array<int> =>
    <- [for (w in split(text, " ")); gb.term_index?[w] ?? -1; where !empty(w)]

// one stack over the primary action of each cell: whether `terms` is
// a sentence, and the productions reduced
def private parse_terms(tb : LalrTables;
                        terms : array<int>) : tuple<ok : bool; reductions : array<int>> {
    var res : tuple<ok : bool; reductions : array<int>>
    return <- res if (!empty(tb.err))
    var stack <- [0]
    var pos = 0
    for (_ in range(1000000)) {
        let term = pos < length(terms) ? terms[pos] : tb.eof
        break if (term < 0 || term > tb.eof || (term == tb.eof && pos < length(terms)))
        let a = tb.action[stack[length(stack) - 1] * tb.nterms + term]
        if (a == ACCEPT) {
            res.ok = true
            break
        } elif (a > 0) {
            stack |> push(a - 1)
            pos++
        } elif (a < 0) {
            let p = -1 - a
            res.reductions |> push(p)
            stack |> resize(length(stack) - length(tb.prods[p].rhs))
            let to = tb.goto_nt[stack[length(stack) - 1] * tb.nrules + tb.prods[p].lhs]
            break if (to < 0)
            stack |> push(to)
        } else {
            break
        }
    }
    return <- res
}

def private parses(tb : LalrTables; terms : array<int>) : bool => parse_terms(tb, terms).ok

def private expr_grammar() : LalrBuilder {
    var gb : LalrBuilder
    prod(gb, "E", "E + T")
    prod(gb, "E", "T")
    prod(gb, "T", "T * F")
    prod(gb, "T", "F")
    prod(gb, "F", "( E )")
    prod(gb, "F", "id")
    return <- gb
}

[test(description = "the textbook expression grammar over named terminals builds to its twelve LALR(1) states with no conflict and no conflict line, the end of input named last, and reduces by precedence")]
def test_lalr_expression_grammar(t : T?) {
    let gb <- expr_grammar()
    let tb <- build_lalr(gb, gb.rule_index?["E"] ?? -1)
    t |> equal(tb.err, "")
    t |> equal(tb.nstates, 12)
    t |> equal(tb.conflicts, 0)
    t |> equal(length(tb.alt), 0)
    t |> equal(length(describe_conflicts(tb)), 0)
    t |> equal(tb.nterms, 6)
    t |> equal(tb.eof, 5)
    t |> equal(tb.term_names[tb.eof], "<end>")
    t |> equal(tb.rule_names[tb.nrules - 1], "<start>")
    for (s in ["id", "id + id * id", "( id + id ) * id", "( ( id ) )"]) {
        t |> success(parses(tb, tokens(gb, s)), s)
    }
    for (s in ["", "id +", "id id", "( id", "id + * id"]) {
        t |> success(!parses(tb, tokens(gb, s)), s)
    }
    let r <- parse_terms(tb, tokens(gb, "id + id * id"))
    let names <- [for (p in r.reductions); describe_prod(tb, p)]
    t |> equal(names[length(names) - 2], "T ::= T * F")
    t |> equal(names[length(names) - 1], "E ::= E + T")
    t |> equal(describe_action(tb, ACCEPT), "accept")
    t |> equal(describe_action(tb, LALR_ACCEPT), "accept")
    t |> equal(describe_action(tb, 0), "error")
    t |> equal(describe_action(tb, 4), "shift to 3")
    t |> equal(describe_action(tb, reduce_action(1)), "reduce E ::= E + T")
    t |> equal(reduce_action(0), ACCEPT)
    t |> success(is_shift(4) && !is_shift(ACCEPT) && !is_shift(-2) && !is_shift(0))
}

[test(description = "the dangling else keeps exactly one shift/reduce cell with both actions, the shift primary and the reduce in alt, and describe_conflicts names the cell's terminal and every action")]
def test_lalr_dangling_else(t : T?) {
    var gb : LalrBuilder
    prod(gb, "S", "if C then S")
    prod(gb, "S", "if C then S else S")
    prod(gb, "S", "other")
    prod(gb, "C", "cond")
    let tb <- build_lalr(gb, rule_id(gb, "S"))
    t |> equal(tb.err, "")
    t |> equal(tb.conflicts, 1)
    t |> equal(length(tb.alt), 1)
    let lines <- describe_conflicts(tb)
    t |> equal(length(lines), 1)
    t |> success(find(lines[0], "on else: shift to") >= 0, lines[0])
    t |> success(find(lines[0], "| reduce S ::= if C then S") >= 0, lines[0])
    t |> success(starts_with(tb.first_conflict, "shift/reduce conflict in state"),
                 tb.first_conflict)
    for (cell, extra in keys(tb.alt), values(tb.alt)) {
        t |> equal(cell % tb.nterms, gb.term_index?["else"] ?? -1)
        t |> success(is_shift(tb.action[cell]), "the shift stays primary")
        t |> equal(length(extra), 1)
        t |> success(extra[0] < 0, "the reduce is kept in alt")
    }
    let r <- parse_terms(tb, tokens(gb, "if cond then if cond then other else other"))
    t |> success(r.ok)
    let s = gb.rule_index?["S"] ?? -1
    let ifs <- [for (p in r.reductions); describe_prod(tb, p);
                where tb.prods[p].lhs == s && length(tb.prods[p].rhs) > 1]
    t |> equal(ifs, ["S ::= if C then S else S", "S ::= if C then S"])
}

[test(description = "two rules deriving the same terminal keep a reduce/reduce cell on the end of input with both reductions")]
def test_lalr_reduce_reduce(t : T?) {
    var gb : LalrBuilder
    prod(gb, "S", "A")
    prod(gb, "S", "B")
    prod(gb, "A", "x")
    prod(gb, "B", "x")
    let tb <- build_lalr(gb, rule_id(gb, "S"))
    t |> equal(tb.conflicts, 1)
    t |> success(starts_with(tb.first_conflict, "reduce/reduce conflict"), tb.first_conflict)
    let lines <- describe_conflicts(tb)
    t |> success(find(lines[0], "on <end>: reduce A ::= x | reduce B ::= x") >= 0, lines[0])
}

[test(description = "a reachable rule that derives no terminal string, or has no production, fails the build naming the rule and builds no tables, an unreachable one does not; an undeclared terminal, rule, root or left-hand side - negative or past the last rule - fails it too and builds no tables")]
def test_lalr_ill_formed(t : T?) {
    {
        var gb : LalrBuilder
        prod(gb, "S", "A x")
        prod(gb, "A", "A y")
        let tb <- build_lalr(gb, rule_id(gb, "S"))
        t |> equal(tb.err, "rule 'A' derives no terminal string")
        t |> equal(tb.err_rule, "A")
        t |> equal(tb.nstates, 0)
        t |> success(!parses(tb, tokens(gb, "x")))
    }
    {
        var gb : LalrBuilder
        prod(gb, "S", "x")
        prod(gb, "S", "Empty")
        t |> equal(build_lalr(gb, rule_id(gb, "S")).err, "rule 'Empty' derives no terminal string")
    }
    {
        var gb : LalrBuilder
        prod(gb, "S", "x")
        prod(gb, "Dead", "Dead y")
        let tb <- build_lalr(gb, rule_id(gb, "S"))
        t |> equal(tb.err, "")
        t |> success(parses(tb, tokens(gb, "x")))
    }
    var gb : LalrBuilder
    declare_terms(gb, 2)
    t |> equal(gb.term_names, ["#0", "#1"])
    add_production(gb, rule_id(gb, "S"), [term_sym(0), term_sym(2)])
    t |> equal(build_lalr(gb, 0).err, "production 0 of 'S' uses terminal 2, which is not declared")
    var gb2 : LalrBuilder
    add_production(gb2, rule_id(gb2, "S"), [rule_sym(5)])
    t |> equal(build_lalr(gb2, 0).err, "production 0 of 'S' uses rule 5, which is not declared")
    t |> equal(build_lalr(gb2, 3).err, "root rule 3 is not a declared rule")
    t |> equal(build_lalr(gb2, -1).err, "root rule -1 is not a declared rule")
    var gb3 : LalrBuilder
    rule_id(gb3, "S")
    add_production(gb3, 4, [term_sym(term_id(gb3, "x"))])
    t |> equal(build_lalr(gb3, 0).err, "production 0 has left-hand side 4, not a declared rule")
    var gb4 : LalrBuilder
    let s4 = rule_id(gb4, "S")
    let x4 = term_id(gb4, "x")
    add_production(gb4, s4, [term_sym(x4)])
    add_production(gb4, -1, [term_sym(0)])
    let tb4 <- build_lalr(gb4, 0)
    t |> equal(tb4.err, "production 1 has left-hand side -1, not a declared rule")
    t |> success(tb4.nstates == 0 && empty(tb4.action) && empty(tb4.prods))
}

[test(description = "declare_terms extends the terminals already declared up to the count, naming each new id by number, and fresh_rule declares a rule rule_id never returns, even under the same name")]
def test_lalr_builder_ids(t : T?) {
    {
        var gb : LalrBuilder
        t |> equal(term_id(gb, "#1"), 0)
        declare_terms(gb, 2)
        t |> equal(length(gb.term_names), 2)
        add_production(gb, rule_id(gb, "S"), [term_sym(0), term_sym(1)])
        let tb <- build_lalr(gb, 0)
        t |> equal(tb.err, "")
        t |> success(parses(tb, [0, 1]))
    }
    {
        var gb : LalrBuilder
        term_id(gb, "x")
        term_id(gb, "y")
        declare_terms(gb, 2)
        t |> equal(gb.term_names, ["x", "y"], "two declared terminals already meet a count of two")
        declare_terms(gb, 3)
        t |> equal(gb.term_names, ["x", "y", "#2"])
    }
    var gr : LalrBuilder
    let fresh = fresh_rule(gr, "A")
    let named = rule_id(gr, "A")
    t |> success(fresh != named, "fresh {fresh}, named {named}")
    t |> equal(rule_id(gr, "A"), named)
}

[test(description = "an epsilon production builds and accepts the empty and a non-empty sentence, and with no terminal declared at all the end of input is the only column, id 0, and the empty sentence is accepted")]
def test_lalr_epsilon(t : T?) {
    var gb : LalrBuilder
    prod(gb, "L", "")
    prod(gb, "L", "L item")
    let tb <- build_lalr(gb, rule_id(gb, "L"))
    t |> equal(tb.err, "")
    t |> equal(tb.conflicts, 0)
    t |> success(parses(tb, tokens(gb, "")))
    t |> success(parses(tb, tokens(gb, "item item item")))
    var gn : LalrBuilder
    prod(gn, "S", "")
    let tn <- build_lalr(gn, rule_id(gn, "S"))
    t |> equal(tn.err, "")
    t |> equal(tn.nterms, 1)
    t |> equal(tn.eof, 0)
    t |> success(parses(tn, tokens(gn, "")), "no declared terminal: the end of input is column 0")
}

[test(description = "over 3000 terminals, lookaheads 951 and 2999 stay apart where a 1024-wide lookahead field would key one item's 2999 as a later item's 951, and a 4096-terminal production ending in a rule parses: the item key packs no field of fixed width")]
def test_lalr_wide_grammar(t : T?) {
    {
        var gb : LalrBuilder
        declare_terms(gb, 3000)
        let s = rule_id(gb, "S")
        let a = rule_id(gb, "A")
        add_production(gb, s, [rule_sym(a), term_sym(951)])
        add_production(gb, s, [rule_sym(a), term_sym(2999)])
        add_production(gb, a, [term_sym(10)])
        add_production(gb, a, [term_sym(10), term_sym(11)])
        let tb <- build_lalr(gb, s)
        t |> equal(tb.err, "")
        t |> equal(tb.conflicts, 0)
        t |> equal(tb.nterms, 3001)
        for (k in [951, 2999]) {
            t |> success(parses(tb, [10, k]), "A ::= 10, then {k}")
            t |> success(parses(tb, [10, 11, k]), "A ::= 10 11, then {k}")
        }
        t |> success(!parses(tb, [10, 1500]))
        t |> success(!parses(tb, [10, 951 + 1024]),
                     "a lookahead 1024 past a real one is not the real one")
    }
    var gb : LalrBuilder
    declare_terms(gb, 2)
    let s = rule_id(gb, "S")
    let b = rule_id(gb, "B")
    var long_rhs <- [for (_ in range(4096)); term_sym(0)]
    long_rhs |> push(rule_sym(b))
    add_production(gb, s, long_rhs)
    add_production(gb, b, [term_sym(1)])
    let tb <- build_lalr(gb, s)
    t |> equal(tb.err, "")
    var input <- [for (_ in range(4096)); 0]
    input |> push(1)
    t |> success(parses(tb, input))
}

[test(description = "a nullable rule lets FIRST and the lookaheads see past it, and FIRST reaches a rule through a chain declared after its user")]
def test_lalr_nullable_first(t : T?) {
    {
        var gb : LalrBuilder
        prod(gb, "S", "A B c")
        prod(gb, "A", "a")
        prod(gb, "B", "")
        prod(gb, "B", "b")
        let tb <- build_lalr(gb, rule_id(gb, "S"))
        t |> equal(tb.err, "")
        t |> equal(tb.conflicts, 0)
        t |> success(parses(tb, tokens(gb, "a c")), "a c")
        t |> success(parses(tb, tokens(gb, "a b c")), "a b c")
    }
    {
        var gb : LalrBuilder
        prod(gb, "S", "A D")
        prod(gb, "D", "C")
        prod(gb, "C", "B")
        prod(gb, "B", "y")
        prod(gb, "A", "x")
        let tb <- build_lalr(gb, rule_id(gb, "S"))
        t |> success(parses(tb, tokens(gb, "x y")),
                     "x y through D ::= C ::= B, each declared after its user")
    }
    var gb : LalrBuilder
    prod(gb, "S", "A D")
    prod(gb, "D", "B c")
    prod(gb, "A", "a")
    prod(gb, "B", "")
    prod(gb, "B", "b")
    let tb <- build_lalr(gb, rule_id(gb, "S"))
    t |> success(parses(tb, tokens(gb, "a c")), "FIRST(D) passes the nullable B")
}

[test(description = "an action two closure items add to one cell is one action, a cell of three reductions each added twice keeps two in alt, and the first conflict names the first cell's first other action")]
def test_lalr_duplicate_actions(t : T?) {
    {
        var gb : LalrBuilder
        prod(gb, "S", "x E y")
        prod(gb, "S", "x E y w")
        prod(gb, "E", "")
        let tb <- build_lalr(gb, rule_id(gb, "S"))
        t |> equal(tb.conflicts, 0)
        t |> equal(length(tb.alt), 0)
        t |> success(parses(tb, tokens(gb, "x y w")))
    }
    var gb : LalrBuilder
    for (r in ["E", "F", "G"]) {
        prod(gb, "S", "x {r} y")
        prod(gb, "S", "x {r} y w")
        prod(gb, r, "")
    }
    prod(gb, "S", "z H q")
    prod(gb, "S", "z K q")
    prod(gb, "H", "")
    prod(gb, "K", "")
    let tb <- build_lalr(gb, rule_id(gb, "S"))
    t |> equal(tb.conflicts, 2)
    let lines <- describe_conflicts(tb)
    t |> equal(length(lines), 2)
    t |> success(ends_with(lines[0], " on y: reduce E ::= | reduce F ::= | reduce G ::="), lines[0])
    t |> success(ends_with(lines[1], " on q: reduce H ::= | reduce K ::="), lines[1])
    t |> success(ends_with(tb.first_conflict, " on y: reduce F ::="), tb.first_conflict)
}

// ===== byte classes over the core =====

[test(description = "byte classes are the core's terminals: a one-byte class is named by its byte, quoted only when printable (DEL is not), the end of input is the column after the last class, and a byte set spanning several classes is one set rule with a production per class, reused by a second use of the same set")]
def test_lr1_classes_as_terminals(t : T?) {
    var gb : GrammarBuilder
    let s = rule_id(gb, "s")
    add_production(gb, s, [sym_bytes(range_set('a', 'c')), sym_byte('x')])
    add_production(gb, s, [sym_byte('b'), sym_byte('y')])
    add_production(gb, s, [sym_bytes(range_set('a', 'c')), sym_byte(',')])
    add_production(gb, s, [sym_byte('\''), sym_byte(' ')])
    let g <- build_grammar(gb, s)
    t |> equal(g.err, "")
    t |> equal(g.nclasses, 8)
    t |> equal(g.nterms, g.nclasses + 1)
    t |> equal(g.eof, g.nclasses)
    t |> equal(g.byte_class['a'], g.byte_class['c'])
    t |> equal(g.term_names[g.byte_class[',']], "','")
    t |> equal(g.term_names[g.byte_class['a']], "class {g.byte_class['a']}")
    t |> equal(g.term_names[g.byte_class['\'']], "byte 39")
    t |> equal(g.term_names[g.byte_class[' ']], "byte 32")
    t |> equal(g.term_names[g.eof], "<end>")
    let sets <- [for (n in g.rule_names); n; where starts_with(n, "<set")]
    t |> equal(length(sets), 1)
    var set_prods = 0
    for (p in g.prods) {
        set_prods += g.rule_names[p.lhs] == sets[0] ? 1 : 0
    }
    t |> equal(set_prods, 2)
    for (w in ["ax", "bx", "cx", "by", "a,", "c,", "' "]) {
        t |> success(lr_matches(g, w), w)
    }
    for (w in ["ay", "cy", "b", "xb", "'"]) {
        t |> success(!lr_matches(g, w), w)
    }
    var gd : GrammarBuilder
    add_production(gd, rule_id(gd, "s"), [sym_byte(127), sym_byte('~')])
    let del <- build_grammar(gd, 0)
    t |> equal(del.term_names[del.byte_class[127]], "byte 127", "DEL is no printable quote")
    t |> equal(del.term_names[del.byte_class['~']], "'~'")
}

[test(description = "a set rule never merges with a user rule of the same name: with a user rule named `<set2>` the set `[ab]` keeps its own two productions, so `[ab] <set2>` accepts `aa` and `ba` only, with no conflict")]
def test_lr1_set_rule_name_clash(t : T?) {
    var gb : GrammarBuilder
    let root = rule_id(gb, "root")
    let user_set = rule_id(gb, "<set2>")
    add_production(gb, root, [sym_bytes(range_set('a', 'b')), sym_rule(user_set)])
    add_production(gb, user_set, [sym_byte('a')])
    let g <- build_grammar(gb, root)
    t |> equal(g.err, "")
    t |> equal(g.conflicts, 0)
    for (w in ["aa", "ba"]) {
        t |> success(lr_matches(g, w), w)
    }
    for (w in ["ab", "bb"]) {
        t |> success(!lr_matches(g, w), w)
    }
}

[test(description = "an empty byte set is a set rule with no production and fails the build naming the rule that uses it, and a root that is no rule of the builder - out of range, or the id a set rule takes - fails it without tables")]
def test_lr1_byte_errors(t : T?) {
    let empty_set : ByteSet
    var gb : GrammarBuilder
    let s = rule_id(gb, "s")
    add_production(gb, s, [sym_byte('a'), sym_bytes(empty_set)])
    let g <- build_grammar(gb, s)
    t |> equal(g.err, "rule 's' derives no terminal string")
    t |> success(!lr_matches(g, "a"))
    let g2 <- build_grammar(gb, 7)
    t |> equal(g2.err, "root rule 7 is not a declared rule")
    var st <- lr_start(g2)
    t |> success(!lr_step(g2, st, uint8('a')) && !lr_at_end(g2, st) &&
                 !lr_accepts(g2, st, uint8('a')))
    var gs : GrammarBuilder
    let s1 = rule_id(gs, "s")
    add_production(gs, s1, [sym_bytes(range_set('a', 'b'))])
    add_production(gs, s1, [sym_byte('a')])
    let g3 <- build_grammar(gs, 1)
    t |> equal(g3.err, "root rule 1 is not a declared rule", "the set rule `[ab]` makes is no root")
    t |> equal(g3.nstates, 0)
    t |> success(!lr_matches(g3, "a") && !lr_matches(g3, "b"))
    let g4 <- build_grammar(gs, s1)
    t |> equal(g4.err, "")
    t |> success(lr_matches(g4, "a") && lr_matches(g4, "b") && !lr_matches(g4, "c"))
}

[test(description = "a 4096-byte literal followed by a rule builds a shift into that rule: the item past the 4096th byte keys apart from the next production's first item")]
def test_lr1_long_production(t : T?) {
    var gb : GrammarBuilder
    let s = rule_id(gb, "s")
    let b = rule_id(gb, "b")
    var rhs <- [for (_ in range(4096)); sym_byte('a')]
    rhs |> push(sym_rule(b))
    add_production(gb, s, rhs)
    add_production(gb, b, [sym_byte('b')])
    let g <- build_grammar(gb, s)
    t |> equal(g.err, "")
    t |> equal(g.conflicts, 0)
    let col = g.byte_class['b']
    let shifts_b <- [for (si in range(g.nstates)); si;
                     where is_shift(g.action[si * g.nterms + col])]
    t |> equal(length(shifts_b), 1, "the state after 4096 a's shifts b")
    let gotos_b <- [for (si in range(g.nstates)); si; where g.goto_nt[si * g.nrules + b] >= 0]
    t |> equal(gotos_b, shifts_b, "... and goes to b's state from the same state")
}
