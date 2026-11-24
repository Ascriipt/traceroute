#!/usr/bin/env bash
# **************************************************************************** #
#  ft_traceroute test suite — compares ft_traceroute with the real traceroute   #
#                                                                              #
#  Usage:  make test                      (or bash tests/run_tests.sh)         #
#  Env:    TARGETS="h1 h2"  hosts used for the live comparison                 #
#          SLOW=1           also run the slow tests (unreachable host, ~3 min) #
#          TOL=30           RTT tolerance per hop in ms (subject: 30 ms)       #
# **************************************************************************** #

cd "$(dirname "$0")/.." || exit 1

FT=./ft_traceroute
REAL=$(command -v traceroute)
TOL=${TOL:-30}
SLOW=${SLOW:-0}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0; WARN=0; SKIP=0
if [ -t 1 ]; then
	G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'
else
	G=; R=; Y=; C=; B=; N=
fi

pass()    { PASS=$((PASS + 1)); printf "  %s[PASS]%s %s\n" "$G" "$N" "$1"; }
fail()    { FAIL=$((FAIL + 1)); printf "  %s[FAIL]%s %s\n" "$R" "$N" "$1"
            [ -n "$2" ] && printf '%s\n' "$2" | sed 's/^/         | /'; }
warn()    { WARN=$((WARN + 1)); printf "  %s[WARN]%s %s\n" "$Y" "$N" "$1"
            [ -n "$2" ] && printf '%s\n' "$2" | sed 's/^/         | /'; }
skip()    { SKIP=$((SKIP + 1)); printf "  %s[SKIP]%s %s\n" "$C" "$N" "$1"; }
section() { printf "\n%s== %s ==%s\n" "$B" "$1" "$N"; }

# run <prefix> <timeout> cmd...  -> <prefix>.out / .err / .rc
run() {
	local p=$1 t=$2
	shift 2
	timeout "$t" "$@" >"$p.out" 2>"$p.err" </dev/null
	echo $? >"$p.rc"
}

# A return code >= 124 means timeout(124) or killed by a signal (128+n).
crashed() { [ "$1" -ge 124 ]; }

# --------------------------------------------------------------------------- #
section "Build & Makefile (subject: Makefile respecting the usual rules)"
# --------------------------------------------------------------------------- #

if [ -x "$FT" ]; then pass "executable is named ft_traceroute"
else fail "executable ft_traceroute not found"; exit 1; fi

for rule in all clean fclean re '\$\(NAME\)'; do
	if grep -qE "^${rule}[[:space:]]*:" Makefile; then
		pass "Makefile has rule '${rule//\\/}'"
	else
		fail "Makefile has no rule '${rule//\\/}'"
	fi
done

if make --no-print-directory 2>&1 | grep -qE "Nothing to be done|is up to date"; then
	pass "make does not relink"
else
	fail "make relinks when nothing changed"
fi

if grep -q -- "-Wall" Makefile && grep -q -- "-Wextra" Makefile \
	&& grep -q -- "-Werror" Makefile; then
	pass "compiled with -Wall -Wextra -Werror"
else
	fail "missing -Wall -Wextra -Werror"
fi

# --------------------------------------------------------------------------- #
section "Static checks on the sources (subject rules)"
# --------------------------------------------------------------------------- #

hits=$(grep -nE "O_NONBLOCK|SOCK_NONBLOCK|MSG_DONTWAIT|fcntl[[:space:]]*\(" src/*.c includes/*.h)
if [ -z "$hits" ]; then pass "no O_NONBLOCK / non-blocking socket usage"
else fail "non-blocking socket usage found" "$hits"; fi

hits=$(grep -nE "getnameinfo|gethostbyaddr" src/*.c includes/*.h)
if [ -z "$hits" ]; then pass "no reverse DNS in hop display (no getnameinfo/gethostbyaddr)"
else fail "reverse DNS function used" "$hits"; fi

hits=$(grep -nE "\b(system|popen|execv|execve|execvp|execl|execlp|fork)[[:space:]]*\(" src/*.c)
if [ -z "$hits" ]; then pass "does not call the real traceroute (no exec/system/popen)"
else fail "program spawns other programs" "$hits"; fi

if command -v ldd >/dev/null; then
	extra=$(ldd "$FT" | grep -vE "linux-vdso|libc\.so|ld-linux")
	if [ -z "$extra" ]; then pass "only linked against the libC"
	else fail "linked against libraries other than libC" "$extra"; fi
else
	skip "ldd not available"
fi

# --------------------------------------------------------------------------- #
section "Arguments & error handling (compared with the real traceroute)"
# --------------------------------------------------------------------------- #

if [ -z "$REAL" ]; then
	skip "real traceroute not installed: comparisons skipped"
else
	# compare_args <name> <mode> args...
	#   exact : same exit status, stdout and stderr
	#   rc    : same exit status, both print an error on stderr
	#   usage : same exit status, usage printed on stderr, same --help line
	compare_args() {
		local name=$1 mode=$2 frc rrc
		shift 2
		run "$TMP/fa" 10 "$FT" "$@"
		run "$TMP/ra" 10 "$REAL" "$@"
		frc=$(cat "$TMP/fa.rc"); rrc=$(cat "$TMP/ra.rc")
		if crashed "$frc"; then
			fail "$name: crash or timeout (exit status $frc)" "$(head -5 "$TMP/fa.err")"
			return
		fi
		if [ "$frc" != "$rrc" ]; then
			fail "$name: exit status $frc, real traceroute gives $rrc"
			return
		fi
		case $mode in
		exact)
			if cmp -s "$TMP/fa.out" "$TMP/ra.out" && cmp -s "$TMP/fa.err" "$TMP/ra.err"; then
				pass "$name: identical output and exit status ($frc)"
			else
				fail "$name: output differs" "$(diff <(cat "$TMP/fa.out" "$TMP/fa.err") \
					<(cat "$TMP/ra.out" "$TMP/ra.err") | head -8)"
			fi ;;
		rc)
			if [ -s "$TMP/fa.err" ] && [ ! -s "$TMP/fa.out" ]; then
				pass "$name: error on stderr, same exit status ($frc)"
			else
				fail "$name: expected an error message on stderr only"
			fi ;;
		usage)
			local line
			line=$(grep -- "--help " "$TMP/ra.err")
			if [ ! -s "$TMP/fa.out" ] && grep -q "^Usage:" "$TMP/fa.err" \
				&& grep -qxF -- "$line" "$TMP/fa.err"; then
				pass "$name: usage on stderr, same --help line, exit status $frc"
			else
				fail "$name: usage output differs" "$(head -8 "$TMP/fa.out" "$TMP/fa.err")"
			fi ;;
		esac
	}

	compare_args "no argument"            usage
	compare_args "--help"                 usage --help
	compare_args "--help with a host"     usage --help 8.8.8.8
	compare_args "host then --help"       usage 8.8.8.8 --help
	compare_args "unknown option -x"      exact -x 8.8.8.8
	compare_args "unknown option -y"      exact -y
	compare_args "unknown long option"    exact --foo 8.8.8.8
	compare_args "lone dash as host"      exact -
	compare_args "unknown host"           exact nosuch.invalid
	compare_args "invalid IPv4 256.1.1.1" exact 256.1.1.1
	compare_args "invalid IPv4 1.2.3.4.5" exact 1.2.3.4.5
	compare_args "empty string host"      exact ""
	compare_args "very long hostname"     exact "$(printf 'a%.0s' {1..300}).com"
	compare_args "two hosts"              rc    8.8.8.8 1.1.1.1
	compare_args "three arguments"        rc    8.8.8.8 a b
fi

# IPv6 is out of scope (subject: IPv4 only): must fail cleanly.
run "$TMP/v6" 10 "$FT" ::1
rc=$(cat "$TMP/v6.rc")
if ! crashed "$rc" && [ "$rc" -ne 0 ] && [ -s "$TMP/v6.err" ]; then
	pass "IPv6 address ::1 rejected cleanly (exit status $rc)"
else
	fail "IPv6 address ::1 not handled cleanly (exit status $rc)" "$(cat "$TMP/v6.out" "$TMP/v6.err")"
fi

# Without root, the raw socket cannot be opened: clean error expected.
if [ "$(id -u)" -ne 0 ]; then
	run "$TMP/nr" 10 "$FT" 127.0.0.1
	rc=$(cat "$TMP/nr.rc")
	if ! crashed "$rc" && [ "$rc" -ne 0 ] && grep -qi "permi\|root" "$TMP/nr.err"; then
		pass "without root: clean permission error (exit status $rc)"
	else
		fail "without root: unexpected behaviour (exit status $rc)" "$(cat "$TMP/nr.err")"
	fi
else
	skip "running as root: non-root permission test skipped"
fi

# --------------------------------------------------------------------------- #
section "Live comparison with the real traceroute (needs root)"
# --------------------------------------------------------------------------- #

AS_ROOT=
ROOT_OK=1
if [ "$(id -u)" -ne 0 ]; then
	if sudo -n true 2>/dev/null; then AS_ROOT=sudo
	else
		echo "  ft_traceroute needs root for its raw socket, asking sudo:"
		if sudo -v; then AS_ROOT=sudo; else ROOT_OK=0; fi
	fi
fi

# Hop line format of traceroute -n:  "%2d " then " IP" / "  x.xxx ms[ !X]" / " *"
HOP_RE='^( [1-9]|[1-9][0-9]) (( \*)|( ([0-9]{1,3}\.){3}[0-9]{1,3})|(  [0-9]+\.[0-9]{3} ms( ![A-Z<>0-9]+)?))+$'

# parse <file>: "ttl|ip1,ip2|min_rtt" for each hop line
parse() {
	awk 'NR > 1 {
		ips = ""; min = ""
		for (i = 2; i <= NF; i++) {
			t = $i
			if (t ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
				if (index("," ips ",", "," t ",") == 0)
					ips = ips (ips == "" ? "" : ",") t
			} else if (t ~ /^[0-9]+\.[0-9]+$/ && $(i + 1) == "ms") {
				if (min == "" || t + 0 < min + 0) min = t
			}
		}
		printf "%s|%s|%s\n", $1, ips, min
	}' "$1"
}

compare_trace() {
	local target=$1 frc rrc bad nf nr dest
	printf "  %s-- %s%s\n" "$B" "$target" "$N"
	run "$TMP/rt" 400 "$REAL" -4 -n "$target"
	sleep 3
	run "$TMP/ft" 400 $AS_ROOT "$FT" "$target"
	frc=$(cat "$TMP/ft.rc"); rrc=$(cat "$TMP/rt.rc")

	if crashed "$frc"; then
		fail "$target: crash or timeout (exit status $frc)" "$(tail -5 "$TMP/ft.out" "$TMP/ft.err")"
		return
	fi
	if [ "$frc" = "$rrc" ]; then pass "$target: same exit status ($frc)"
	else fail "$target: exit status $frc, real traceroute gives $rrc" "$(cat "$TMP/ft.err")"; fi

	if [ "$(head -1 "$TMP/ft.out")" = "$(head -1 "$TMP/rt.out")" ]; then
		pass "$target: identical header line"
	else
		fail "$target: header differs" "ft  : $(head -1 "$TMP/ft.out")
real: $(head -1 "$TMP/rt.out")"
	fi

	bad=$(tail -n +2 "$TMP/ft.out" | grep -vE "$HOP_RE")
	bad+=$(tail -n +2 "$TMP/ft.out" | awk '{ n = 0
		for (i = 2; i <= NF; i++) if ($i == "ms" || $i == "*") n++
		if (n != 3) print "not 3 probes: " $0 }')
	bad+=$(tail -n +2 "$TMP/ft.out" | awk '$1 != NR { print "bad hop number: " $0; exit }')
	if [ -z "$bad" ]; then pass "$target: same indentation/format as traceroute -n, IPs only (no DNS)"
	else fail "$target: badly formatted hop lines" "$bad"; fi

	nf=$(($(wc -l <"$TMP/ft.out") - 1)); nr=$(($(wc -l <"$TMP/rt.out") - 1))
	[ "$nf" -lt 0 ] && nf=0; [ "$nr" -lt 0 ] && nr=0
	if [ "$nf" -eq "$nr" ]; then pass "$target: same number of hops ($nf)"
	else warn "$target: $nf hops, real traceroute shows $nr (the route may have changed)"; fi

	dest=$(head -1 "$TMP/rt.out" | sed -n 's/^[^(]*(\([0-9.]*\)).*/\1/p')
	if tail -1 "$TMP/rt.out" | grep -qw -- "$dest"; then
		if tail -1 "$TMP/ft.out" | grep -qw -- "$dest"; then
			pass "$target: destination $dest reached, trace stops there"
		else
			fail "$target: real traceroute reaches $dest, ft_traceroute does not"
		fi
	fi

	parse "$TMP/rt.out" >"$TMP/rt.p"
	parse "$TMP/ft.out" >"$TMP/ft.p"
	awk -F'|' -v tol="$TOL" '
		NR == FNR { rip[$1] = $2; rmin[$1] = $3; next }
		($1 in rip) {
			if ($2 == "" || rip[$1] == "") {
				if ($2 != rip[$1])
					print "WARN hop " $1 ": only one side got answers (ft=[" $2 "] real=[" rip[$1] "])"
				next
			}
			n = split($2, a, ","); common = 0
			for (k = 1; k <= n; k++)
				if (index("," rip[$1] ",", "," a[k] ",")) common = 1
			if (!common) {
				print "WARN hop " $1 ": different routers (ft=" $2 " real=" rip[$1] ")"
				next
			}
			d = $3 - rmin[$1]; if (d < 0) d = -d
			if (d > tol)
				printf "FAIL hop %s: RTT differs by %.3f ms > %s ms (ft=%s real=%s)\n", $1, d, tol, $3, rmin[$1]
			else
				ok++
		}
		END { print "OK " ok + 0 }' "$TMP/rt.p" "$TMP/ft.p" >"$TMP/cmp"

	local ok fails warns
	ok=$(sed -n 's/^OK //p' "$TMP/cmp")
	fails=$(grep "^FAIL" "$TMP/cmp" | sed 's/^FAIL //')
	warns=$(grep "^WARN" "$TMP/cmp" | sed 's/^WARN //')
	if [ -z "$fails" ]; then pass "$target: $ok common hop(s) with same router and RTT within ±${TOL} ms"
	else fail "$target: RTT out of tolerance" "$fails"; fi
	[ -n "$warns" ] && warn "$target: hops that could not be compared (load balancing / ICMP rate limiting)" "$warns"
	if [ -n "$fails" ] || [ "$frc" != "$rrc" ]; then
		printf '         | %s\n' "--- ft_traceroute:"; sed 's/^/         | /' "$TMP/ft.out"
		printf '         | %s\n' "--- traceroute -n:"; sed 's/^/         | /' "$TMP/rt.out"
	fi
}

if [ -z "$REAL" ]; then
	skip "real traceroute not installed"
elif [ "$ROOT_OK" -ne 1 ]; then
	skip "no root access: live tests skipped (run 'sudo make test')"
else
	if [ -z "$TARGETS" ]; then
		local_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')
		TARGETS="127.0.0.1 localhost 0.0.0.0 $local_ip"
		if getent hosts google.com >/dev/null 2>&1; then
			TARGETS="$TARGETS 8.8.8.8 1.1.1.1 google.com www.42.fr"
		else
			skip "no DNS/internet: remote targets skipped"
		fi
	fi
	for t in $TARGETS; do
		compare_trace "$t"
	done

	# Broadcast address: sendto() is refused, both must exit with an error.
	printf "  %s-- 255.255.255.255%s\n" "$B" "$N"
	run "$TMP/bc" 20 $AS_ROOT "$FT" 255.255.255.255
	run "$TMP/rbc" 20 "$REAL" -4 -n 255.255.255.255
	rc=$(cat "$TMP/bc.rc"); rrc=$(cat "$TMP/rbc.rc")
	if ! crashed "$rc" && [ "$rc" -ne 0 ] && [ "$rrc" -ne 0 ] && [ -s "$TMP/bc.err" ]; then
		pass "255.255.255.255: clean error like the real traceroute (exit status $rc / real $rrc)"
	else
		fail "255.255.255.255: exit status $rc (real $rrc)" "$(cat "$TMP/bc.out" "$TMP/bc.err")"
	fi

	# Runtime check: sockets of the running process must not be O_NONBLOCK.
	$AS_ROOT "$FT" 192.0.2.1 >/dev/null 2>&1 &
	sleep 3
	pid=$(pgrep -n -x ft_traceroute)
	if [ -n "$pid" ]; then
		nb=0; nsock=0
		for fd in $($AS_ROOT ls /proc/"$pid"/fd 2>/dev/null); do
			if $AS_ROOT readlink /proc/"$pid"/fd/"$fd" | grep -q '^socket:'; then
				nsock=$((nsock + 1))
				flags=$($AS_ROOT awk '/^flags:/ { print $2 }' /proc/"$pid"/fdinfo/"$fd")
				(( 8#$flags & 8#4000 )) && nb=1
			fi
		done
		$AS_ROOT kill "$pid" 2>/dev/null
		if [ "$nsock" -eq 0 ]; then skip "runtime O_NONBLOCK check: no socket found"
		elif [ "$nb" -eq 0 ]; then pass "runtime: the $nsock socket(s) are in blocking mode"
		else fail "runtime: a socket is in O_NONBLOCK mode"; fi
	else
		skip "runtime O_NONBLOCK check: process not found"
	fi
	wait 2>/dev/null

	# Memory errors / leaks.
	if command -v valgrind >/dev/null; then
		run "$TMP/vg" 120 $AS_ROOT valgrind --leak-check=full --show-leak-kinds=all \
			--track-fds=yes --error-exitcode=42 "$FT" 127.0.0.1
		if [ "$(cat "$TMP/vg.rc")" = 0 ] && grep -q "All heap blocks were freed" "$TMP/vg.err"; then
			pass "valgrind: no memory error, no leak"
		else
			fail "valgrind reported problems" "$(grep -E "ERROR SUMMARY|definitely|indirectly|still reachable|Open" "$TMP/vg.err")"
		fi
	else
		skip "valgrind not installed"
	fi

	if [ "$SLOW" = 1 ]; then
		section "Slow tests"
		# 192.0.2.1 is TEST-NET-1 (RFC 5737): usually never answers,
		# so the trace must go up to 30 hops, ending with '* * *' lines.
		compare_trace 192.0.2.1
		if [ "$(tail -n +2 "$TMP/ft.out" | wc -l)" -eq 30 ]; then
			pass "192.0.2.1: stops after 30 hops max"
		else
			warn "192.0.2.1: $(tail -n +2 "$TMP/ft.out" | wc -l) hops (an answer was received?)"
		fi
	else
		skip "slow tests (unreachable host, 30 hops): run with 'make test SLOW=1'"
	fi
fi

# --------------------------------------------------------------------------- #
printf "\n%sSummary:%s %s%d passed%s, %s%d failed%s, %s%d warnings%s, %s%d skipped%s\n" \
	"$B" "$N" "$G" "$PASS" "$N" "$R" "$FAIL" "$N" "$Y" "$WARN" "$N" "$C" "$SKIP" "$N"
[ "$FAIL" -eq 0 ]
