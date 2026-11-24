#include "ft_traceroute.h"

/*
** Resolve the host argument (IPv4 address or FQDN) exactly once.
** Hops are later displayed as raw IPs: no reverse DNS is performed.
*/
int	resolve_host(t_trace *tr)
{
	struct addrinfo	hints;
	struct addrinfo	*res;
	int				err;

	memset(&hints, 0, sizeof(hints));
	hints.ai_family = AF_INET;
	hints.ai_socktype = SOCK_DGRAM;
	err = getaddrinfo(tr->host, NULL, &hints, &res);
	if (err != 0)
	{
		fprintf(stderr, "%s: %s\n", tr->host, gai_strerror(err));
		fprintf(stderr, "Cannot handle \"host\" cmdline arg `%s' "
			"on position 1 (argc 1)\n", tr->host);
		return (-1);
	}
	memcpy(&tr->dst, res->ai_addr, sizeof(struct sockaddr_in));
	freeaddrinfo(res);
	tr->dst.sin_port = 0;
	if (!inet_ntop(AF_INET, &tr->dst.sin_addr, tr->ip_str,
			sizeof(tr->ip_str)))
	{
		perror(PROG_NAME ": inet_ntop");
		return (-1);
	}
	return (0);
}
