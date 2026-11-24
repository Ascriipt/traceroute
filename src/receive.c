#include "ft_traceroute.h"

/*
** Check that an ICMP message is a reply to one of OUR probes and return
** the destination port of the UDP datagram that triggered it (-1 if not).
** Our probes are recognised by their UDP source port (bound, unique to this
** process). The quoted destination address is NOT checked: the kernel may
** rewrite it (e.g. 0.0.0.0 is sent to 127.0.0.1).
**
**  [ outer IP hdr ][ ICMP hdr (8) ][ inner IP hdr ][ inner UDP hdr (8) ]
*/
static int	parse_icmp(t_trace *tr, char *buf, ssize_t len,
				struct icmp **icmp_out)
{
	struct ip		*ip;
	struct icmp		*icmp;
	struct ip		*inner;
	struct udphdr	*udp;
	int				hlen;
	int				inner_hlen;

	ip = (struct ip *)buf;
	hlen = ip->ip_hl << 2;
	if (len < hlen + ICMP_MINLEN + (ssize_t)sizeof(struct ip))
		return (-1);
	icmp = (struct icmp *)(buf + hlen);
	if (!(icmp->icmp_type == ICMP_TIMXCEED
			&& icmp->icmp_code == ICMP_TIMXCEED_INTRANS)
		&& icmp->icmp_type != ICMP_UNREACH)
		return (-1);
	inner = &icmp->icmp_ip;
	inner_hlen = inner->ip_hl << 2;
	if (len < hlen + ICMP_MINLEN + inner_hlen + (ssize_t)sizeof(*udp))
		return (-1);
	if (inner->ip_p != IPPROTO_UDP)
		return (-1);
	udp = (struct udphdr *)((char *)inner + inner_hlen);
	if (ntohs(udp->uh_sport) != tr->src_port)
		return (-1);
	*icmp_out = icmp;
	return (ntohs(udp->uh_dport));
}

/* Store the reply in the probe whose destination port matches. */
static int	match_probe(t_probe *probes, int count, int port,
				struct icmp *icmp, struct sockaddr_in *from,
				struct timeval *now)
{
	int	i;

	i = 0;
	while (i < count)
	{
		if (probes[i].port == port && !probes[i].received)
		{
			probes[i].received = 1;
			probes[i].recv = *now;
			probes[i].from = from->sin_addr;
			probes[i].icmp_type = icmp->icmp_type;
			probes[i].icmp_code = icmp->icmp_code;
			return (1);
		}
		i++;
	}
	return (0);
}

static int	read_one(t_trace *tr, t_probe *probes, int count)
{
	char				buf[RECV_BUF_LEN];
	struct sockaddr_in	from;
	socklen_t			fromlen;
	ssize_t				len;
	struct timeval		now;
	struct icmp			*icmp;
	int					port;

	fromlen = sizeof(from);
	len = recvfrom(tr->icmp_fd, buf, sizeof(buf), 0,
			(struct sockaddr *)&from, &fromlen);
	gettimeofday(&now, NULL);
	if (len < 0)
	{
		if (errno == EINTR)
			return (0);
		perror(PROG_NAME ": recvfrom");
		return (-1);
	}
	port = parse_icmp(tr, buf, len, &icmp);
	if (port < 0)
		return (0);
	return (match_probe(probes, count, port, icmp, &from, &now));
}

/*
** Wait (with select(), sockets stay blocking) until every probe of the
** hop got an answer or the deadline is reached.
*/
int	receive_replies(t_trace *tr, t_probe *probes, int count,
		struct timeval *deadline)
{
	fd_set			rfds;
	struct timeval	timeout;
	int				pending;
	int				ret;

	pending = count;
	while (pending > 0 && time_remaining(deadline, &timeout))
	{
		FD_ZERO(&rfds);
		FD_SET(tr->icmp_fd, &rfds);
		ret = select(tr->icmp_fd + 1, &rfds, NULL, NULL, &timeout);
		if (ret < 0)
		{
			if (errno == EINTR)
				continue ;
			perror(PROG_NAME ": select");
			return (-1);
		}
		if (ret == 0)
			break ;
		ret = read_one(tr, probes, count);
		if (ret < 0)
			return (-1);
		pending -= ret;
	}
	return (0);
}
