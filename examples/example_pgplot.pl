#!/usr/bin/env perl
# example_pgplot.pl
# PDL::Graphics::Cairo::PGPLOT compatibility layer demo
# Equivalent to example_cairo_api.pl but using PGPLOT-style API.
#
# Run:
#   perl -I./lib examples/example_pgplot.pl
#
# Device switching via pgbegin() argument:
#   macOS native:  pgbegin(0, "/osx",  1, 1)   [default on macOS]
#   gnuplot/aqua:  pgbegin(0, "/aqua", 1, 1)
#   gnuplot/x11:   pgbegin(0, "/xw",   1, 1)
#   PNG file:      pgbegin(0, "output.png/PNG", 1, 1)

use strict;
use warnings;
use PDL::Graphics::Cairo::PGPLOT qw(:all);

my @x = (-100 .. 899);
my @y = map { 10 + $_ * (-20 / 999) } (0 .. 999);
my $n = scalar @x;

if ($^O eq 'darwin') {
    pgbegin(0, "/osx", 1, 1);
} else {
    pgbegin(0, "/xw", 1, 1);   # X11 via gnuplot
}

pgenv(-100, 899, 10, -10, 0, -2);   # negative up: ymin > ymax
pgsci(3);                            # green
pgline($n, \@x, \@y);
pgsci(1);
pgbox("ANST", 0.0, 1, "ANTV", 5.0, 2);
pgmtxt("TR", -1, 0.1, 1.0, "Ch1");
pgend();
