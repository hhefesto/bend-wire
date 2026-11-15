import Base
import ./Wire.bend as W

# Serve: Wire's requests and responses on TCP (warp's job). A connection
# is a computation of its own (IO.spawn), so one that waits holds no other;
# on it, requests are read one after another (keep-alive, pipelined ones
# too: what follows a body is the next request's bytes), each answered by
# the application before the next is read.
#
# The one effect Base lacks (effs/wire.c) is the peer's address, so this
# file checks with SOME PROOFS FAIL; the laws are in files that import only
# Wire.bend.
#
# Every def is prefixed `wr.` (a program's defs share one namespace).

# the peer's address ("127.0.0.1"; an IPv4 one inside IPv6 as IPv4), "" none
def wr.peer(sock: Socket) -> IO(Socket & String):
  import "./effs/wire.c"

# Reading
# -------

def wr.s.fed(sock: Socket, c: W.wr.Cut, more: Socket -> W.wr.Cut -> IO(Socket & W.wr.Cut)) -> IO(Socket & W.wr.Cut):
  match c:
    case W.wr.More{rev, +seen}:
      more(sock, W.wr.More{rev, seen})
    case W.wr.Head{h, rest}:
      IO.pure(Socket & W.wr.Cut, (sock, W.wr.Head{h, rest}))

def wr.s.piece(sock: Socket, m: Maybe<&1, List<&2, U32>>, c: W.wr.Cut, more: Socket -> W.wr.Cut -> IO(Socket & W.wr.Cut)) -> IO(Socket & W.wr.Cut):
  match m:
    case None{}:
      IO.pure(Socket & W.wr.Cut, (sock, c))
    case Some{bs}:
      wr.s.fed(sock, W.wr.feed(c, bs), more)

def wr.s.got(r: Socket & Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, c: W.wr.Cut, more: Socket -> W.wr.Cut -> IO(Socket & W.wr.Cut)) -> IO(Socket & W.wr.Cut):
  match r:
    case (sock, Fail{e}):
      IO.pure(Socket & W.wr.Cut, (sock, c))
    case (sock, Done{m}):
      wr.s.piece(sock, m, c, more)

def wr.s.more(sock: Socket, c: W.wr.Cut, more: Socket -> W.wr.Cut -> IO(Socket & W.wr.Cut)) -> IO(Socket & W.wr.Cut):
  match c:
    case W.wr.Head{h, rest}:
      IO.pure(Socket & W.wr.Cut, (sock, W.wr.Head{h, rest}))
    case W.wr.More{rev, +seen}:
      do IO<Socket & W.wr.Cut>:
        r : Socket & Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>> <- TCP.recv_bytes(sock, 65536)
        wr.s.got(r, W.wr.More{rev, seen}, more)

# the head, in at most `fuel` pieces (a closed or failed connection ends the
# read where it is)
def wr.s.head(fuel: Nat, sock: Socket, c: W.wr.Cut) -> IO(Socket & W.wr.Cut):
  match fuel:
    case 0n:
      IO.pure(Socket & W.wr.Cut, (sock, c))
    case 1n+p:
      wr.s.more(sock, c, s => c2 => wr.s.head(p, s, c2))

# The body: `want` bytes, in pieces kept as they came (reversed) and
# counted, then joined once.
def wr.s.join(ps: List<&2, List<&2, U32>>, acc: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case Nil{}:
      acc
    case Con{p, t}:
      wr.s.join(t, List.append(&2, U32, p, acc))

def wr.s.len(bs: List<&2, U32>, +n: U32) -> U32:
  match bs:
    case Nil{}:
      n
    case Con{b, t}:
      wr.s.len(t, (n + 1 : U32))

def wr.s.body.piece(sock: Socket, m: Maybe<&1, List<&2, U32>>, +have: U32, ps: List<&2, List<&2, U32>>, more: Socket -> U32 -> List<&2, List<&2, U32>> -> IO(Socket & List<&2, U32>)) -> IO(Socket & List<&2, U32>):
  match m:
    case None{}:
      IO.pure(Socket & List<&2, U32>, (sock, wr.s.join(ps, [])))
    case Some{+bs}:
      more(sock, wr.s.len(bs, have), bs <> ps)

def wr.s.body.got(r: Socket & Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, +have: U32, ps: List<&2, List<&2, U32>>, more: Socket -> U32 -> List<&2, List<&2, U32>> -> IO(Socket & List<&2, U32>)) -> IO(Socket & List<&2, U32>):
  match r:
    case (sock, Fail{e}):
      IO.pure(Socket & List<&2, U32>, (sock, wr.s.join(ps, [])))
    case (sock, Done{m}):
      wr.s.body.piece(sock, m, have, ps, more)

def wr.s.body.at(enough: Bool, sock: Socket, +have: U32, ps: List<&2, List<&2, U32>>, more: Socket -> U32 -> List<&2, List<&2, U32>> -> IO(Socket & List<&2, U32>)) -> IO(Socket & List<&2, U32>):
  match enough:
    case True{}:
      IO.pure(Socket & List<&2, U32>, (sock, wr.s.join(ps, [])))
    case False{}:
      do IO<Socket & List<&2, U32>>:
        r : Socket & Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>> <- TCP.recv_bytes(sock, 65536)
        wr.s.body.got(r, have, ps, more)

def wr.s.body(fuel: Nat, sock: Socket, +want: U32, +have: U32, ps: List<&2, List<&2, U32>>) -> IO(Socket & List<&2, U32>):
  match fuel:
    case 0n:
      IO.pure(Socket & List<&2, U32>, (sock, wr.s.join(ps, [])))
    case 1n+p:
      wr.s.body.at(U32.is_ge(have, want), sock, have, ps, s => h => qs => wr.s.body(p, s, want, h, qs))

# Writing
# -------

def wr.s.sock(r: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>) -> Socket:
  match r:
    case (s, x):
      s

def wr.s.file.sent(r: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>, f: File, more: Socket -> File -> IO(Socket & File)) -> IO(Socket & File):
  match r:
    case (s, Done{u}):
      more(s, f)
    case (s, Fail{e}):
      IO.pure(Socket & File, (s, f))

def wr.s.file.bytes(sock: Socket, f: File, bs: List<&2, U32>, more: Socket -> File -> IO(Socket & File)) -> IO(Socket & File):
  match bs:
    case Nil{}:
      IO.pure(Socket & File, (sock, f))
    case Con{b, t}:
      do IO<Socket & File>:
        r : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send_bytes(sock, b <> t)
        wr.s.file.sent(r, f, more)

def wr.s.file.got(sock: Socket, r: File & Result<&1, &1, U32 & String, List<&2, U32>>, more: Socket -> File -> IO(Socket & File)) -> IO(Socket & File):
  match r:
    case (f, Fail{e}):
      IO.pure(Socket & File, (sock, f))
    case (f, Done{bs}):
      wr.s.file.bytes(sock, f, bs, more)

def wr.s.file.more(done: Bool, sock: Socket, f: File, +off: U32, +left: U32, more: Socket -> File -> IO(Socket & File)) -> IO(Socket & File):
  match done:
    case True{}:
      IO.pure(Socket & File, (sock, f))
    case False{}:
      do IO<Socket & File>:
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(f, off, U32.min(left, 65536))
        wr.s.file.got(sock, r, more)

# `left` bytes of a file from `off`, sent in pieces of 64 KB
def wr.s.file.piece(fuel: Nat, sock: Socket, f: File, +off: U32, +left: U32) -> IO(Socket & File):
  match fuel:
    case 0n:
      IO.pure(Socket & File, (sock, f))
    case 1n+p:
      wr.s.file.more(U32.is_eq(left, 0), sock, f, off, left,
        s => g => wr.s.file.piece(p, s, g, (off + U32.min(left, 65536) : U32), (left - U32.min(left, 65536) : U32)))

def wr.s.file.close(r: Socket & File) -> IO(Socket):
  match r:
    case (s, f):
      do IO<Socket>:
        File.close(f)
        return s

def wr.s.file.open(sock: Socket, +off: U32, +n: U32, r: Result<&1, &1, U32 & String, File>) -> IO(Socket):
  match r:
    case Fail{e}:
      IO.pure(Socket, sock)
    case Done{f}:
      do IO<Socket>:
        r2 : Socket & File <- wr.s.file.piece(65536n, sock, f, off, n)
        wr.s.file.close(r2)

# The head and a file's first piece go out in one write, so the head is not
# a small segment alone: Nagle's algorithm holds the next write's last
# segment until the head is acknowledged, and the peer's delayed ACK waits
# about 40 ms (TCP_NODELAY would need a call Base lacks).
def wr.s.file.head(sock: Socket, +head: String, +off: U32, +n: U32, r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Socket):
  match r:
    case (f, Fail{e}):
      do IO<Socket>:
        s : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send(sock, head)
        wr.s.file.close((wr.s.sock(s), f))
    case (f, Done{bs}):
      do IO<Socket>:
        s : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send_bytes(sock, List.append(&2, U32, W.wr.utf8.of(head), bs))
        r2 : Socket & File <- wr.s.file.piece(65536n, wr.s.sock(s), f, (off + U32.min(n, 65536) : U32), (n - U32.min(n, 65536) : U32))
        wr.s.file.close(r2)

def wr.s.file.first(sock: Socket, +head: String, +off: U32, +n: U32, r: Result<&1, &1, U32 & String, File>) -> IO(Socket):
  match r:
    case Fail{e}:
      do IO<Socket>:
        s : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send(sock, head)
        return wr.s.sock(s)
    case Done{f}:
      do IO<Socket>:
        r2 : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(f, off, U32.min(n, 65536))
        wr.s.file.head(sock, head, off, n, r2)

def wr.s.parts(sock: Socket, +head: String, bare: Bool, b: W.wr.Body) -> IO(Socket):
  match bare b:
    case True{} x:
      do IO<Socket>:
        r : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send(sock, head)
        return wr.s.sock(r)
    case False{} W.wr.Text{s}:
      do IO<Socket>:
        r : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send(sock, head ++ s)
        return wr.s.sock(r)
    case False{} W.wr.Bytes{bs}:
      do IO<Socket>:
        r : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send_bytes(sock, List.append(&2, U32, W.wr.utf8.of(head), bs))
        return wr.s.sock(r)
    case False{} W.wr.File{path, +off, +n}:
      do IO<Socket>:
        f : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        wr.s.file.first(sock, head, off, n, f)

def wr.s.sized(sock: Socket, +st: U32, hs: List<&2, W.wr.H>, bn: W.wr.Body & U32, +keep: Bool, bare: Bool) -> IO(Socket):
  match bn:
    case (b, +n):
      wr.s.parts(sock, W.wr.head(st, hs, n, keep), bare, b)

# a response sent (bare: its head only, as to HEAD)
def wr.s.send(sock: Socket, r: W.wr.Resp, +keep: Bool, bare: Bool) -> IO(Socket):
  match r:
    case W.wr.Resp{+st, hs, b}:
      wr.s.sized(sock, st, hs, W.wr.body.len(b), keep, bare)

# A connection
# ------------

def wr.s.answered(sock: Socket, r: W.wr.Resp, +keep: Bool, +bare: Bool, rest: List<&2, U32>, more: Socket -> W.wr.Cut -> IO(Socket)) -> IO(Socket):
  match keep:
    case True{}:
      do IO<Socket>:
        s : Socket <- wr.s.send(sock, r, True{}, bare)
        more(s, W.wr.cut(rest, [], 0))
    case False{}:
      wr.s.send(sock, r, False{}, bare)

def wr.s.split.then(~E: Data, ~app: E -> W.wr.Req -> IO(W.wr.Resp), ~pre: E -> W.wr.Req -> Maybe<&2, W.wr.Resp>, +env: E, req: W.wr.Req, +peer: String, sock: Socket, +keep: Bool, +bare: Bool, br: List<&2, U32> & List<&2, U32>, more: Socket -> W.wr.Cut -> IO(Socket)) -> IO(Socket):
  match br:
    case (body, rest):
      do IO<Socket>:
        resp : W.wr.Resp <- app(env, W.wr.req.with(req, body, peer))
        wr.s.answered(sock, resp, keep, bare, rest, more)

def wr.s.bodied(~E: Data, ~app: E -> W.wr.Req -> IO(W.wr.Resp), ~pre: E -> W.wr.Req -> Maybe<&2, W.wr.Resp>, +env: E, req: W.wr.Req, +want: U32, +peer: String, r: Socket & List<&2, U32>, more: Socket -> W.wr.Cut -> IO(Socket)) -> IO(Socket):
  match req r:
    case W.wr.Req{+m, +v, +p, +raw, +q, +hs, +b, +x} Tuple{sock, bs}:
      wr.s.split.then(~E, ~app, ~pre, env, W.wr.Req{m, v, p, raw, q, hs, b, x}, peer, sock, W.wr.keep(v, hs), String.eq(m, "HEAD"), W.wr.split(U32.to_nat(want), bs), more)

def wr.s.toolong(sock: Socket) -> IO(Socket):
  wr.s.send(sock, W.wr.json(413, "{\"replyOk\":false,\"replySays\":\"it is too large\"}"), False{}, False{})

def wr.s.reqlen(+req: W.wr.Req) -> U32:
  match req:
    case W.wr.Req{m, v, p, raw, q, +hs, b, x}:
      W.wr.length(hs)

def wr.s.read.at(~E: Data, ~app: E -> W.wr.Req -> IO(W.wr.Resp), ~pre: E -> W.wr.Req -> Maybe<&2, W.wr.Resp>, big: Bool, +env: E, +peer: String, sock: Socket, +req: W.wr.Req, +want: U32, +rest: List<&2, U32>, more: Socket -> W.wr.Cut -> IO(Socket)) -> IO(Socket):
  match big:
    case True{}:
      wr.s.toolong(sock)
    case False{}:
      do IO<Socket>:
        r : Socket & List<&2, U32> <- wr.s.body(4096n, sock, want, wr.s.len(rest, 0), [rest])
        wr.s.bodied(~E, ~app, ~pre, env, req, want, peer, r, more)

# answered before its body is read (the application's `pre` said so: a
# refusal, as a middleware that will not read a body), then the connection
# ends, since the body was never read
def wr.s.read.pre(~E: Data, ~app: E -> W.wr.Req -> IO(W.wr.Resp), ~pre: E -> W.wr.Req -> Maybe<&2, W.wr.Resp>, m: Maybe<&2, W.wr.Resp>, +env: E, +max: U32, +peer: String, sock: Socket, +req: W.wr.Req, +want: U32, +rest: List<&2, U32>, more: Socket -> W.wr.Cut -> IO(Socket)) -> IO(Socket):
  match m:
    case Some{r}:
      wr.s.send(sock, r, False{}, String.eq(W.wr.req.method(req), "HEAD"))
    case None{}:
      wr.s.read.at(~E, ~app, ~pre, U32.is_gt(want, max), env, peer, sock, req, want, rest, more)

def wr.s.read.len(~E: Data, ~app: E -> W.wr.Req -> IO(W.wr.Resp), ~pre: E -> W.wr.Req -> Maybe<&2, W.wr.Resp>, +env: E, +max: U32, +peer: String, sock: Socket, +req: W.wr.Req, +want: U32, +rest: List<&2, U32>, more: Socket -> W.wr.Cut -> IO(Socket)) -> IO(Socket):
  wr.s.read.pre(~E, ~app, ~pre, pre(env, req), env, max, peer, sock, req, want, rest, more)

def wr.s.read(~E: Data, ~app: E -> W.wr.Req -> IO(W.wr.Resp), ~pre: E -> W.wr.Req -> Maybe<&2, W.wr.Resp>, +env: E, +max: U32, +peer: String, sock: Socket, m: Maybe<&2, W.wr.Req>, +rest: List<&2, U32>, more: Socket -> W.wr.Cut -> IO(Socket)) -> IO(Socket):
  match m:
    case None{}:
      wr.s.send(sock, W.wr.text(400, "that is no request"), False{}, False{})
    case Some{+req}:
      wr.s.read.len(~E, ~app, ~pre, env, max, peer, sock, req, wr.s.reqlen(req), rest, more)

def wr.s.headed(~E: Data, ~app: E -> W.wr.Req -> IO(W.wr.Resp), ~pre: E -> W.wr.Req -> Maybe<&2, W.wr.Resp>, +env: E, +max: U32, +peer: String, r: Socket & W.wr.Cut, more: Socket -> W.wr.Cut -> IO(Socket)) -> IO(Socket):
  match r:
    case (sock, W.wr.More{rev, seen}):
      IO.pure(Socket, sock)
    case (sock, W.wr.Head{+h, +rest}):
      wr.s.read(~E, ~app, ~pre, env, max, peer, sock, W.wr.req(h), rest, more)

# the requests of a connection, at most `fuel` of them
def wr.s.conn(~E: Data, ~app: E -> W.wr.Req -> IO(W.wr.Resp), ~pre: E -> W.wr.Req -> Maybe<&2, W.wr.Resp>, fuel: Nat, sock: Socket, c: W.wr.Cut, +env: E, +max: U32, +peer: String) -> IO(Socket):
  match fuel:
    case 0n:
      IO.pure(Socket, sock)
    case 1n+p:
      do IO<Socket>:
        r : Socket & W.wr.Cut <- wr.s.head(64n, sock, c)
        wr.s.headed(~E, ~app, ~pre, env, max, peer, r, s => c2 => wr.s.conn(~E, ~app, ~pre, p, s, c2, env, max, peer))

def wr.s.peered(~E: Data, ~app: E -> W.wr.Req -> IO(W.wr.Resp), ~pre: E -> W.wr.Req -> Maybe<&2, W.wr.Resp>, +env: E, +max: U32, r: Socket & String) -> IO(Unit):
  match r:
    case (sock, +peer):
      do IO<Unit>:
        s : Socket <- wr.s.conn(~E, ~app, ~pre, 1000000n, sock, W.wr.More{[], 0}, env, max, peer)
        Socket.close(s)

def wr.s.one(~E: Data, ~app: E -> W.wr.Req -> IO(W.wr.Resp), ~pre: E -> W.wr.Req -> Maybe<&2, W.wr.Resp>, +env: E, +max: U32, sock: Socket) -> IO(Unit):
  do IO<Unit>:
    r : Socket & String <- wr.peer(sock)
    wr.s.peered(~E, ~app, ~pre, env, max, r)

# The listener
# ------------

def wr.s.accepted(~E: Data, ~app: E -> W.wr.Req -> IO(W.wr.Resp), ~pre: E -> W.wr.Req -> Maybe<&2, W.wr.Resp>, l: Listener, +env: E, +max: U32, r: Result<&1, &1, U32 & String, Socket>, more: Listener -> IO(Listener)) -> IO(Listener):
  match r:
    case Fail{e}:
      more(l)
    case Done{sock}:
      do IO<Listener>:
        IO.spawn(Unit, wr.s.one(~E, ~app, ~pre, env, max, sock))
        more(l)

def wr.s.accept(~E: Data, ~app: E -> W.wr.Req -> IO(W.wr.Resp), ~pre: E -> W.wr.Req -> Maybe<&2, W.wr.Resp>, r: Listener & Result<&1, &1, U32 & String, Socket>, +env: E, +max: U32, more: Listener -> IO(Listener)) -> IO(Listener):
  match r:
    case (l, res):
      wr.s.accepted(~E, ~app, ~pre, l, env, max, res, more)

# connections, one after another, `fuel` of them (Bend's loops end; a
# server's counts down what the world sends it); max: the longest body read;
# pre: what the application answers to a request before its body is read
# (None: read it, then ask app)
def wr.serve(~E: Data, ~app: E -> W.wr.Req -> IO(W.wr.Resp), ~pre: E -> W.wr.Req -> Maybe<&2, W.wr.Resp>, fuel: Nat, l: Listener, +env: E, +max: U32) -> IO(Listener):
  match fuel:
    case 0n:
      IO.pure(Listener, l)
    case 1n+p:
      do IO<Listener>:
        r : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(l)
        wr.s.accept(~E, ~app, ~pre, r, env, max, l2 => wr.serve(~E, ~app, ~pre, p, l2, env, max))
