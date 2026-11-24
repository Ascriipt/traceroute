#include "ft_traceroute.h"

/*
** Did this hop end the trace? Any ICMP "destination unreachable" means
** either we reached the target (port unreachable) or it can't be reached.
*/
static int	hop_is_final(const t_probe *probes, int count)
{
	int	i;

	i = 0;
	while (i < count)
	{
		if (probes[i].received && probes[i].icmp_type == ICMP_UNREACH)
			return (1);
		i++;
	}
	return (0);
}

static int	trace_hop(t_trace *tr, int ttl, t_probe *probes)
{
	struct timeval	deadline;
	int				i;

	memset(probes, 0, sizeof(t_probe) * tr->nprobes);
	i = 0;
	while (i < tr->nprobes)
	{
		probes[i].port = BASE_PORT + (ttl - 1) * tr->nprobes + i;
		if (send_probe(tr, &probes[i], ttl) < 0)
			return (-1);
		i++;
	}
	gettimeofday(&deadline, NULL);
	time_add(&deadline, tr->wait);
	if (receive_replies(tr, probes, tr->nprobes, &deadline) < 0)
		return (-1);
	print_hop(ttl, probes, tr->nprobes);
	return (hop_is_final(probes, tr->nprobes));
}

int	run_traceroute(t_trace *tr)
{
	t_probe	probes[NPROBES];
	int		ttl;
	int		ret;

	print_header(tr);
	ttl = 1;
	while (ttl <= tr->max_hops)
	{
		ret = trace_hop(tr, ttl, probes);
		if (ret < 0)
			return (1);
		if (ret == 1)
			break ;
		ttl++;
	}
	return (0);
}
