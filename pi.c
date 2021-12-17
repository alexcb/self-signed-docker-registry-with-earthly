
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <limits.h>

void print_help(char **argv)
{
	const char *bin_name = "pi";
	if( argv && argv[0] && argv[0][0] ) {
		bin_name = argv[0];
	}
	fprintf(stderr, "usage: %s <N>\n", bin_name);
}

int main(int argc, char **argv, char **env)
{
	if( argc != 2 ) {
		print_help(argv);
		return 1;
	}

	const char *n_str = argv[1];
	int n = atoi(n_str);
	if( n <= 0 && strcmp(n_str, "0") ) {
		print_help(argv);
		return 2;
	}

	long double pi = 0.0;
	for( int i = 0; i < n; i++ ) {
		pi += powl(-1.0, i) / (2.0*i+1);
	}
	pi *= 4.0;

	printf("%Lf\n", pi);
	return 0;
}
