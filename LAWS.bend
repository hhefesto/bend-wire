# Wire's laws: what a connection's bytes mean does not depend on how they
# come, and middlewares compose as functions do.

import Base
import ./Wire.bend as W

# Where a head ends does not depend on how its bytes were cut into pieces:
# the bytes fed after a cut are the cut of all of them. So the server, which
# feeds each piece TCP gives it as it comes, reads what the bytes, whole,
# mean.
law feed_cut:
  for bs: List<&2, U32>
  for rev: List<&2, U32>
  for +seen: U32
  for cs: List<&2, U32>
  {W.wr.feed(W.wr.cut(bs, rev, seen), cs) == W.wr.cut(List.append(&2, U32, bs, cs), rev, seen) : W.wr.Cut}

# A whole head is found whatever bytes follow it, and they are left as they
# are: on a kept-alive connection the next request's bytes, pipelined or
# not, are not touched by this one's reading.
law head_then:
  for h: List<&2, U32>
  for bs: List<&2, U32>
  for whole: {W.wr.cut(h, [], 0) == W.wr.Head{h, []} : W.wr.Cut}
  {W.wr.cut(List.append(&2, U32, h, bs), [], 0) == W.wr.Head{h, bs} : W.wr.Cut}

# The body is its Content-Length's bytes, and what follows it is the next
# request's, whatever it is.
law body_then:
  for body: List<&2, U32>
  for rest: List<&2, U32>
  {W.wr.split(List.length(&2, U32, body), List.append(&2, U32, body, rest)) == (body, rest) : List<&2, U32> & List<&2, U32>}

# Middlewares: the identity and composition, a monoid (on every application
# and request: functions are equal when they agree)
law mid_id_left:
  for m: W.wr.Mid()
  for app: W.wr.App()
  for r: W.wr.Req
  {W.wr.mid.then(W.wr.mid.id(), m)(app)(r) == m(app)(r) : IO(W.wr.Resp)}

law mid_id_right:
  for m: W.wr.Mid()
  for app: W.wr.App()
  for r: W.wr.Req
  {W.wr.mid.then(m, W.wr.mid.id())(app)(r) == m(app)(r) : IO(W.wr.Resp)}

law mid_assoc:
  for f: W.wr.Mid()
  for g: W.wr.Mid()
  for h: W.wr.Mid()
  for app: W.wr.App()
  for r: W.wr.Req
  {W.wr.mid.then(W.wr.mid.then(f, g), h)(app)(r) == W.wr.mid.then(f, W.wr.mid.then(g, h))(app)(r) : IO(W.wr.Resp)}
