use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::Driver::Cairo;

# ==================================================================
# Cairo's arc() joins the current point to the start of the arc with a
# straight line. text() leaves a current point (move_to before
# show_layout), so a circle marker drawn after a text had a line from the
# text to the circle: in a legend of scatter entries, a line from each
# label to the next marker. marker() and circle() now start from an empty
# path.
# ==================================================================

sub pixel {
    my ($d, $x, $y) = @_;
    my $s = $d->{surface};
    $s->flush;
    return [ unpack('C4', substr($s->get_data, $y * $s->get_stride + $x * 4, 4)) ];
}

sub white { my ($p) = @_; $p->[0] > 250 && $p->[1] > 250 && $p->[2] > 250 }

# text near (10, 10), then a red marker / circle at (100, 100): a stray line
# would run from the text's current point to the start of the arc (104, 100),
# through the square x 30..80, y 25..80, which is otherwise empty
sub red_pixels {
    my ($d, $x0, $x1, $y0, $y1) = @_;
    my $n = 0;
    for my $y ($y0 .. $y1) {
        for my $x ($x0 .. $x1) {
            my $p = pixel($d, $x, $y);          # B, G, R, A
            $n++ if $p->[2] - $p->[1] > 60;
        }
    }
    return $n;
}
for my $what (qw(marker circle)) {
    my $d = PDL::Graphics::Cairo::Driver::Cairo->new(width => 120, height => 120, file => ':memory:');
    $d->set_color(0, 0, 0);
    $d->set_font(size => 10);
    $d->text(10, 10, 'label', align => 'left', valign => 'middle');
    $d->set_color(1, 0, 0);
    $d->set_linewidth(2);
    $what eq 'marker' ? $d->marker(100, 100, 4, 'o', 1) : $d->circle(100, 100, 4, 0);   # outline: a stray segment would be stroked
    is(red_pixels($d, 30, 80, 25, 80), 0, "$what after text: nothing drawn between them");
    ok(red_pixels($d, 95, 105, 95, 105) > 20, "$what after text: the circle is drawn");
}

# the legend of a scatter plot: between two markers' rows, left of the labels
{
    my $fig = figure(width => 300, height => 240);
    my $ax  = $fig->axes;
    $ax->scatter(pdl(0, 1), pdl(0, 1), color => 'red',  label => 'Class 0');
    $ax->scatter(pdl(0, 1), pdl(1, 0), color => 'blue', label => 'Class 1');
    $ax->scatter(pdl(0.5),  pdl(0.5), color => 'green', label => 'Class 2');
    $ax->legend(loc => 'upper right');
    my $d = PDL::Graphics::Cairo::Driver::Cairo->new(width => 300, height => 240, file => ':memory:');
    $fig->_render_to($d);
    my $s = $d->{surface};
    $s->flush;
    my $p = zeroes(byte, 4, 300, 240);
    ${ $p->get_dataref } = substr($s->get_data, 0, 300 * 240 * 4);
    $p->upd_data;
    # coloured (not grey/black/white) pixels: |R-G| or |G-B| large
    my $c = $p->long;
    my $col = (($c->slice('(2)') - $c->slice('(1)'))->abs + ($c->slice('(1)') - $c->slice('(0)'))->abs) > 120;
    # the legend box is the top-right area; count coloured pixels there that are
    # not near a marker: the markers sit in a narrow column, a stray line slants
    my $w = whichND($col->slice('150:299,0:110'));
    my %cols;
    $cols{ $w->at(0, $_) }++ for 0 .. $w->dim(1) - 1;
    my $spread = scalar keys %cols;
    cmp_ok($spread, '<=', 20, "legend: coloured pixels only in the marker column ($spread columns)");
}

done_testing;
