use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::Driver::Gnuplot;

# Driver::Gnuplot object creation
my $drv = PDL::Graphics::Cairo::Driver::Gnuplot->new(
    width => 400, height => 300
);
isa_ok $drv, 'PDL::Graphics::Cairo::Driver::Gnuplot';
is $drv->width,  400, 'width';
is $drv->height, 300, 'height';
is $drv->terminal, '', 'default terminal is auto';
is $drv->keep,     0,  'default keep is 0';

# Figure has show() / _render_to() / save() methods
my $fig = figure(width => 400, height => 300);
can_ok $fig, 'show';
can_ok $fig, '_render_to';
can_ok $fig, 'save';

done_testing;
