# wire: HTTP/1.1 in Bend (http-types, wai, warp)

**What it means.** A request is its head (method, version, target, headers)
and its body; a response is a status, headers and a body. An application
means a function from requests to responses (`wr.App() = wr.Req ->
IO(wr.Resp)`); a middleware a function from applications to applications
(`wr.Mid()`), and middlewares compose as functions (`wr.mid.then`, identity
`wr.mid.id`). A connection means the sequence of requests its bytes are,
each answered as if alone.

**The machine.** `wr.cut` finds where a head ends one byte at a time, fed
pieces as TCP gives them (`wr.feed`); `wr.req` reads the head (wai's
`pathInfo`, %-decoding, query parameters as servant reads them);
`wr.split` takes the body by its Content-Length and leaves the rest for the
next request. `Serve.bend` runs it: a computation per connection
(`IO.spawn`), requests read one after another on it (keep-alive, pipelined
ones too), each answered before the next is read; responses carry
Content-Length (and `Connection: close` when the request asked for it or
was HTTP/1.0); before a body is read the application may answer instead
(`pre`: a refusal, as Api.hs's bodyLimit middleware), and the connection
then ends; a body is text, bytes, or a range of a file sent in 64 KB
pieces; HEAD gets the head only.

**Laws** (`LAWS.bend`, proved in `PROOF.bend`, `--verdict` too):

- `feed_cut`: bytes fed in pieces are cut as when fed whole.
- `head_then`: a whole head is found whatever follows it, and what follows
  is left untouched (the next request's bytes on a kept-alive connection).
- `body_then`: the body is its Content-Length's bytes and what follows is the
  next request's.
- `mid_id_left`, `mid_id_right`, `mid_assoc`: middlewares form a monoid.

Mutants (`../mutants.sh wire`): feed-forgets-seen, feed-drops-rest,
body-eats-next, id-answers-500, then-not-assoc, each caught.

**Outside Bend**: `effs/wire.c`, one call, getpeername(2) (`wr.peer`: Base
has no way to ask who is at the other end of a socket). `Serve.bend` uses
it, so it checks with SOME PROOFS FAIL; the laws import only `Wire.bend`.
