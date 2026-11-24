#include "ft_traceroute.h"

void	print_usage(FILE *out)
{
	fprintf(out,
		"Usage:\n"
		"  " PROG_NAME " host\n"
		"Options:\n"
		"  --help                      Read this help and exit\n"
		"\n"
		"Arguments:\n"
		"+     host          The host to traceroute to\n");
}

/*
** Returns 0 when the program should continue, -1 when it should exit
** successfully (--help or no argument, like the real traceroute: usage on
** stderr, exit status 0) and a positive exit code on error.
*/
int	parse_args(int argc, char **argv, t_trace *tr)
{
	int	i;

	if (argc < 2)
	{
		print_usage(stderr);
		return (-1);
	}
	i = 1;
	while (i < argc)
	{
		if (strcmp(argv[i], "--help") == 0)
		{
			print_usage(stderr);
			return (-1);
		}
		i++;
	}
	i = 1;
	while (i < argc)
	{
		if (argv[i][0] == '-' && argv[i][1] != '\0')
		{
			fprintf(stderr, "Bad option `%s' (argc %d)\n", argv[i], i);
			return (2);
		}
		if (tr->host != NULL)
		{
			fprintf(stderr, "Extra arg `%s' (position %d, argc %d)\n",
				argv[i], 2, i);
			return (2);
		}
		tr->host = argv[i];
		i++;
	}
	if (tr->host == NULL)
	{
		print_usage(stderr);
		return (2);
	}
	return (0);
}
