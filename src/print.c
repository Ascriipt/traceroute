#include "ft_traceroute.h"

void	print_header(const t_trace *tr)
{
	printf("traceroute to %s (%s), %d hops max, %d byte packets\n",
		tr->host, tr->ip_str, tr->max_hops, PACKET_LEN);
	fflush(stdout);
}

/* Same annotations as the real traceroute for ICMP unreachable codes. */
static void	print_annotation(const t_probe *p)
{
	if (p->icmp_type != ICMP_UNREACH)
		return ;
	if (p->icmp_code == ICMP_UNREACH_PORT)
		return ;
	if (p->icmp_code == ICMP_UNREACH_NET
		|| p->icmp_code == ICMP_UNREACH_NET_UNKNOWN
		|| p->icmp_code == ICMP_UNREACH_NET_PROHIB)
		printf(" !N");
	else if (p->icmp_code == ICMP_UNREACH_HOST
		|| p->icmp_code == ICMP_UNREACH_HOST_UNKNOWN
		|| p->icmp_code == ICMP_UNREACH_HOST_PROHIB)
		printf(" !H");
	else if (p->icmp_code == ICMP_UNREACH_PROTOCOL)
		printf(" !P");
	else if (p->icmp_code == ICMP_UNREACH_NEEDFRAG)
		printf(" !F");
	else if (p->icmp_code == ICMP_UNREACH_SRCFAIL)
		printf(" !S");
	else if (p->icmp_code == ICMP_UNREACH_FILTER_PROHIB)
		printf(" !X");
	else if (p->icmp_code == ICMP_UNREACH_HOST_PRECEDENCE)
		printf(" !V");
	else if (p->icmp_code == ICMP_UNREACH_PRECEDENCE_CUTOFF)
		printf(" !C");
	else
		printf(" !<%d>", p->icmp_code);
}

/*
** Format (identical to traceroute -n):
**  " 1  192.168.1.1  0.512 ms  0.480 ms  0.470 ms"
**  " 5  * * *"
** The address is only printed when it differs from the previous one.
*/
void	print_hop(int ttl, const t_probe *probes, int count)
{
	char			ip[INET_ADDRSTRLEN];
	struct in_addr	last;
	int				i;

	printf("%2d ", ttl);
	last.s_addr = 0;
	i = 0;
	while (i < count)
	{
		if (!probes[i].received)
			printf(" *");
		else
		{
			if (probes[i].from.s_addr != last.s_addr)
			{
				inet_ntop(AF_INET, &probes[i].from, ip, sizeof(ip));
				printf(" %s", ip);
				last = probes[i].from;
			}
			printf("  %.3f ms",
				time_diff_ms(&probes[i].sent, &probes[i].recv));
			print_annotation(&probes[i]);
		}
		i++;
	}
	printf("\n");
	fflush(stdout);
}
