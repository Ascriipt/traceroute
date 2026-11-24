NAME		= ft_traceroute

CC			= cc
CFLAGS		= -Wall -Wextra -Werror
INCLUDES	= -I includes

SRC_DIR		= src
OBJ_DIR		= obj

SRCS		= main.c \
			  args.c \
			  resolve.c \
			  socket.c \
			  send.c \
			  receive.c \
			  trace.c \
			  print.c \
			  time.c

OBJS		= $(addprefix $(OBJ_DIR)/, $(SRCS:.c=.o))

all: $(NAME)

$(NAME): $(OBJS)
	$(CC) $(CFLAGS) $(OBJS) -o $(NAME)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c includes/ft_traceroute.h
	@mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

clean:
	rm -rf $(OBJ_DIR)

fclean: clean
	rm -f $(NAME)

re: fclean all

# Compare ft_traceroute with the real traceroute.
#   make test                       quick + live tests (asks sudo if needed)
#   make test SLOW=1                also the slow tests (unreachable host)
#   make test TARGETS="8.8.8.8 a.b" choose the live targets
test: $(NAME)
	@SLOW="$(SLOW)" TARGETS="$(TARGETS)" TOL="$(TOL)" bash tests/run_tests.sh

.PHONY: all clean fclean re test
