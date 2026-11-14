import Base

# Wire: HTTP/1.1 on bytes (http-types', wai's and warp's job in the Haskell
# backend), the pure part; Serve.bend runs it on sockets.
#
# What it means. A request is its head (method, version, target, headers)
# and its body; a response is a status, headers and a body. An application
# means a function from requests to responses (in IO: it may read the
# world), `wr.App`; a middleware means a function from applications to
# applications, and they compose as functions do (LAWS.bend: a monoid).
#
# A connection means the requests its bytes are, in order, each answered as
# if alone: `wr.cut` finds where a head ends however the bytes come in
# pieces (fed one piece after another it answers what it answers fed them
# all at once: law feed_cut), the head says how long the body is, and what
# follows the body is the next request (keep-alive, pipelining: law
# next_request).
#
# Bytes are one List cell each, as TCP.recv_bytes gives them.
#
# Every def is prefixed `wr.` (a program's defs share one namespace).

type wr.H is Data:
  wr.H{name: String, value: String}

# two strings (a pair of them is a Type, not Data, so no Maybe holds one)
type wr.Two is Data:
  wr.Two{a: String, b: String}

# a query's parameter: its key and value, %-decoded ("+" a space); a key
# with no "=" has no value
type wr.Q is Data:
  wr.Q{key: String, value: Maybe<&2, String>}

# A request: method, version, path (wai's pathInfo: the target's path cut at
# every "/", the first "" dropped, each %-decoded; "/" is []), the path as
# sent (before "?"), the query, headers (names in lower case), body, and the
# peer's address ("" not known).
type wr.Req is Data:
  wr.Req{method: String, version: String, path: List<&2, String>, raw: String, query: List<&2, wr.Q>, headers: List<&2, wr.H>, body: List<&2, U32>, peer: String}

# Where a request's head ends: not yet (the bytes so far, reversed, and how
# much of "\r\n\r\n" ends them), or the head (with its "\r\n\r\n") and the
# bytes after it.
type wr.Cut is Data:
  wr.More{rev: List<&2, U32>, seen: U32}
  wr.Head{head: List<&2, U32>, rest: List<&2, U32>}

# a UTF-8 read so far: continuation bytes still wanted, the code so far, the
# characters read (reversed)
type wr.U8 is Data:
  wr.U8{need: U32, code: U32, out: String}

# A body: text (sent as UTF-8), bytes, or `size` bytes of a file from `off`,
# read as they are sent.
type wr.Body is Data:
  wr.Text{s: String}
  wr.Bytes{bs: List<&2, U32>}
  wr.File{path: String, off: U32, size: U32}

type wr.Resp is Data:
  wr.Resp{status: U32, headers: List<&2, wr.H>, body: wr.Body}

# a choice whose branches are computed only when taken (Bool.pick computes
# both)
def wr.if(-A: Data, b: Bool, t: Unit -> A, e: Unit -> A) -> A:
  match b:
    case True{}:
      t(Unit{})
    case False{}:
      e(Unit{})

# The head's end
# -------------

# the byte "\r\n\r\n" wants after `seen` of it
def wr.want(+seen: U32) -> U32:
  Bool.pick(U32, U32.is_even(seen), 13, 10)

# how much of "\r\n\r\n" the bytes end in, after one more
def wr.next(+seen: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_eq(b, wr.want(seen)), (seen + 1 : U32), Bool.pick(U32, U32.is_eq(b, 13), 1, 0))

def wr.cut.at(done: Bool, rev: List<&2, U32>, +seen: U32, +rest: List<&2, U32>, more: List<&2, U32> -> U32 -> wr.Cut) -> wr.Cut:
  match done:
    case True{}:
      wr.Head{List.reverse(&2, U32, rev), rest}
    case False{}:
      more(rev, seen)

# The bytes bs, after rev (reversed) which ended in `seen` of "\r\n\r\n".
def wr.cut(bs: List<&2, U32>, rev: List<&2, U32>, +seen: U32) -> wr.Cut:
  match bs:
    case Nil{}:
      wr.More{rev, seen}
    case Con{+b, +t}:
      wr.cut.at(U32.is_eq(wr.next(seen, b), 4), b <> rev, wr.next(seen, b), t, r => s => wr.cut(t, r, s))

# More bytes come.
def wr.feed(c: wr.Cut, bs: List<&2, U32>) -> wr.Cut:
  match c:
    case wr.More{rev, +seen}:
      wr.cut(bs, rev, seen)
    case wr.Head{h, rest}:
      wr.Head{h, List.append(&2, U32, rest, bs)}

# Text
# ----

# bytes as Latin-1 (a head is ASCII)
def wr.latin1(bs: List<&2, U32>) -> String:
  match bs:
    case Nil{}:
      SNil{}
    case Con{b, t}:
      SCon{Chr{b}, wr.latin1(t)}

def wr.u8.onto.at(one: Bool, two: Bool, three: Bool, +c: U32, out: List<&2, U32>) -> List<&2, U32>:
  match one two three:
    case True{} _ _:
      c <> out
    case False{} True{} _:
      U32.or(192, U32.shrn(c, 6n)) <> U32.or(128, U32.and(c, 63)) <> out
    case False{} False{} True{}:
      U32.or(224, U32.shrn(c, 12n)) <> U32.or(128, U32.and(U32.shrn(c, 6n), 63)) <> U32.or(128, U32.and(c, 63)) <> out
    case False{} False{} False{}:
      U32.or(240, U32.shrn(c, 18n)) <> U32.or(128, U32.and(U32.shrn(c, 12n), 63)) <> U32.or(128, U32.and(U32.shrn(c, 6n), 63)) <> U32.or(128, U32.and(c, 63)) <> out

# a character's UTF-8, onto the bytes after it
def wr.u8.onto(+c: U32, out: List<&2, U32>) -> List<&2, U32>:
  wr.u8.onto.at(U32.is_lt(c, 128), U32.is_lt(c, 2048), U32.is_lt(c, 65536), c, out)

# a string's UTF-8
def wr.utf8.of(s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      []
    case SCon{Chr{+c}, t}:
      wr.u8.onto(c, wr.utf8.of(t))

# how many bytes a string's UTF-8 is
def wr.utf8.len(s: String, +n: U32) -> U32:
  match s:
    case SNil{}:
      n
    case SCon{Chr{+c}, t}:
      wr.utf8.len(t, (n + Bool.pick(U32, U32.is_lt(c, 128), 1, Bool.pick(U32, U32.is_lt(c, 2048), 2, Bool.pick(U32, U32.is_lt(c, 65536), 3, 4))) : U32))

# UTF-8 read: `need` continuation bytes still wanted for `code`; a byte that
# breaks a sequence ends it as U+FFFD
def wr.u8.lead.at(l1: Bool, l2: Bool, l3: Bool, l4: Bool, l5: Bool, +b: U32) -> U32 & U32:
  match l1 l2 l3 l4 l5:
    case True{} _ _ _ _:
      (0, b)
    case False{} True{} _ _ _:
      (9, 65533)
    case False{} False{} True{} _ _:
      (1, U32.and(b, 31))
    case False{} False{} False{} True{} _:
      (2, U32.and(b, 15))
    case False{} False{} False{} False{} True{}:
      (3, U32.and(b, 7))
    case False{} False{} False{} False{} False{}:
      (9, 65533)

def wr.u8.lead(+b: U32) -> U32 & U32:
  wr.u8.lead.at(U32.is_lt(b, 128), U32.is_lt(b, 192), U32.is_lt(b, 224), U32.is_lt(b, 240), U32.is_lt(b, 248), b)

def wr.u8.put.at(done: Bool, bad: Bool, +code: U32, out: String) -> String:
  match done bad:
    case True{} _:
      SCon{Chr{code}, out}
    case False{} True{}:
      SCon{Chr{65533}, out}
    case False{} False{}:
      out

def wr.u8.put(+need: U32, +code: U32, out: String) -> String:
  wr.u8.put.at(U32.is_eq(need, 0), U32.is_eq(need, 9), code, out)

# a sequence cut short at the end is U+FFFD
def wr.u8.end(done: Bool, out: String) -> String:
  match done:
    case True{}:
      out
    case False{}:
      SCon{Chr{65533}, out}

def wr.u8.state(+need: U32) -> U32:
  Bool.pick(U32, U32.is_eq(need, 9), 0, need)

def wr.u8.began(+n2: U32, +c2: U32, out: String) -> wr.U8:
  wr.U8{wr.u8.state(n2), c2, wr.u8.put(n2, c2, out)}

def wr.u8.lead.of(lc: U32 & U32, out: String) -> wr.U8:
  match lc:
    case (+n2, +c2):
      wr.u8.began(n2, c2, out)

def wr.u8.step.at(lead: Bool, cont: Bool, +need: U32, +code: U32, +b: U32, out: String) -> wr.U8:
  match lead cont:
    case True{} _:
      wr.u8.lead.of(wr.u8.lead(b), out)
    case False{} True{}:
      wr.U8{(need - 1 : U32), U32.or(U32.shln(code, 6n), U32.and(b, 63)), wr.u8.put((need - 1 : U32), U32.or(U32.shln(code, 6n), U32.and(b, 63)), out)}
    case False{} False{}:
      wr.u8.lead.of(wr.u8.lead(b), SCon{Chr{65533}, out})

def wr.u8.step(st: wr.U8, +b: U32) -> wr.U8:
  match st:
    case wr.U8{+need, +code, out}:
      wr.u8.step.at(U32.is_eq(need, 0), U32.is_eq(U32.and(b, 192), 128), need, code, b, out)

def wr.u8.fin(st: wr.U8) -> String:
  match st:
    case wr.U8{+need, code, out}:
      String.reverse(wr.u8.end(U32.is_eq(need, 0), out))

def wr.u8.go(bs: List<&2, U32>, st: wr.U8) -> String:
  match bs:
    case Nil{}:
      wr.u8.fin(st)
    case Con{+b, t}:
      wr.u8.go(t, wr.u8.step(st, b))

# bytes read as UTF-8
def wr.utf8(bs: List<&2, U32>) -> String:
  wr.u8.go(bs, wr.U8{0, 0, ""})

# The head read
# -------------

def wr.drop.cr.go(cs: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Con{Chr{13}, t}:
      t
    case _:
      cs

def wr.drop.cr(s: String) -> String:
  String.from_list(List.reverse(&2, Char, wr.drop.cr.go(List.reverse(&2, Char, String.to_list(s)))))

def wr.break.cons(+h: Char, m: Maybe<&2, wr.Two>) -> Maybe<&2, wr.Two>:
  match m:
    case None{}:
      None{}
    case Some{wr.Two{a, b}}:
      Some{wr.Two{SCon{h, a}, b}}

# s split at the first c: before, after (Nothing when no c)
def wr.break.at(hit: Bool, +h: Char, t: String, more: String -> Maybe<&2, wr.Two>) -> Maybe<&2, wr.Two>:
  match hit:
    case True{}:
      Some{wr.Two{"", t}}
    case False{}:
      wr.break.cons(h, more(t))

def wr.break(s: String, +c: U32) -> Maybe<&2, wr.Two>:
  match s:
    case SNil{}:
      None{}
    case SCon{Chr{+x}, +t}:
      wr.break.at(U32.is_eq(x, c), Chr{x}, t, r => wr.break(t, c))

def wr.header.got(m: Maybe<&2, wr.Two>) -> Maybe<&2, wr.H>:
  match m:
    case None{}:
      None{}
    case Some{wr.Two{n, v}}:
      Some{wr.H{String.to_lower(String.trim(n)), String.trim(v)}}

def wr.header.of(+line: String) -> Maybe<&2, wr.H>:
  wr.header.got(wr.break(line, 58))

def wr.opt.cons(m: Maybe<&2, wr.H>, rest: List<&2, wr.H>) -> List<&2, wr.H>:
  match m:
    case None{}:
      rest
    case Some{h}:
      h <> rest

def wr.headers(ls: List<&2, String>) -> List<&2, wr.H>:
  match ls:
    case Nil{}:
      []
    case Con{+l, t}:
      wr.opt.cons(wr.header.of(wr.drop.cr(l)), wr.headers(t))

# The request line's target: its path and its query ("" none)
def wr.target.got(+t: String, m: Maybe<&2, wr.Two>) -> wr.Two:
  match m:
    case None{}:
      wr.Two{t, ""}
    case Some{pq}:
      pq

def wr.target(+t: String) -> wr.Two:
  wr.target.got(t, wr.break(t, 63))

# A header's value ("" none: the first named so)
def wr.header(hs: List<&2, wr.H>, +name: String) -> String:
  match hs:
    case Nil{}:
      ""
    case Con{wr.H{+n, +v}, t}:
      wr.if(String, String.eq(n, name), u => v, u => wr.header(t, name))

def wr.has.header(hs: List<&2, wr.H>, +name: String) -> Bool:
  match hs:
    case Nil{}:
      False{}
    case Con{wr.H{+n, v}, t}:
      String.eq(n, name) || wr.has.header(t, name)

# how long its body says it is (0 when it does not say)
def wr.length(+hs: List<&2, wr.H>) -> U32:
  Maybe.default(&2, U32, U32.read(wr.header(hs, "content-length")), 0)

# %-decoding (and "+" as a space, as a query has it), to bytes
def wr.hexv.at(a: Bool, b: Bool, c2: Bool, d: Bool, e: Bool, f: Bool, +c: U32) -> Maybe<&2, U32>:
  match a b c2 d e f:
    case False{} True{} _ _ _ _:
      Some{(c - 48 : U32)}
    case False{} False{} False{} True{} _ _:
      Some{(c - 55 : U32)}
    case False{} False{} False{} False{} False{} True{}:
      Some{(c - 87 : U32)}
    case _ _ _ _ _ _:
      None{}

def wr.hexv(+c: U32) -> Maybe<&2, U32>:
  wr.hexv.at(U32.is_lt(c, 48), U32.is_lt(c, 58), U32.is_lt(c, 65), U32.is_lt(c, 71), U32.is_lt(c, 97), U32.is_lt(c, 103), c)

# A %-read so far: the bytes it lets out now, and where it is: 0 in plain
# text, 1 after a "%", 2 after a "%" and one more character (hi); plus: a
# "+" is a space.
type wr.P is Data:
  wr.P{out: List<&2, U32>, st: U32, hi: U32, plus: Bool}

# a character in plain text
def wr.pct.plain.at(pct: Bool, sp: Bool, +c: U32, out: List<&2, U32>, +plus: Bool) -> wr.P:
  match pct sp:
    case True{} _:
      wr.P{out, 1, 0, plus}
    case False{} True{}:
      wr.P{List.append(&2, U32, out, [32]), 0, 0, plus}
    case False{} False{}:
      wr.P{List.append(&2, U32, out, [c]), 0, 0, plus}

def wr.pct.plain(+c: U32, out: List<&2, U32>, +plus: Bool) -> wr.P:
  wr.pct.plain.at(U32.is_eq(c, 37), U32.is_eq(c, 43) && plus, c, out, plus)

# the second hex digit: the byte, or what came as it came
def wr.pct.pair(a: Maybe<&2, U32>, b: Maybe<&2, U32>, +hi: U32, +c: U32, +plus: Bool) -> wr.P:
  match a b:
    case Some{+x} Some{+y}:
      wr.P{[(x * 16 + y : U32)], 0, 0, plus}
    case _ _:
      wr.pct.plain(c, [37, hi], plus)

def wr.pct.step.at(zero: Bool, one: Bool, +hi: U32, +c: U32, +plus: Bool) -> wr.P:
  match zero one:
    case True{} _:
      wr.pct.plain(c, [], plus)
    case False{} True{}:
      wr.P{[], 2, c, plus}
    case False{} False{}:
      wr.pct.pair(wr.hexv(hi), wr.hexv(c), hi, c, plus)

def wr.pct.step(p: wr.P, +c: U32) -> wr.P:
  match p:
    case wr.P{out, +st, +hi, +plus}:
      wr.pct.step.at(U32.is_eq(st, 0), U32.is_eq(st, 1), hi, c, plus)

# what a read that ends now lets out still
def wr.pct.flush(p: wr.P) -> List<&2, U32>:
  match p:
    case wr.P{out, +st, +hi, plus}:
      Bool.pick(List<&2, U32>, U32.is_eq(st, 0), [], Bool.pick(List<&2, U32>, U32.is_eq(st, 1), [37], [37, hi]))

def wr.pct.emit(p: wr.P, k: wr.P -> List<&2, U32>) -> List<&2, U32>:
  match p:
    case wr.P{out, +st, +hi, +plus}:
      List.append(&2, U32, out, k(wr.P{[], st, hi, plus}))

def wr.pct.go(cs: List<&2, Char>, p: wr.P) -> List<&2, U32>:
  match cs:
    case Nil{}:
      wr.pct.flush(p)
    case Con{Chr{+c}, t}:
      wr.pct.emit(wr.pct.step(p, c), q => wr.pct.go(t, q))

# s %-decoded, then read as UTF-8
def wr.pct(+s: String, +plus: Bool) -> String:
  wr.utf8(wr.pct.go(String.to_list(s), wr.P{[], 0, 0, plus}))

# The path's segments
def wr.segs.tail(ss: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}:
      []
    case Con{h, t}:
      t

def wr.segs.fix(ss: List<&2, String>) -> List<&2, String>:
  match ss:
    case Con{SNil{}, Nil{}}:
      []
    case x:
      x

def wr.segs.dec(ss: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}:
      []
    case Con{+s, t}:
      wr.pct(s, False{}) <> wr.segs.dec(t)

def wr.segs(+p: String) -> List<&2, String>:
  wr.segs.dec(wr.segs.fix(wr.segs.tail(String.split(p, '/'))))

# The query's parameters
def wr.q.got(+kv: String, m: Maybe<&2, wr.Two>) -> wr.Q:
  match m:
    case None{}:
      wr.Q{wr.pct(kv, True{}), None{}}
    case Some{wr.Two{+k, +v}}:
      wr.Q{wr.pct(k, True{}), Some{wr.pct(v, True{})}}

def wr.q.one(empty: Bool, +kv: String, rest: List<&2, wr.Q>) -> List<&2, wr.Q>:
  match empty:
    case True{}:
      rest
    case False{}:
      wr.q.got(kv, wr.break(kv, 61)) <> rest

def wr.q.go(kvs: List<&2, String>) -> List<&2, wr.Q>:
  match kvs:
    case Nil{}:
      []
    case Con{+kv, t}:
      wr.q.one(String.eq(kv, ""), kv, wr.q.go(t))

def wr.query(+q: String) -> List<&2, wr.Q>:
  wr.q.go(String.split(q, '&'))

# a parameter's value: None when it is missing or has no "=" (as servant's
# QueryParam reads it)
def wr.param(qs: List<&2, wr.Q>, +name: String) -> Maybe<&2, String>:
  match qs:
    case Nil{}:
      None{}
    case Con{wr.Q{+k, v}, t}:
      wr.if(Maybe<&2, String>, String.eq(k, name), u => v, u => wr.param(t, name))

def wr.req.make(+m: String, +v: String, pq: wr.Two, hs: List<&2, wr.H>) -> Maybe<&2, wr.Req>:
  match pq:
    case wr.Two{+p, +q}:
      Some{wr.Req{m, v, wr.segs(p), p, wr.query(q), hs, [], ""}}

def wr.req.line(ws: List<&2, String>, hs: List<&2, wr.H>) -> Maybe<&2, wr.Req>:
  match ws:
    case [+m, +t, +v]:
      wr.req.make(m, v, wr.target(t), hs)
    case _:
      None{}

def wr.req.lines(ls: List<&2, String>) -> Maybe<&2, wr.Req>:
  match ls:
    case Nil{}:
      None{}
    case Con{first, rest}:
      wr.req.line(String.split(wr.drop.cr(first), ' '), wr.headers(rest))

# A head (its bytes, "\r\n\r\n" in): the request, body still empty, if it
# reads.
def wr.req(head: List<&2, U32>) -> Maybe<&2, wr.Req>:
  wr.req.lines(String.lines(wr.latin1(head)))

# the request with its body and peer
def wr.req.with(r: wr.Req, body: List<&2, U32>, peer: String) -> wr.Req:
  match r:
    case wr.Req{m, v, p, raw, q, hs, b, x}:
      wr.Req{m, v, p, raw, q, hs, body, peer}

# whether the connection stays open after this request: HTTP/1.1 unless it
# says Connection: close
def wr.keep(+v: String, +hs: List<&2, wr.H>) -> Bool:
  String.eq(v, "HTTP/1.1") && Bool.not(String.eq(String.to_lower(wr.header(hs, "connection")), "close"))

# The response written
# --------------------

def wr.reason.more.at(a: Bool, b: Bool, c: Bool, d: Bool, e: Bool) -> String:
  match a b c d e:
    case True{} _ _ _ _:
      "Method Not Allowed"
    case False{} True{} _ _ _:
      "Length Required"
    case False{} False{} True{} _ _:
      "Payload Too Large"
    case False{} False{} False{} True{} _:
      "Too Many Requests"
    case False{} False{} False{} False{} True{}:
      "Internal Server Error"
    case _ _ _ _ _:
      "Status"

def wr.reason.more(+s: U32) -> String:
  wr.reason.more.at(U32.is_eq(s, 405), U32.is_eq(s, 411), U32.is_eq(s, 413), U32.is_eq(s, 429), U32.is_eq(s, 500))

def wr.reason.at(a: Bool, b: Bool, c: Bool, d: Bool, e: Bool, f: Bool, +s: U32) -> String:
  match a b c d e f:
    case True{} _ _ _ _ _:
      "OK"
    case False{} True{} _ _ _ _:
      "No Content"
    case False{} False{} True{} _ _ _:
      "Found"
    case False{} False{} False{} True{} _ _:
      "Bad Request"
    case False{} False{} False{} False{} True{} _:
      "Unauthorized"
    case False{} False{} False{} False{} False{} True{}:
      "Not Found"
    case _ _ _ _ _ _:
      wr.reason.more(s)

def wr.reason(+s: U32) -> String:
  wr.reason.at(U32.is_eq(s, 200), U32.is_eq(s, 204), U32.is_eq(s, 302), U32.is_eq(s, 400), U32.is_eq(s, 401), U32.is_eq(s, 404), s)

def wr.body.len(b: wr.Body) -> wr.Body & U32:
  match b:
    case wr.Text{+s}:
      (wr.Text{s}, wr.utf8.len(s, 0))
    case wr.Bytes{+bs}:
      (wr.Bytes{bs}, U32.from_nat(List.length(&2, U32, bs)))
    case wr.File{p, o, +n}:
      (wr.File{p, o, n}, n)

def wr.headers.text(hs: List<&2, wr.H>) -> String:
  match hs:
    case Nil{}:
      ""
    case Con{wr.H{n, v}, t}:
      n ++ ": " ++ v ++ "\r\n" ++ wr.headers.text(t)

def wr.conn.line(keep: Bool) -> String:
  match keep:
    case True{}:
      ""
    case False{}:
      "Connection: close\r\n"

# the head of a response with a body of n bytes
def wr.head(+status: U32, hs: List<&2, wr.H>, +n: U32, keep: Bool) -> String:
  "HTTP/1.1 " ++ U32.show(status) ++ " " ++ wr.reason(status) ++ "\r\n" ++ wr.headers.text(hs)
    ++ "Content-Length: " ++ U32.show(n) ++ "\r\n" ++ wr.conn.line(keep) ++ "\r\n"

# Responses
# ---------

def wr.json(+status: U32, body: String) -> wr.Resp:
  wr.Resp{status, [wr.H{"Content-Type", "application/json;charset=utf-8"}], wr.Text{body}}

def wr.text(+status: U32, body: String) -> wr.Resp:
  wr.Resp{status, [wr.H{"Content-Type", "text/plain;charset=utf-8"}], wr.Text{body}}

def wr.with(r: wr.Resp, h: wr.H) -> wr.Resp:
  match r:
    case wr.Resp{s, hs, b}:
      wr.Resp{s, List.append(&2, wr.H, hs, [h]), b}

# Applications
# ------------

# An application: a request answered (it may read and change the world).
# A middleware: an application made from another.
def wr.App() -> Type:
  wr.Req -> IO(wr.Resp)

def wr.Mid() -> Type:
  wr.App() -> wr.App()

def wr.mid.id() -> wr.Mid():
  app => app

def wr.mid.then(f: wr.Mid(), g: wr.Mid()) -> wr.Mid():
  app => f(g(app))

# A request's parts
# -----------------

def wr.req.method(r: wr.Req) -> String:
  match r:
    case wr.Req{m, v, p, raw, q, hs, b, x}:
      m

def wr.req.path(r: wr.Req) -> List<&2, String>:
  match r:
    case wr.Req{m, v, p, raw, q, hs, b, x}:
      p

def wr.req.raw(r: wr.Req) -> String:
  match r:
    case wr.Req{m, v, p, raw, q, hs, b, x}:
      raw

def wr.req.query(r: wr.Req) -> List<&2, wr.Q>:
  match r:
    case wr.Req{m, v, p, raw, q, hs, b, x}:
      q

def wr.req.headers(r: wr.Req) -> List<&2, wr.H>:
  match r:
    case wr.Req{m, v, p, raw, q, hs, b, x}:
      hs

def wr.req.body(r: wr.Req) -> List<&2, U32>:
  match r:
    case wr.Req{m, v, p, raw, q, hs, b, x}:
      b

def wr.req.peer(r: wr.Req) -> String:
  match r:
    case wr.Req{m, v, p, raw, q, hs, b, x}:
      x

# A connection's bytes after a head: the body (its first n bytes, the
# Content-Length) and what follows it, the next request's
def wr.split.cons(+b: U32, p: List<&2, U32> & List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match p:
    case (xs, rest):
      (b <> xs, rest)

def wr.split(n: Nat, bs: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match n bs:
    case 0n rest:
      ([], rest)
    case 1n+p Nil{}:
      ([], [])
    case 1n+p Con{+b, t}:
      wr.split.cons(b, wr.split(p, t))
