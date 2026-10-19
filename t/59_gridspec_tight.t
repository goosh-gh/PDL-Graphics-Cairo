use strict;
use warnings;
use utf8;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplot_mosaic);

# An explicit $fig->tight_layout places the panels of a GridSpec /
# subplot_mosaic from what each
# needs around its plot rectangle (Figure::_tight_gridspec), as matplotlib's
# tight_layout does: plot rectangles of a row (column) line up, the panels'
# boxes (plot rectangle + room for numbers, labels, title, colorbar) do not
# overlap and stay inside the figure, and the gaps are no wider than the
# rooms plus GS_PAD. Up to 0.42 the GridSpec's own hspace/wspace gap was kept
# and fixed margins were added inside each cell, so most of the figure was
# empty (examples/example_gridspec.pl).

sub plot_rect {          # (x0, y0, x1, y1) of the plot rectangle
    my ($ax) = @_;
    return ($ax->fig_x + $ax->margin_left, $ax->fig_y + $ax->margin_top,
            $ax->fig_x + $ax->width - $ax->margin_right,
            $ax->fig_y + $ax->height - $ax->margin_bottom);
}
sub box {                # (x0, y0, x1, y1) of the whole Axes box
    my ($ax) = @_;
    return ($ax->fig_x, $ax->fig_y, $ax->fig_x + $ax->width, $ax->fig_y + $ax->height);
}
sub overlap {
    my ($p, $q) = @_;
    return $p->[0] < $q->[2] - 0.5 && $q->[0] < $p->[2] - 0.5
        && $p->[1] < $q->[3] - 0.5 && $q->[1] < $p->[3] - 0.5;
}

my $x = sequence(20);

# mosaic "AAB / CDB / CDE" with labels, a colorbar and a heatmap
{
    my ($fig, %ax) = subplot_mosaic("AAB\nCDB\nCDE", width => 800, height => 650,
        hspace => 0.45, wspace => 0.40);
    $ax{A}->line($x, $x); $ax{A}->xlabel('Frequency (Hz)'); $ax{A}->ylabel('Power');
    $ax{A}->title('A: spectrum');
    $ax{B}->barh(pdl(1..5), pdl(4, 3, 5, 2, 3)); $ax{B}->title('B');
    $ax{C}->scatter($x, $x); $ax{C}->title('C');
    $ax{D}->heatmap(sequence(6, 6)); $ax{D}->title('D');
    $ax{E}->hist(sin($x), bins => 5); $ax{E}->title('E');
    $fig->suptitle('mosaic');
    $fig->tight_layout;

    my %pr = map { $_ => [ plot_rect($ax{$_}) ] } keys %ax;
    my %bx = map { $_ => [ box($ax{$_}) ] } keys %ax;

    # rows: A top = B top; C top = D top; C, D, E bottom; columns: A left = C left
    is($pr{A}[1], $pr{B}[1], 'A and B start on the same row line');
    is($pr{C}[1], $pr{D}[1], 'C and D start on the same row line');
    is($pr{C}[3], $pr{D}[3], 'C and D end on the same row line');
    is($pr{D}[3], $pr{E}[3], 'D and E end on the same row line');
    is($pr{A}[0], $pr{C}[0], 'A and C start on the same column line');
    is($pr{A}[2], $pr{D}[2], 'A and D end on the same column line');
    is($pr{B}[2], $pr{E}[2], 'B and E end on the same column line');

    my @k = sort keys %ax;
    my $ov = 0;
    for my $i (0 .. $#k) { for my $j ($i + 1 .. $#k) {
        $ov++ if overlap($bx{ $k[$i] }, $bx{ $k[$j] });
    } }
    is($ov, 0, 'no two panel boxes overlap');
    my $out = grep { $_->[0] < 0 || $_->[1] < 0 || $_->[2] > 800 || $_->[3] > 650 } values %bx;
    is($out, 0, 'all panel boxes inside the figure');

    # gaps no wider than the two rooms + pad (10 px)
    my $gap_cd = $pr{D}[0] - $pr{C}[2];
    my $room_cd = $ax{C}->margin_right + $ax{D}->margin_left;
    cmp_ok($gap_cd, '<=', $room_cd + 11, "gap C-D $gap_cd px <= rooms $room_cd + pad");
    # the panels use most of the figure (0.42: A's plot rectangle was 25 px high)
    cmp_ok($pr{A}[3] - $pr{A}[1], '>', 80, 'A is not squashed (' . ($pr{A}[3] - $pr{A}[1]) . ' px high)');
}

# two columns, the left panel with a long ylabel and wide numbers: the right
# panel's box starts after the left one's
{
    my $fig = figure(width => 600, height => 300);
    my $gs  = $fig->add_gridspec(1, 2, wspace => 0.0);
    my $a1 = $fig->add_subplot($gs->at(0, 0));
    my $a2 = $fig->add_subplot($gs->at(0, 1));
    $a1->line($x, $x * 1e5); $a1->ylabel('a long label');
    $a2->line($x, -$x * 1e5); $a2->ylabel('another');
    $fig->tight_layout;
    ok(!overlap([ box($a1) ], [ box($a2) ]), 'wspace 0: the boxes still do not overlap');
    my @p1 = plot_rect($a1); my @p2 = plot_rect($a2);
    is($p2[2] - $p2[0], $p1[2] - $p1[0], 'equal columns: equal plot widths');
}

# width_ratios / height_ratios share the plot sizes
{
    my $fig = figure(width => 600, height => 400);
    my $gs  = $fig->add_gridspec(2, 2, width_ratios => [2, 1], height_ratios => [1, 3]);
    my @a = map { my $r = $_; map { $fig->add_subplot($gs->at($r, $_)) } 0, 1 } 0, 1;
    $_->line($x, $x) for @a;
    $fig->tight_layout;
    my @w = map { my @p = plot_rect($_); $p[2] - $p[0] } @a[0, 1];
    my @h = map { my @p = plot_rect($_); $p[3] - $p[1] } @a[0, 2];
    cmp_ok(abs($w[0] / $w[1] - 2), '<', 0.03, "width ratio 2:1 ($w[0]:$w[1])");
    cmp_ok(abs($h[1] / $h[0] - 3), '<', 0.05, "height ratio 1:3 ($h[0]:$h[1])");
}

# cell_margins: the GridSpec's own cells are kept (t/44 covers the details)
{
    my $fig = figure(width => 400, height => 300);
    my $gs  = $fig->add_gridspec(1, 2, cell_margins => 0, left => 0.1, right => 0.9, wspace => 0.2);
    my $a1 = $fig->add_subplot($gs->at(0, 0));
    my @before = box($a1);
    $a1->line($x, $x);
    $fig->tight_layout;
    is_deeply([ box($a1) ], \@before, 'cell_margins: the cell is not moved');
}

# Only an explicit $fig->tight_layout moves the cells: when save/show apply
# the layout by themselves, the GridSpec's bounds and gaps are kept.
{
    my $fig = figure(width => 400, height => 300);
    my $gs  = $fig->add_gridspec(1, 2, left => 0.02, right => 0.98, wspace => 0.1);
    my $a1  = $fig->add_subplot($gs->at(0, 0));
    my @before = box($a1);
    $a1->line($x, $x);
    $fig->to_png;                      # applies tight_layout by itself
    is_deeply([ box($a1) ], \@before, 'implicit layout: the cell is not moved');
}

# A panel placed with set_position is not moved.
{
    my $fig = figure(width => 400, height => 300);
    my $gs  = $fig->add_gridspec(1, 2);
    my $a1  = $fig->add_subplot($gs->at(0, 0));
    my $a2  = $fig->add_subplot($gs->at(0, 1));
    $a1->set_position([0.1, 0.1, 0.3, 0.8]);
    my @before = box($a1);
    $_->line($x, $x) for $a1, $a2;
    $fig->tight_layout;
    is_deeply([ box($a1) ], \@before, 'set_position: the panel is not moved');
}

done_testing;
