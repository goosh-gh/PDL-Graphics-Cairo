use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);

# legend(loc => 'outside top' | 'outside right' | 'outside'): the legend is
# drawn outside the axes frame, in room that tight_layout takes for it.

sub render {
    my ($f) = @_;
    my $d = PDL::Graphics::Cairo::Driver::Cairo->new(
        width => $f->width, height => $f->height, file => ':memory:');
    $f->_render_to($d);
    return $d;
}

# the inside legend box border is 0.6 grey (153), antialiased against white:
# neutral grey pixels; the data lines here are coloured, not grey
sub is_grey {
    my ($r, $g, $b) = @_;
    return $r == $g && $g == $b && $r >= 120 && $r <= 200;
}

sub make {
    my (%o) = @_;
    my $f = figure(width => $o{w} // 500, height => $o{h} // 260);
    my $ax = $f->axes;
    my $t = sequence(200) / 20;
    $ax->line($t, sin($t * $_), label => "ch$_") for 1 .. $o{n};
    $ax->set_title($o{title}) if defined $o{title};
    $ax->ylabel('amplitude');
    $ax->legend(loc => $o{loc}, (defined $o{max} ? (outside_max => $o{max}) : ()));
    $f->tight_layout;
    return ($f, $ax);
}

# ---- placement chosen by loc ----
{
    my %want = ('outside top' => 'top', 'outside right' => 'right',
                'upper right' => 'inside', 'lower left' => 'inside',
                'nonsense' => 'inside');
    for my $loc (sort keys %want) {
        my (undef, $ax) = make(n => 2, loc => $loc);
        is($ax->_legend_place, $want{$loc}, "loc '$loc' -> $want{$loc}");
    }
    my (undef, $a3) = make(n => 3, loc => 'outside');
    is($a3->_legend_place, 'top', "'outside' with 3 entries -> top");
    my (undef, $a4) = make(n => 4, loc => 'outside');
    is($a4->_legend_place, 'right', "'outside' with 4 entries -> right");
    my (undef, $a5) = make(n => 4, loc => 'outside', max => 5);
    is($a5->_legend_place, 'top', "'outside' with outside_max 5 and 4 entries -> top");
    my $f = figure(width => 300, height => 200);
    my $ax = $f->axes;
    $ax->line(sequence(5), sequence(5));     # no label
    $ax->legend(loc => 'outside right');
    is($ax->_legend_place, '', 'no labelled entries -> no legend');
}

# ---- outside top: above the frame, inside the figure, not on the title ----
for my $case (
    [ 'short title',  'STANDARD_10s.wav', 2, 'center-or-left' ],
    [ 'long title',   'STANDARD_10s.wav — slider 0: position / slider 1: width', 3, 'own row' ],
    [ 'no title',     undef, 2, 'own row' ],
) {
    my ($name, $title, $n, $kind) = @$case;
    my ($f, $ax) = make(n => $n, loc => 'outside top', title => $title);
    my $d = render($f);
    my $lt = $ax->{_legend_top_now};
    ok($lt, "$name: layout made in draw");
    my ($ml, $mr, $mt) = ($ax->_plot_ml, $ax->_plot_mr, $ax->_plot_mt);
    my $ybot = $lt->{yc} + 10;
    my $ytop = $lt->{yc} - 10;
    cmp_ok($ybot, '<=', $mt, "$name: legend row ends above the frame ($ybot <= $mt)");
    cmp_ok($ytop, '>=', 0, "$name: legend row starts inside the figure ($ytop)");
    cmp_ok(abs($lt->{x0} + $lt->{row_w} - $mr), '<', 1, "$name: right-aligned to the frame");
    if (defined $title) {
        # title box: bottom at mt - 14 - title_up, measured width/height
        $d->set_font(size => 13, weight => 'bold');
        my ($tw, $th) = $d->text_size($title);
        my $tb = $mt - 14 - $lt->{title_up};
        my $tx0 = $lt->{title_align} eq 'left' ? $ml : ($ml + $mr) / 2 - $tw / 2;
        my $tx1 = $tx0 + $tw;
        my $sep_x = $tx1 <= $lt->{x0};
        my $sep_y = $tb <= $ytop;
        ok($sep_x || $sep_y, "$name: title and legend do not overlap");
        cmp_ok($tb - $th, '>=', 0, "$name: title inside the figure");
        is(($lt->{title_up} ? 'own row' : 'center-or-left'), $kind, "$name: $kind");
    }
}

# ---- outside right: frame narrower, legend column right of it, in the figure ----
{
    my ($f0, $a0) = make(n => 7, loc => 'upper right');
    my ($f1, $a1) = make(n => 7, loc => 'outside right');
    my $m = PDL::Graphics::Cairo::Figure::_measure_driver();
    my $g = $a1->_legend_geom($m);
    cmp_ok($a1->margin_right - $a0->margin_right, '>=', $g->{col_w},
        'outside right: margin_right grows by at least the legend column');
    my $d = render($f1);
    my $mr = $a1->_plot_mr;
    my $lx = $a1->fig_x + $a1->width - $g->{col_w} - 4;
    cmp_ok($lx, '>=', $mr + 10, 'legend column starts right of the frame');
    cmp_ok($lx + $g->{col_w}, '<=', $f1->width, 'and ends inside the figure');

    # pixels: in the frame, at the rows of the legend entries, the colours of
    # the outside-right legend do not appear where the inside box would be
    my $s = $d->{surface}; $s->flush;
    my $raw = $s->get_data; my $stride = $s->get_stride;
    my $grey = 0;      # the inside legend box border is 0.6 grey (153)
    for my $y (int($a1->_plot_mt) + 6 .. int($a1->_plot_mt) + 40) {
        for my $x (int($mr) - 60 .. int($mr) - 2) {
            my ($b, $gg, $r) = unpack 'C3', substr($raw, $y * $stride + 4 * $x, 3);
            $grey++ if is_grey($r, $gg, $b);
        }
    }
    is($grey, 0, 'no legend box border inside the frame');
}

# negative control: the inside legend does draw its grey box there
{
    my ($f, $ax) = make(n => 7, loc => 'upper right');
    my $d = render($f);
    my $s = $d->{surface}; $s->flush;
    my $raw = $s->get_data; my $stride = $s->get_stride;
    my $grey = 0;
    my $mr = $ax->_plot_mr;
    for my $y (int($ax->_plot_mt) + 2 .. int($ax->_plot_mt) + 40) {
        for my $x (int($mr) - 200 .. int($mr) - 2) {
            my ($b, $gg, $r) = unpack 'C3', substr($raw, $y * $stride + 4 * $x, 3);
            $grey++ if is_grey($r, $gg, $b);
        }
    }
    cmp_ok($grey, '>', 20, "control: 'upper right' draws its grey box in the frame ($grey px)");
}

# ---- uniform_margins: the legend column is taken on every panel ----
{
    my $f = figure(width => 600, height => 400);
    my @a = $f->subplots(2, 1);
    $a[0]->line(sequence(5), sequence(5), label => "ch$_") for 1 .. 5;
    $a[0]->legend(loc => 'outside right');
    $a[1]->line(sequence(5), sequence(5));
    $f->tight_layout(uniform_margins => 1);
    is($a[0]->margin_right, $a[1]->margin_right, 'uniform_margins: same margin_right on both panels');
}

done_testing;
