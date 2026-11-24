# ft_traceroute — how it works

`ft_traceroute` re-implements the mandatory part of `traceroute`:

- a single argument: an IPv4 address or a hostname (FQDN), resolved **once**;
- hops are displayed as raw IPv4 addresses (**no reverse DNS**), exactly like `traceroute -n`;
- the only option is `--help`;
- sockets stay in **blocking** mode (no `O_NONBLOCK`), waiting is done with `select()`;
- only the libc is used.

```
make
sudo ./ft_traceroute google.com
```

Root is required because the program opens a raw ICMP socket.

---

## 1. The idea behind traceroute

Every IP packet carries a **TTL** (Time To Live). Each router decrements it;
when it reaches 0 the router drops the packet and sends back an
**ICMP Time Exceeded** message, whose source address is the router itself.

So:

1. send a packet with TTL = 1 → the 1st router answers "Time Exceeded";
2. send a packet with TTL = 2 → the 2nd router answers;
3. ... and so on.

We send **UDP** datagrams to an *unlikely* port (33434 and up). When a probe
finally reaches the destination host, nothing listens on that port, so the host
answers **ICMP Destination Unreachable / Port Unreachable**: that tells us we
have arrived and can stop.

Each ICMP error message contains a copy of the IP header + the first 8 bytes
(the UDP header) of the packet that caused it. That is how we know which
of our probes an answer belongs to:

```
received on the raw socket:
[ outer IP header ][ ICMP header (8 B) ][ inner IP header ][ inner UDP header ]
                                          ^ copy of OUR probe
```

- inner protocol == UDP;
- inner UDP source port == our bound port → it's from *this* process
  (several traceroutes can run in parallel);
- inner UDP destination port → identifies exactly which probe (hop + try).

## 2. Design choices

| Choice | What we did | Why |
|---|---|---|
| Probe type | UDP datagrams + raw ICMP socket to listen | Default behaviour of the real traceroute; the most common approach in 42 projects; easy to explain. |
| Timing | **Per-hop batch**: the 3 probes of a hop are sent together, then replies are collected with `select()` for up to 5 s | Every probe has its own timestamp, so RTTs stay accurate (well within the 30 ms tolerance); a silent hop costs 5 s instead of 15 s. |
| No `O_NONBLOCK` | `select()` tells us when the raw socket is readable, then a blocking `recvfrom()` returns immediately | Respects the subject. |
| Probe identification | One unique destination port per probe: `33434 + (ttl-1)*3 + i` | Unambiguous matching of replies, even late ones. |
| Output | `traceroute to HOST (IP), 30 hops max, 60 byte packets` / `%2d ` + ` IP  x.xxx ms` | Same format/indentation as the real traceroute (with `-n`, since no reverse DNS is allowed). |

Default values (from `includes/ft_traceroute.h`):

| Macro | Value | Meaning |
|---|---|---|
| `MAX_HOPS` | 30 | maximum TTL |
| `NPROBES` | 3 | probes per hop |
| `WAIT_SEC` | 5.0 | max wait per hop (seconds) |
| `BASE_PORT` | 33434 | first UDP destination port |
| `PACKET_LEN` | 60 | full packet size: 20 (IP) + 8 (UDP) + 32 (payload) |

## 3. Data structures (`includes/ft_traceroute.h`)

### `t_probe` — one UDP datagram and its answer
| Field | Meaning |
|---|---|
| `port` | UDP destination port used, unique per probe |
| `sent` / `recv` | timestamps of `sendto()` and of the reply reception |
| `received` | 1 if a matching ICMP reply arrived |
| `from` | address of the host that answered (router or destination) |
| `icmp_type` / `icmp_code` | type/code of the answer (Time Exceeded, Unreachable…) |

### `t_trace` — state of the whole run
| Field | Meaning |
|---|---|
| `host` | argument given by the user |
| `ip_str` | resolved IPv4 as text |
| `dst` | resolved destination (`sockaddr_in`) |
| `udp_fd` | socket used to send probes |
| `icmp_fd` | raw socket used to receive ICMP errors |
| `src_port` | local UDP port (identifies our process' probes) |
| `max_hops`, `nprobes`, `wait` | runtime parameters |

## 4. Program flow

```
main
 ├─ parse_args        → --help / errors / host
 ├─ resolve_host      → getaddrinfo (once)
 ├─ open_sockets      → raw ICMP + UDP (bound)
 ├─ run_traceroute
 │    ├─ print_header
 │    └─ for ttl = 1..30:
 │         trace_hop
 │          ├─ send_probe ×3        (setsockopt IP_TTL, sendto)
 │          ├─ receive_replies      (select + recvfrom until 3 replies or 5 s)
 │          │    └─ read_one → parse_icmp → match_probe
 │          ├─ print_hop
 │          └─ hop_is_final ? stop
 └─ close_sockets
```

## 5. Function reference

### `src/main.c`

#### `int main(int argc, char **argv)`
Entry point. Initialises a `t_trace` with default values (sockets set to `-1`
so they can be closed safely), then calls, in order: `parse_args`,
`resolve_host`, `open_sockets`, `run_traceroute`, `close_sockets`.
Returns `0` on success, `2` on argument/resolution/socket errors (like the
real traceroute), `1` on a runtime error.

### `src/args.c`

#### `void print_usage(FILE *out)`
Prints the usage text (same layout as the real `traceroute --help`) to `out`.
Like the real traceroute, it is always called with `stderr`.

#### `int parse_args(int argc, char **argv, t_trace *tr)`
Parses the command line.
- No argument → usage on stderr, returns `-1` (main exits with `0`).
- `--help` anywhere → usage on stderr, returns `-1` (main exits with `0`).

  (This is exactly what the real traceroute does — checked by `make test`.)
- Any other argument starting with `-` → `Bad option` error, returns `2`.
- More than one host → `Extra arg` error, returns `2`.
- Otherwise stores the host in `tr->host` and returns `0`.

### `src/resolve.c`

#### `int resolve_host(t_trace *tr)`
Turns the argument (IPv4 like `8.8.8.8` *or* FQDN like `google.com`) into a
`struct sockaddr_in` with `getaddrinfo()` restricted to `AF_INET`.
This is the **only** DNS operation of the program — hops are never
reverse-resolved. Stores the result in `tr->dst` and its text form
(`inet_ntop`) in `tr->ip_str` for the header line. On failure prints the same
messages as the real traceroute (`Name or service not known` …).

### `src/socket.c`

#### `int open_sockets(t_trace *tr)`
Creates the two sockets:
- `socket(AF_INET, SOCK_RAW, IPPROTO_ICMP)`: receives **every** ICMP packet
  reaching the machine (needs root / `CAP_NET_RAW`; a clear message is printed
  on `EPERM`);
- `socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)`: sends the probes; the kernel
  builds the IP and UDP headers for us.

Then calls `bind_udp_socket`.

#### `static int bind_udp_socket(t_trace *tr)`
Binds the UDP socket to port `0` (the kernel picks a free port), then reads it
back with `getsockname()` into `tr->src_port`. Because every probe leaves from
this port, any ICMP error quoting another source port belongs to someone
else and is ignored.

#### `void close_sockets(t_trace *tr)`
Closes both sockets if they are open and resets them to `-1`.

### `src/send.c`

#### `int send_probe(t_trace *tr, t_probe *probe, int ttl)`
Sends one probe:
1. `setsockopt(IP_TTL, ttl)` — the heart of traceroute;
2. fills a 32-byte payload (so the full packet is 60 bytes, as announced);
3. records `probe->sent` with `gettimeofday()` right before sending;
4. `sendto()` the target on port `probe->port`.

### `src/receive.c`

#### `int receive_replies(t_trace *tr, t_probe *probes, int count, struct timeval *deadline)`
Waits for the answers of one hop. Loop while some probes are still pending
and the deadline is not reached:
- compute the remaining time (`time_remaining`);
- `select()` on the raw socket with that timeout;
- timeout → stop (remaining probes will print as `*`);
- readable → `read_one`, and decrement the pending counter if a probe was
  matched.

`EINTR` is retried. Because `select()` guarantees data is available,
`recvfrom()` never blocks even though the socket is in blocking mode.

#### `static int read_one(t_trace *tr, t_probe *probes, int count)`
Reads one packet with `recvfrom()` and immediately takes the reception
timestamp (accurate RTT). Passes the packet to `parse_icmp`; if it is one of
ours, gives it to `match_probe`. Returns `1` if a probe got its answer,
`0` if the packet was ignored, `-1` on error.

#### `static int parse_icmp(t_trace *tr, char *buf, ssize_t len, struct icmp **icmp_out)`
Validates and decodes a raw packet:
1. skips the outer IP header (`ip_hl * 4` bytes — it may contain options);
2. keeps only ICMP **Time Exceeded (in transit)** and **Destination
   Unreachable**; everything else (ping replies, etc.) is dropped;
3. checks the length at each step so we never read past the buffer;
4. reads the quoted inner IP header: protocol must be UDP;
5. reads the quoted UDP header: source port must be `tr->src_port`.

The quoted destination address is deliberately **not** compared with the
target: the kernel can rewrite it (tracing `0.0.0.0` actually sends to
`127.0.0.1`). The bound source port is already unique to our process.

Returns the quoted UDP destination port (which identifies the probe) and
sets `*icmp_out`, or `-1` if the packet is not for us.

#### `static int match_probe(t_probe *probes, int count, int port, struct icmp *icmp, struct sockaddr_in *from, struct timeval *now)`
Finds the probe of the current hop whose `port` matches and that has not been
answered yet. Fills `received`, `recv`, `from`, `icmp_type`, `icmp_code`.
Late answers from a previous hop have a port that doesn't belong to the
current hop, so they are naturally ignored.

### `src/trace.c`

#### `int run_traceroute(t_trace *tr)`
Prints the header then traces hop after hop, TTL `1` to `max_hops`. Stops
early when `trace_hop` reports the trace is finished. Returns `0`, or `1` on
a send/receive error.

#### `static int trace_hop(t_trace *tr, int ttl, t_probe *probes)`
Handles one line of output:
1. resets the probes and assigns each a unique port
   `BASE_PORT + (ttl-1)*nprobes + i`;
2. sends the 3 probes (`send_probe`);
3. sets a deadline = now + `WAIT_SEC` and collects the replies
   (`receive_replies`);
4. prints the line (`print_hop`).

Returns `1` if this was the last hop, `0` to continue, `-1` on error.

#### `static int hop_is_final(const t_probe *probes, int count)`
Returns `1` if any probe got an **ICMP Destination Unreachable**:
- *port unreachable* → we reached the destination;
- other codes (`!H`, `!N`, `!P`, …) → the destination can't be reached,
  going further is useless.

### `src/print.c`

#### `void print_header(const t_trace *tr)`
Prints `traceroute to <host> (<ip>), 30 hops max, 60 byte packets`.

#### `void print_hop(int ttl, const t_probe *probes, int count)`
Prints one hop line with the exact spacing of the real traceroute:
```
 1  192.168.1.1  0.512 ms  0.480 ms  0.470 ms
 2  10.0.0.1  3.210 ms 10.0.0.9  3.400 ms  3.300 ms
 3  * * *
```
- `%2d ` for the hop number;
- the answering IP is printed only when it differs from the previous answer of
  the same line (load-balanced routes show several IPs);
- `  x.xxx ms` for each answer, ` *` for each timeout;
- followed by `print_annotation`.

`fflush(stdout)` makes each line appear immediately even when piped.

#### `static void print_annotation(const t_probe *p)`
For Destination Unreachable answers other than *port unreachable*, prints the
same flags as traceroute: `!N` (network), `!H` (host), `!P` (protocol),
`!F` (fragmentation needed), `!S` (source route), `!X` (administratively
prohibited), `!V`, `!C`, or `!<code>`.

### `src/time.c`

#### `double time_diff_ms(const struct timeval *start, const struct timeval *end)`
Returns `end - start` in milliseconds (with microsecond precision) — the RTT.

#### `void time_add(struct timeval *tv, double seconds)`
Adds a duration to a `timeval`, normalising microseconds. Used to compute the
per-hop deadline.

#### `int time_remaining(const struct timeval *deadline, struct timeval *out)`
Stores `deadline - now` in `*out` (the `select()` timeout). Returns `0` when the
deadline has passed. Recomputing it on every loop turn means that ignored
packets (someone else's pings…) never extend the waiting time.

## 6. Makefile

Standard rules: `all`, `clean`, `fclean`, `re`, compiled with
`-Wall -Wextra -Werror`. Objects go to `obj/`, and each object also depends
on the header, so editing it triggers a rebuild.

Extra rule: `test` (see below).

## 7. Tests: `make test`

```
make test                          # all quick tests (asks for sudo for the live part)
make test SLOW=1                   # + unreachable host traced up to 30 hops (~3 min)
make test TARGETS="8.8.8.8 42.fr"  # choose the live targets
make test TOL=10                   # stricter RTT tolerance (default 30 ms)
```

The script is `tests/run_tests.sh`. It never runs inside `ft_traceroute` —
the real `traceroute` (Linux traceroute 2.x) is only called by the test script
as a reference. It is run as `traceroute -4 -n`, because the subject asks for
IPv4 only and no DNS resolution on the hops. Each test prints `PASS`, `FAIL`,
`WARN` (difference that can be caused by the network itself) or `SKIP`; the
rule fails if any test fails.

### Where the tests come from

From the **subject**:

| Subject requirement | Test |
|---|---|
| executable `ft_traceroute`, Makefile with the usual rules | binary exists, rules `all clean fclean re $(NAME)`, no relink, `-Wall -Wextra -Werror` |
| only option `--help` | `--help` (alone, before/after a host) gives the same usage behaviour as the real traceroute; unknown options (`-x`, `-y`, `--foo`) give the same error |
| simple IPv4 address/hostname as parameter | IPv4 (`127.0.0.1`, `8.8.8.8`, `1.1.1.1`, local IP), FQDN (`localhost`, `google.com`, `www.42.fr`) |
| FQDN without DNS resolution in the hop display | hop lines must contain IPs only; sources must not use `getnameinfo`/`gethostbyaddr` |
| 30 ms tolerance per hop | for every hop answered by the same router in both programs, the min RTT must differ by ≤ 30 ms |
| no `O_NONBLOCK` | static grep for `O_NONBLOCK`/`SOCK_NONBLOCK`/`MSG_DONTWAIT`/`fcntl`, **and** a runtime check of the socket flags in `/proc/<pid>/fdinfo` |
| only the libC | `ldd` shows nothing but libc |
| you cannot call the real traceroute | no `system`/`popen`/`exec*`/`fork` in the sources |
| errors managed reasonably, never quit unexpectedly | every case checks for a crash (signal) or a hang (timeout); `valgrind` must report no error and no leak |
| same indentation as the real traceroute | identical header line; every hop line matches the `traceroute -n` format (`%2d `, `  x.xxx ms`, ` *`, `!H`…), exactly 3 probes per line, consecutive hop numbers |

From the **usual traceroute tests** (common evaluation checks):

| Case | Expected (same as the real traceroute) |
|---|---|
| no argument | usage on stderr, exit 0 |
| unknown host `nosuch.invalid` | `Name or service not known` + `Cannot handle "host"…`, exit 2 |
| invalid IPv4 `256.1.1.1`, `1.2.3.4.5` | same resolution error, exit 2 |
| empty string, lone `-`, 300-character hostname | same error, exit 2 |
| two / three arguments | error, exit 2 |
| IPv6 `::1` | rejected cleanly (IPv6 is out of scope) |
| not root | clean permission error, no crash |
| `127.0.0.1`, `localhost`, `0.0.0.0` | 1 hop, `127.0.0.1` |
| own LAN IP | 1 hop |
| internet hosts | same hops/routers, destination reached, RTT within tolerance |
| `255.255.255.255` | send refused → error, non-zero exit, like the real one |
| `192.0.2.1` (TEST-NET, `SLOW=1`) | never answers: 30 hops of `* * *` |

### Why some differences are only warnings

Two traceroutes run one after the other don't always see the same thing:
routes can be load-balanced (different router at the same hop), and routers
rate-limit their ICMP answers (a hop may answer one program and show `*` to
the other — the real traceroute sends up to 16 probes at once, which triggers
this more easily). Those cases are reported as `WARN`, not `FAIL`. The script
waits 3 s between the two runs to limit rate-limiting effects.
