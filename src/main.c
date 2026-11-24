#include "ft_traceroute.h"

int	main(int argc, char **argv)
{
	t_trace	tr;
	int		ret;

	memset(&tr, 0, sizeof(tr));
	tr.udp_fd = -1;
	tr.icmp_fd = -1;
	tr.max_hops = MAX_HOPS;
	tr.nprobes = NPROBES;
	tr.wait = WAIT_SEC;
	ret = parse_args(argc, argv, &tr);
	if (ret != 0)
		return (ret < 0 ? 0 : ret);
	if (resolve_host(&tr) != 0)
		return (2);
	if (open_sockets(&tr) != 0)
	{
		close_sockets(&tr);
		return (2);
	}
	ret = run_traceroute(&tr);
	close_sockets(&tr);
	return (ret);
}
