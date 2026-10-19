use strict;
use warnings;
use utf8;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);

# The label on the right of a twinx (set_right_ylabel, or the twin's ylabel)
# is drawn past the right tick numbers, and tight_layout leaves room for both
# (Axes::_twin_yaxis_room, the same formula as _draw_twin_yaxis). Up to 0.42
# the label was anchored at its lower edge at mr+20, so it grew to the left
# over the tick numbers, and tight_layout did not count set_right_ylabel.

# ARGB32 pixels of the figure as a (4, W, H) byte piddle (B,G,R,A on LE).
sub render_pixels {
    my ($f) = @_;
    my $d = PDL::Graphics::Cairo::Driver::Cairo->new(
        width => $f->width, height => $f->height, file => ':memory:');
    $f->_render_to($d);
    my $s = $d->{surface};
    $s->flush;
    my $stride = $s->get_stride;
    my ($w, $h) = ($f->width, $f->height);
    my $raw = $s->get_data;
    my $p = zeroes(byte, 4, $w, $h);
    my $ref = $p->get_dataref;
    $$ref = join '', map { substr($raw, $_ * $stride, 4 * $w) } 0 .. $h - 1;
    $p->upd_data;
    return $p;
}

# x range (x0, x1) of the columns where two renders differ
sub diff_xrange {
    my ($p, $q) = @_;
    my $d = (($p->long - $q->long)->abs->sumover > 30);   # (W, H)
    my $xs = which($d->mv(1, 0)->sumover > 0);
    return () unless $xs->nelem;
    return ($xs->min->sclr, $xs->max->sclr);
}

# A twinx figure, laid out by tight_layout with the right label given as $how
# ('right': set_right_ylabel, 'ylabel': the twin's ylabel). After the layout,
# $drop removes the label ('label') or also the right tick numbers ('both'),
# so that the variants differ only in what they draw.
sub twin_fig {
    my ($scale, $how, $drop) = @_;
    my $f  = figure(width => 500, height => 300);
    my $ax = $f->axes;
    my $x  = sequence(11);
    $ax->line($x, $x);
    $ax->ylabel('left');
    my $tw = $ax->twinx;
    $tw->line($x, $x * $scale);
    $tw->set_right_ylabel('Humidity (%)') if $how eq 'right';
    $tw->ylabel('Humidity (%)')           if $how eq 'ylabel';
    $f->tight_layout;
    if ($drop) {
        $tw->set_right_ylabel('');
        $tw->ylabel('');
        $tw->yticks([]) if $drop eq 'both';
    }
    return ($f, $ax, $tw);
}

for my $scale (1, 1e3, 1e4) {          # tick numbers "10", "10000", "1.00e+05"
    for my $how ('right', 'ylabel') {
        my ($f, $ax) = twin_fig($scale, $how);

        my $full    = render_pixels($f);
        my $nolabel = render_pixels((twin_fig($scale, $how, 'label'))[0]);
        my $noboth  = render_pixels((twin_fig($scale, $how, 'both'))[0]);

        my ($lx0, $lx1) = diff_xrange($full, $nolabel);     # the right label
        my ($tx0, $tx1) = diff_xrange($nolabel, $noboth);   # right ticks and numbers
        ok(defined $lx0 && defined $tx0, "scale $scale, $how: label and numbers drawn")
            or next;
        cmp_ok($lx0, ">", $tx1 + 3, "scale $scale, $how: label starts past the numbers ($lx0 > $tx1 + 3)");
        cmp_ok($lx1, '<', $f->width, "scale $scale, $how: label inside the figure ($lx1 < " . $f->width . ")");
    }
}

# tight_layout leaves room for what _draw_twin_yaxis draws: wider numbers and
# a right label each widen the right margin.
{
    my @mr = map { (twin_fig(@$_))[1]->margin_right }
        ([1, ''], [1, 'right'], [1e4, 'right']);
    cmp_ok($mr[1], '>', $mr[0] + 8, "right label widens the margin ($mr[0] -> $mr[1])");
    cmp_ok($mr[2], '>', $mr[1] + 8, "wider numbers widen the margin ($mr[1] -> $mr[2])");
}

# set_right_ylabel wins over the twin's ylabel when both are given; the twin's
# ylabel is not drawn on the left either.
{
    my $f  = figure(width => 300, height => 200);
    my $tw = $f->axes->twinx;
    $tw->ylabel('B');
    is($tw->_twin_ylabel_text, 'B', 'twin ylabel used when no right label');
    $tw->set_right_ylabel('A');
    is($tw->_twin_ylabel_text, 'A', 'set_right_ylabel takes precedence');
}

done_testing;
