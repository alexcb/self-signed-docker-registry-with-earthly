#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <limits.h>

void print_help(char **argv)
{
	const char *bin_name = "euler";
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

	long double e = 0.0;
	long long unsigned factorial = 1;
	if( n > 0 ) {
		e += 1.0;
	}
	for( int i = 1; i < n; i++ ) {
		factorial *= i;
		if( factorial >= ULLONG_MAX || factorial == 0 ) {
			// TODO use gmp.h for better precission
			fprintf(stderr, "unable to calculate factorial: long long unsigned is too small.\n");
			return 3;
		}
		e += 1.0 / factorial;
	}

	printf("%Lf\n", e);
	return 0;
}
