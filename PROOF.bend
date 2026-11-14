# The proofs of LAWS.bend. Nothing here is trusted: `bend PROOF.bend`
# checks every def, `--verdict` rechecks them with BendTT's kernel.

import Base
import ./Wire.bend as W
import ./LAWS.bend as Laws

# One byte's step, its two ways: the head ends here (both sides end it, the
# fed one with the later bytes after it), or it does not (both go on with the
# rest, which is the law again, one byte shorter).
law feed_cut.at:
  for done: Bool
  for -rev: List<&2, U32>
  for +seen: U32
  for -t: List<&2, U32>
  for -cs: List<&2, U32>
  for ih: {W.wr.feed(W.wr.cut(t, rev, seen), cs) == W.wr.cut(List.append(&2, U32, t, cs), rev, seen) : W.wr.Cut}
  {W.wr.feed(W.wr.cut.at(done, rev, seen, t, r => s => W.wr.cut(t, r, s)), cs)
     == W.wr.cut.at(done, rev, seen, List.append(&2, U32, t, cs), r => s => W.wr.cut(List.append(&2, U32, t, cs), r, s)) : W.wr.Cut}

def feed_cut.at(done, rev, seen, t, cs, ih):
  match done:
    case True{}:
      {==}
    case False{}:
      ih

def Laws.feed_cut(bs, rev, seen, cs):
  match bs:
    case Nil{}:
      {==}
    case Con{+b, t}:
      feed_cut.at(U32.is_eq(W.wr.next(seen, b), 4), b <> rev, W.wr.next(seen, b), t, cs,
                  Laws.feed_cut(t, b <> rev, W.wr.next(seen, b), cs))

# head_then: feed_cut, then the whole head's cut
def Laws.head_then(h, bs, whole):
  %Laws.feed_cut(h, [], 0, bs) : {_ == W.wr.Head{h, bs} : W.wr.Cut}
  %Equal.sym(W.wr.Cut, W.wr.cut(h, [], 0), W.wr.Head{h, []}, whole) : {W.wr.feed(_, bs) == W.wr.Head{h, bs} : W.wr.Cut}
  {==}

# body_then: by the body, a byte at a time
def Laws.body_then(body, rest):
  match body:
    case Nil{}:
      {==}
    case Con{+b, t}:
      %Equal.sym(List<&2, U32> & List<&2, U32>, W.wr.split(List.length(&2, U32, t), List.append(&2, U32, t, rest)), (t, rest), Laws.body_then(t, rest))
        : {W.wr.split.cons(b, _) == (b <> t, rest) : List<&2, U32> & List<&2, U32>}
      {==}

def Laws.mid_id_left(m, app, r):
  {==}

def Laws.mid_id_right(m, app, r):
  {==}

def Laws.mid_assoc(f, g, h, app, r):
  {==}
