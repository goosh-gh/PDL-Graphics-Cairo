use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);

# tight_layout leaves room for the tick numbers, ylabel, xlabel and title it
# measures (Axes::_label_room), so that none of them is cut at the edge of the
# figure. Before P:G:C30 the left margin was a fixed 70 px: with tick numbers
# like "-2.00e+04" the ylabel was drawn outside the figure, and in a low figure
# the xlabel was cut at the bottom.

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

# bounding box (x0, x1, y0, y1) of the pixels where two renders differ
sub diff_bbox {
    my ($p, $q) = @_;
    my $d = (($p->long - $q->long)->abs->sumover > 30);   # (W, H)
    my $cols = $d->mv(1, 0)->sumover;                      # per x
    my $rows = $d->sumover;                                # per y
    my $xs = which($cols > 0);
    my $ys = which($rows > 0);
    return () unless $xs->nelem && $ys->nelem;
    return ($xs->min->sclr, $xs->max->sclr, $ys->min->sclr, $ys->max->sclr);
}

sub make_fig {
    my (%o) = @_;
    my $f = figure(width => $o{w}, height => $o{h});
    my @a = $f->subplots(2, 1);
    my $t = sequence(200) / 20;
    for my $ax (@a) {
        $ax->line($t, sin($t * 3) * ($o{amp} // 2e4));
        $ax->ylabel('amplitude') if $o{ylabel};
    }
    $a[1]->xlabel('time (s)') if $o{xlabel};
    $f->tight_layout;
    $o{after}->(@a) if $o{after};
    return ($f, @a);
}

# ---- ylabel with long tick numbers: inside the figure at every width ----
for my $w (300, 500, 900) {
    my ($f1) = make_fig(w => $w, h => 300, ylabel => 1);
    my ($f0) = make_fig(w => $w, h => 300, ylabel => 0);
    my @bb = diff_bbox(render_pixels($f1), render_pixels($f0));
    ok(@bb, "w=$w: the ylabel is drawn");
    cmp_ok($bb[0], '>', 0, "w=$w: ylabel ink does not touch the left edge (x0=$bb[0])");
}

# the numbers themselves: the minus sign of -2.00e+04 is inside the figure
{
    my ($f, @a) = make_fig(w => 500, h => 300, ylabel => 0);
    my $p = render_pixels($f);
    my $col0 = $p->slice('0:2,0,:')->long->sumover;   # B+G+R of column 0, per y
    ok(($col0 < 3 * 255 - 30)->sum->sclr == 0, 'nothing is drawn in column 0');
}

# negative control: the same check sees a cut ylabel when the margin is too small
{
    my $narrow = sub { $_->margin_left(40) for @_ };
    my ($f1) = make_fig(w => 500, h => 300, ylabel => 1, after => $narrow);
    my ($f0) = make_fig(w => 500, h => 300, ylabel => 0, after => $narrow);
    my @bb = diff_bbox(render_pixels($f1), render_pixels($f0));
    ok(!@bb || $bb[0] == 0,
       'control: with margin_left 40 the ylabel is cut at x=0 or not visible at all');
    my $part = sub { $_->margin_left(80) for @_ };
    ($f1) = make_fig(w => 500, h => 300, ylabel => 1, after => $part);
    ($f0) = make_fig(w => 500, h => 300, ylabel => 0, after => $part);
    @bb = diff_bbox(render_pixels($f1), render_pixels($f0));
    is($bb[0], 0, 'control: with margin_left 80 the ylabel ink reaches x=0');
}

# ---- xlabel in a low figure: inside the figure ----
# (Below about 250 px for two rows the margins are still capped at 80% of the
# cell, to leave a plot area, and the xlabel can be cut.)
for my $h (250, 300) {
    my ($f1) = make_fig(w => 300, h => $h, xlabel => 1);
    my ($f0) = make_fig(w => 300, h => $h, xlabel => 0);
    my @bb = diff_bbox(render_pixels($f1), render_pixels($f0));
    ok(@bb, "h=$h: the xlabel is drawn");
    cmp_ok($bb[3], '<', $h - 1, "h=$h: xlabel ink does not touch the bottom edge (y1=$bb[3])");
}
{
    my $short = sub { $_[1]->margin_bottom(40) };
    my ($f1) = make_fig(w => 300, h => 250, xlabel => 1, after => $short);
    my ($f0) = make_fig(w => 300, h => 250, xlabel => 0, after => $short);
    my @bb = diff_bbox(render_pixels($f1), render_pixels($f0));
    is($bb[3], 249, 'control: with margin_bottom 40 the xlabel ink reaches the bottom row');
}

# ---- figures whose labels fit keep the margins they had ----
{
    my ($f, @a) = make_fig(w => 400, h => 300, ylabel => 1, xlabel => 1, amp => 1);
    is($a[0]->margin_left, 70, 'short tick numbers: margin_left stays 70');
    is($a[1]->margin_bottom, 56, 'margin_bottom with xlabel stays 56');
}

# ---- the room follows the range (no stale cache) ----
{
    my $m = PDL::Graphics::Cairo::Figure::_measure_driver();
    my $f = figure(width => 400, height => 300);
    my $ax = $f->axes;
    $ax->line(sequence(5), sequence(5));
    $ax->ylabel('y');
    my ($l1) = $ax->_label_room($m, 0);
    $ax->ylim(-20000, 20000);
    my ($l2) = $ax->_label_room($m, 0);
    cmp_ok($l2, '>', $l1 + 20, "longer tick numbers need more room ($l1 -> $l2)");
    $ax->ylim(0, 4);
    my ($l3) = $ax->_label_room($m, 0);
    is($l3, $l1, 'and the same range gives the same room again');
    is_deeply([ $ax->ymin, $ax->ymax ], [0, 4], '_label_room leaves the user ylim as it was');
    my $g = figure(width => 400, height => 300);
    my $bx = $g->axes;
    $bx->line(sequence(5), sequence(5));
    $bx->_label_room($m, 0);
    ok(!defined $bx->ymin, '... and an autoscaled ylim undefined');
}

# ---- uniform_margins: every panel gets the largest room ----
{
    my $f = figure(width => 600, height => 400);
    my @rows = $f->subplots(2, 2);
    my @a = map { @$_ } @rows;
    $_->line(sequence(5), sequence(5)) for @a;
    $a[3]->ylim(-20000, 20000);
    $a[3]->ylabel('uV');
    $f->tight_layout(uniform_margins => 1);
    my %ml = map { $_->margin_left => 1 } @a;
    is(scalar keys %ml, 1, 'uniform_margins: one margin_left for all panels');
    my $m = PDL::Graphics::Cairo::Figure::_measure_driver();
    my ($need) = $a[3]->_label_room($m, 1);
    cmp_ok($a[0]->margin_left, '>=', $need, 'and it holds the widest panel');
}

done_testing;
