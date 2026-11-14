// wire's system calls
// ===================
//
// What serving needs that Base lacks: who is at the other end of a socket
// (getpeername(2)). wr.peer(sock) means the peer's address as text
// ("127.0.0.1", "fd7a::1"; an IPv4 one inside IPv6 as IPv4), "" when it has
// none; the socket is handed back.

#include <arpa/inet.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>

#ifdef CID(wr.peer)
Term wr_peer_run(Env e, Term* f, IoWork* w) {
  int                     fd = (int)io_hand_v(f[0]);
  struct sockaddr_storage sa;
  socklen_t               sl = sizeof(sa);
  char                    out[INET6_ADDRSTRLEN + 1];
  out[0]                     = 0;
  if (getpeername(fd, (struct sockaddr*)&sa, &sl) == 0) {
    if (sa.ss_family == AF_INET) {
      inet_ntop(AF_INET, &((struct sockaddr_in*)&sa)->sin_addr, out, sizeof(out));
    } else if (sa.ss_family == AF_INET6) {
      struct in6_addr* a = &((struct sockaddr_in6*)&sa)->sin6_addr;
      if (IN6_IS_ADDR_V4MAPPED(a)) {
        inet_ntop(AF_INET, &a->s6_addr[12], out, sizeof(out));
      } else {
        inet_ntop(AF_INET6, a, out, sizeof(out));
      }
    }
  }
  return io_tup(e, io_hand(fd), io_str(e, out, strlen(out)));
}

static void __attribute__((constructor)) wr_peer_use(void) {
  io_eff(CID(wr.peer), wr_peer_run);
}
#endif
