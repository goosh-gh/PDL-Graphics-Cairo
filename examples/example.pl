use strict;
use warnings;

use PDL;
use PDL::Graphics::Cairo qw(figure);

my $x = sequence(200)/10;
my $y = sin($x);

my $fig = figure(width=>800,height=>600);

my $ax = $fig->axes(title=>"sin(x)");

$ax->line($x,$y);

$fig->show();

print "done (window opened)\n";
