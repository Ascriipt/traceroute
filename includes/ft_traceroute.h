#ifndef FT_TRACEROUTE_H
# define FT_TRACEROUTE_H

# include <stdio.h>
# include <stdlib.h>
# include <string.h>
# include <errno.h>
# include <unistd.h>
# include <sys/types.h>
# include <sys/socket.h>
# include <sys/select.h>
# include <sys/time.h>
# include <netinet/in.h>
# include <netinet/ip.h>
# include <netinet/ip_icmp.h>
# include <netinet/udp.h>
# include <arpa/inet.h>
# include <netdb.h>

# define PROG_NAME		"ft_traceroute"
# define MAX_HOPS		30
# define NPROBES		3
# define WAIT_SEC		5.0
# define BASE_PORT		33434
# define PACKET_LEN		60
# define PAYLOAD_LEN	(PACKET_LEN - (int)sizeof(struct ip) \
							- (int)sizeof(struct udphdr))
# define RECV_BUF_LEN	512

/* One probe (one UDP datagram) and what we learned about it. */
typedef struct s_probe
{
	int				port;
	struct timeval	sent;
	struct timeval	recv;
	int				received;
	struct in_addr	from;
	int				icmp_type;
	int				icmp_code;
}	t_probe;

/* Global state of a traceroute run. */
typedef struct s_trace
{
	const char			*host;
	char				ip_str[INET_ADDRSTRLEN];
	struct sockaddr_in	dst;
	int					udp_fd;
	int					icmp_fd;
	uint16_t			src_port;
	int					max_hops;
	int					nprobes;
	double				wait;
}	t_trace;

/* args.c */
int		parse_args(int argc, char **argv, t_trace *tr);
void	print_usage(FILE *out);

/* resolve.c */
int		resolve_host(t_trace *tr);

/* socket.c */
int		open_sockets(t_trace *tr);
void	close_sockets(t_trace *tr);

/* send.c */
int		send_probe(t_trace *tr, t_probe *probe, int ttl);

/* receive.c */
int		receive_replies(t_trace *tr, t_probe *probes, int count,
			struct timeval *deadline);

/* trace.c */
int		run_traceroute(t_trace *tr);

/* print.c */
void	print_header(const t_trace *tr);
void	print_hop(int ttl, const t_probe *probes, int count);

/* time.c */
double	time_diff_ms(const struct timeval *start, const struct timeval *end);
void	time_add(struct timeval *tv, double seconds);
int		time_remaining(const struct timeval *deadline, struct timeval *out);

#endif
