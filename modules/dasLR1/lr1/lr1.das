options gen2
options indenting = 4
options strict_smart_pointers = true

module lr1 shared public

require lr1/lr1_lalr public
require daslib/strings_boost

// An LALR(1) parser generator over BYTE terminals, built at run time
// from a grammar a program assembles (`GrammarBuilder`) or reads from
// text (`lr1/gbnf`): byte classes become the terminals of the integer
// core (`lr1/lr1_lalr`), which builds the tables. Over them runs an
// incremental acceptor: feed one byte, ask which bytes may come next,
// probe a whole byte string on a copy of the stack. The acceptor has
// the viable-prefix property - a byte is refused the moment no
// sentence of the grammar extends the prefix - so a sampler masking
// tokens through it never emits a prefix it must later undo.

//! A set of bytes: one flag per byte value.
typedef ByteSet = bool[256]

//! A symbol on a production's right-hand side before the grammar is finalized: a byte set, or a rule.
struct GrammarSym {
    is_rule : bool
    rule : int          //!< the rule id when is_rule
    bytes : ByteSet     //!< the terminal's byte set otherwise
}

//! A finalized grammar: the core's LALR(1) tables over byte classes.
//! Class `c` is terminal id `c`, so
//! `action[state * (nclasses + 1) + cls]` reads a byte's column and
//! the end-of-input column is `nclasses` (`eof`), where `ACCEPT`
//! marks acceptance. A byte set that spans several classes is a rule
//! named `<setN>`, one production per class. A cell with more than
//! one action keeps the others in `alt`: the grammar is not LALR(1)
//! there and the acceptor forks its stack, so an ambiguous grammar
//! still accepts exactly its language; `conflicts` counts such cells
//! and `first_conflict` names the first.
struct Grammar : LalrTables {
    byte_class : array<int>     //!< 256 entries: byte -> terminal class
    nclasses : int
}

//! The acceptor's state: the set of live LR stacks - one for a deterministic grammar, several while an
//! ambiguous grammar's alternatives are all still open. A copy for a probe clones the set.
struct LrStack {
    stacks : array<array<int>>
}

//! The most stacks the acceptor keeps alive; past it the acceptor refuses, so a pathological grammar
//! cannot grow without bound.
let LR_MAX_STACKS = 256

// ===== building =====

//! Assembles a grammar: rules by name, productions as sequences of byte sets and rule references.
struct GrammarBuilder {
    rule_names : array<string>
    rule_index : table<string; int>
    prods : array<tuple<lhs : int; rhs : array<GrammarSym>>>
}

//! The id of rule `name`, declared on first mention.
def rule_id(var gb : GrammarBuilder; name : string) : int =>
    intern(gb.rule_names, gb.rule_index, name)

def sym_rule(rule : int) : GrammarSym => GrammarSym(is_rule = true, rule = rule)

def sym_byte(b : int) : GrammarSym {
    var s : GrammarSym
    s.bytes[b] = true
    return s
}

def sym_bytes(bytes : ByteSet) : GrammarSym {
    var s : GrammarSym
    s.bytes = bytes
    return s
}

//! Add `lhs -> rhs`; an empty `rhs` is the epsilon production.
def add_production(var gb : GrammarBuilder; lhs : int; var rhs : array<GrammarSym>) {
    gb.prods |> emplace((lhs = lhs, rhs <- rhs))
}

def byteset_empty(bs : ByteSet) : bool {
    for (i in range(256)) {
        if (bs[i]) {
            return false
        }
    }
    return true
}

// the finest partition of the byte alphabet that every terminal set
// of the grammar is a union of: refine a single class by each set in
// turn, then number the classes in byte order
def private byte_classes(gb : GrammarBuilder; var cls : array<int>) : int {
    cls |> resize(256)
    var n = 1
    for (p in gb.prods) {
        for (s in p.rhs) {
            continue if (s.is_rule)
            var inscope remap : table<int; int>
            for (b in range(256)) {
                continue if (!s.bytes[b])
                let old = cls[b]
                if (!(remap |> key_exists(old))) {
                    var outside = false
                    for (c in range(256)) {
                        if (cls[c] == old && !s.bytes[c]) {
                            outside = true
                            break
                        }
                    }
                    remap[old] = outside ? n : old
                    if (outside) {
                        n++
                    }
                }
                cls[b] = remap[old]
            }
        }
    }
    var seen : table<int; int>
    for (b in range(256)) {
        let old = cls[b]
        if (!(seen |> key_exists(old))) {
            seen[old] = length(seen)
        }
        cls[b] = seen[old]
    }
    return length(seen)
}

// a class's terminal name: its byte when it holds one, else `class N`
def private class_name(cls : array<int>; c : int) : string {
    var only = -1
    for (b in range(256)) {
        continue if (cls[b] != c)
        return "class {c}" if (only >= 0)
        only = b
    }
    if (only > 32 && only < 127 && only != '\'') {
        return "'{to_char(only)}'"
    }
    return "byte {only}"
}

// the right-hand side of `gp` as core symbols: a set of one class is
// that terminal, a set of several is the set rule of its classes,
// declared on first use
def private core_rhs(var lb : LalrBuilder; var set_rules : table<string; int>;
                     byte_class : array<int>;
                     gp : tuple<lhs : int; rhs : array<GrammarSym>>) : array<int> {
    var rhs : array<int>
    for (s in gp.rhs) {
        if (s.is_rule) {
            rhs |> push(rule_sym(s.rule))
            continue
        }
        var inscope classes : array<int>
        var inscope seen : table<int>
        for (b in range(256)) {
            if (s.bytes[b] && !(seen |> key_exists(byte_class[b]))) {
                seen |> insert(byte_class[b])
                classes |> push(byte_class[b])
            }
        }
        if (length(classes) == 1) {
            rhs |> push(term_sym(classes[0]))
            continue
        }
        sort(classes)
        let key = join(classes, ",")
        var set_rule = set_rules?[key] ?? -1
        if (set_rule < 0) {
            set_rule = fresh_rule(lb, "<set{length(lb.rule_names)}>")
            set_rules[key] = set_rule
            for (c in classes) {
                add_production(lb, set_rule, [term_sym(c)])
            }
        }
        rhs |> push(rule_sym(set_rule))
    }
    return <- rhs
}

//! Finalize `gb` with `root` as the start rule: the byte classes,
//! each declared as a terminal of the LALR(1) core, then the core's
//! tables over them. The result's `err` is non-empty for a root that
//! is not a rule of `gb` (a set rule is never a root) or a reachable
//! rule that derives no terminal string; such a grammar accepts
//! nothing. A table conflict is not an error: the acceptor forks its
//! stack there.
def build_grammar(gb : GrammarBuilder; root : int) : Grammar {
    var g : Grammar
    if (root < 0 || root >= length(gb.rule_names)) {
        g.err = "root rule {root} is not a declared rule"
        return <- g
    }
    g.nclasses = byte_classes(gb, g.byte_class)
    var lb : LalrBuilder
    for (c in range(g.nclasses)) {
        term_id(lb, class_name(g.byte_class, c))
    }
    for (name in gb.rule_names) {
        rule_id(lb, name)
    }
    var set_rules : table<string; int>
    for (gp in gb.prods) {
        var inscope rhs <- core_rhs(lb, set_rules, g.byte_class, gp)
        add_production(lb, gp.lhs, rhs)
    }
    build_lalr_into(lb, root, g)
    return <- g
}

// ===== the acceptor =====

//! A fresh stack set at the start state.
[unused_argument(g)]
def lr_start(g : Grammar) : LrStack {
    var st : LrStack
    var one : array<int>
    one |> push(0)
    st.stacks |> emplace(one)
    return <- st
}

// every action of a cell: the primary one, then the alternatives of a conflicting cell
def private actions_at(g : Grammar; state, cls : int; var out : array<int>) {
    out |> clear()
    let cell = state * g.nterms + cls
    let a = g.action[cell]
    if (a != 0) {
        out |> push(a)
        g.alt |> get(cell) $(extra) {
            for (x in extra) {
                out |> push(x)
            }
        }
    }
}

def private stack_key(st : array<int>) : string => join(st, ",")

// follow every reduce chain of `st` on lookahead `cls`; each stack whose chain ends in a shift (or in
// ACCEPT on the EOF column) lands in `out`, the shift target at its top for a terminal class; false when
// the set would grow past LR_MAX_STACKS (the chains left unwalked)
def private resolve(g : Grammar; st : array<int>; cls : int; var out : array<array<int>>; var seen : table<string>) : bool {
    var work : array<array<int>>
    var first := st
    work |> emplace(first)
    var acts : array<int>
    while (!empty(work)) {
        return false if (length(out) > LR_MAX_STACKS)
        var inscope cur <- work[length(work) - 1]
        work |> pop()
        let key = stack_key(cur)
        continue if (seen |> key_exists(key))
        seen |> insert(key)
        actions_at(g, cur[length(cur) - 1], cls, acts)
        for (a in acts) {
            if (a == ACCEPT) {
                var done := cur
                done |> push(ACCEPT)
                out |> emplace(done)
            } elif (a > 0) {
                var shifted := cur
                shifted |> push(a - 1)
                out |> emplace(shifted)
            } else {
                let p & = unsafe(g.prods[-1 - a])
                var reduced := cur
                reduced |> resize(length(reduced) - length(p.rhs))
                let to = g.goto_nt[reduced[length(reduced) - 1] * g.nrules + p.lhs]
                if (to >= 0) {
                    reduced |> push(to)
                    work |> emplace(reduced)
                }
            }
        }
    }
    return length(out) <= LR_MAX_STACKS
}

// the stack set after consuming terminal class `cls`; empty when the class is refused - by the grammar, or
// because the set would grow past LR_MAX_STACKS
def private advance(g : Grammar; st : LrStack; cls : int) : LrStack {
    var next : LrStack
    next.stacks |> reserve(length(st.stacks))
    var seen : table<string>
    for (s in st.stacks) {
        if (!resolve(g, s, cls, next.stacks, seen)) {
            next.stacks |> clear()
            return <- next
        }
    }
    // dedupe the survivors
    var uniq : table<string>
    var kept : array<array<int>>
    kept |> reserve(length(next.stacks))
    for (s in next.stacks) {
        let k = stack_key(s)
        if (!(uniq |> key_exists(k))) {
            uniq |> insert(k)
            kept |> emplace(s)
        }
    }
    next.stacks <- kept
    return <- next
}

//! Feed one byte: true and the state advanced, or false and the state unchanged (the byte is refused).
def lr_step(g : Grammar; var st : LrStack; b : uint8) : bool {
    return false if (!empty(g.err) || empty(st.stacks))
    var next <- advance(g, st, g.byte_class[int(b)])
    if (empty(next.stacks)) {
        return false
    }
    st.stacks <- next.stacks
    return true
}

//! Whether the prefix fed so far is a complete sentence (the end of input is acceptable here).
def lr_at_end(g : Grammar; st : LrStack) : bool {
    return false if (!empty(g.err))
    let next <- advance(g, st, g.eof)
    for (s in next.stacks) {
        if (s[length(s) - 1] == ACCEPT) {
            return true
        }
    }
    return false
}

//! Whether `b` may come next, the state untouched.
def lr_accepts(g : Grammar; st : LrStack; b : uint8) : bool {
    return false if (!empty(g.err))
    let next <- advance(g, st, g.byte_class[int(b)])
    return !empty(next.stacks)
}

//! The set of bytes that may come next.
def lr_next_bytes(g : Grammar; st : LrStack) : ByteSet {
    var out : ByteSet
    return out if (!empty(g.err))
    var by_class : table<int; bool>
    for (b in range(256)) {
        let cls = g.byte_class[b]
        if (!(by_class |> key_exists(cls))) {
            let next <- advance(g, st, cls)
            by_class[cls] = !empty(next.stacks)
        }
        out[b] = by_class[cls]
    }
    return out
}

//! Feed every byte of `s`: true when all were accepted (the state advanced past them), false and the
//! state unchanged otherwise - the whole-token probe a sampler asks per candidate.
def lr_step_bytes(g : Grammar; var st : LrStack; s : string) : bool {
    var probe : LrStack
    probe.stacks := st.stacks
    var ok = true
    peek_data(s) $(d : array<uint8> const#) {
        for (b in d) {
            if (!lr_step(g, probe, b)) {
                ok = false
                break
            }
        }
    }
    if (ok) {
        st.stacks <- probe.stacks
    }
    return ok
}

//! Whether the whole string `s` is a sentence of the grammar.
def lr_matches(g : Grammar; s : string) : bool {
    var st <- lr_start(g)
    return lr_step_bytes(g, st, s) && lr_at_end(g, st)
}
