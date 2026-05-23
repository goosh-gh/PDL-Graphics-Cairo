#!/usr/bin/env perl
# example_cairo_api.pl
# PDL::Graphics::Cairo (matplotlib-style API) demo
# Equivalent to example_pgplot.pl but using the Cairo API directly.
#
# Run:
#   perl -I./lib examples/example_cairo_api.pl
#
# Device switching via show() argument:
#   macOS native:  $fig->show(backend => 'osx')   [default on macOS]
#   gnuplot/aqua:  $fig->show(terminal => 'aqua')
#   gnuplot/x11:   $fig->show(terminal => 'x11')
#   PNG file:      $fig->save('output.png')

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure);

my $x = pdl(-100 .. 899);
my $y = 10 + $x * (-20 / 999);

my $fig = figure(width => 800, height => 500);
my $ax  = $fig->axes();

$ax->line($x, $y, color => 'green', lw => 1.5);
$ax->xlim(-100, 899);
$ax->ylim(10, -10);     # lo > hi → negative up (Y axis auto-reversed)
$ax->set_grid(0);

# Channel label near upper-right (equivalent to pgmtxt "TR")
$ax->text(870, 9.5, "Ch1", color => 'black');

$fig->tight_layout();

if ($^O eq 'darwin') {
    $fig->show(backend => 'osx', title => 'Ch1');
} else {
    $fig->show();   # gnuplot auto-detect (wxt/x11/qt)
}
