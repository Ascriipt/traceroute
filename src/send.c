#include "ft_traceroute.h"

/*
** Send one UDP probe with the given TTL to probe->port on the target.
** The send time is recorded just before sendto() for RTT computation.
*/
int	send_probe(t_trace *tr, t_probe *probe, int ttl)
{
	char				payload[PAYLOAD_LEN];
	struct sockaddr_in	to;
	int					i;

	if (setsockopt(tr->udp_fd, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) < 0)
	{
		perror(PROG_NAME ": setsockopt IP_TTL");
		return (-1);
	}
	i = 0;
	while (i < PAYLOAD_LEN)
	{
		payload[i] = 0x40 + (i % 0x20);
		i++;
	}
	to = tr->dst;
	to.sin_port = htons(probe->port);
	gettimeofday(&probe->sent, NULL);
	if (sendto(tr->udp_fd, payload, sizeof(payload), 0,
			(struct sockaddr *)&to, sizeof(to)) < 0)
	{
		perror(PROG_NAME ": sendto");
		return (-1);
	}
	return (0);
}
