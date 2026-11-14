import Base
import ../Wire.bend as W
import ../Serve.bend as S

# A server that answers {"signedIn":false} to every request: how fast the
# wire is, alone.   bend probe/Hello.bend -o hello && ./hello PORT

def hi.app(u: Unit, r: W.wr.Req) -> IO(W.wr.Resp):
  IO.pure(W.wr.Resp, W.wr.json(200, "{\"signedIn\":false}"))

def hi.listening(r: Result<&1, &1, U32 & String, Listener>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, "cannot listen")
    case Done{l}:
      do IO<Unit>:
        l2 : Listener <- S.wr.serve(~Unit, ~hi.app, 4000000000n, l, Unit{}, 4000000)
        return Unit{}

def hi.port(as: List<String>) -> U32:
  match as:
    case Con{p, Con{n, t}}:
      Maybe.default(&2, U32, U32.read(n), 3119)
    case x:
      3119

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    l : Result<&1, &1, U32 & String, Listener> <- TCP.listen("127.0.0.1", hi.port(as))
    hi.listening(l)
