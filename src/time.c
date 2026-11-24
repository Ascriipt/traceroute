#include "ft_traceroute.h"

double	time_diff_ms(const struct timeval *start, const struct timeval *end)
{
	return ((end->tv_sec - start->tv_sec) * 1000.0
		+ (end->tv_usec - start->tv_usec) / 1000.0);
}

void	time_add(struct timeval *tv, double seconds)
{
	long	usec;

	usec = (long)(seconds * 1000000.0);
	tv->tv_sec += usec / 1000000;
	tv->tv_usec += usec % 1000000;
	if (tv->tv_usec >= 1000000)
	{
		tv->tv_sec++;
		tv->tv_usec -= 1000000;
	}
}

/* Fill *out with deadline - now. Returns 0 when the deadline has passed. */
int	time_remaining(const struct timeval *deadline, struct timeval *out)
{
	struct timeval	now;

	gettimeofday(&now, NULL);
	out->tv_sec = deadline->tv_sec - now.tv_sec;
	out->tv_usec = deadline->tv_usec - now.tv_usec;
	if (out->tv_usec < 0)
	{
		out->tv_sec--;
		out->tv_usec += 1000000;
	}
	if (out->tv_sec < 0)
		return (0);
	if (out->tv_sec == 0 && out->tv_usec == 0)
		return (0);
	return (1);
}
