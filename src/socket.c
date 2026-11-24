#include "ft_traceroute.h"

/*
** Bind the UDP socket to an ephemeral port chosen by the kernel and
** remember it: it lets us recognise our own probes in ICMP errors.
*/
static int	bind_udp_socket(t_trace *tr)
{
	struct sockaddr_in	local;
	socklen_t			len;

	memset(&local, 0, sizeof(local));
	local.sin_family = AF_INET;
	local.sin_addr.s_addr = htonl(INADDR_ANY);
	local.sin_port = 0;
	if (bind(tr->udp_fd, (struct sockaddr *)&local, sizeof(local)) < 0)
	{
		perror(PROG_NAME ": bind");
		return (-1);
	}
	len = sizeof(local);
	if (getsockname(tr->udp_fd, (struct sockaddr *)&local, &len) < 0)
	{
		perror(PROG_NAME ": getsockname");
		return (-1);
	}
	tr->src_port = ntohs(local.sin_port);
	return (0);
}

int	open_sockets(t_trace *tr)
{
	tr->icmp_fd = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
	if (tr->icmp_fd < 0)
	{
		perror(PROG_NAME ": socket (raw ICMP)");
		if (errno == EPERM || errno == EACCES)
			fprintf(stderr, PROG_NAME ": you must be root to run this "
				"program\n");
		return (-1);
	}
	tr->udp_fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
	if (tr->udp_fd < 0)
	{
		perror(PROG_NAME ": socket (UDP)");
		return (-1);
	}
	return (bind_udp_socket(tr));
}

void	close_sockets(t_trace *tr)
{
	if (tr->udp_fd >= 0)
		close(tr->udp_fd);
	if (tr->icmp_fd >= 0)
		close(tr->icmp_fd);
	tr->udp_fd = -1;
	tr->icmp_fd = -1;
}
