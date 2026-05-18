use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

# figure() creation
my $fig = figure(width => 400, height => 300);
isa_ok $fig, 'PDL::Graphics::Cairo::Figure';
is $fig->width,  400, 'width';
is $fig->height, 300, 'height';

# axes() creation
my $ax = $fig->axes();
isa_ok $ax, 'PDL::Graphics::Cairo::Axes';

# line() does not throw an error
my $x = sequence(10);
my $y = $x * $x;
eval { $ax->line($x, $y) };
is $@, '', 'line() no error';

# save() generates a PNG file
my $tmpfile = "/tmp/test_$$.png";
eval { $fig->save($tmpfile) };
is $@, '', 'save() no error';
ok -f $tmpfile, 'PNG file created';
unlink $tmpfile;

done_testing;
