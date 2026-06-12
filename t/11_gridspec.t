use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots subplot_mosaic);
use PDL::Graphics::Cairo::GridSpec;

# ----------------------------------------------------------------
# 1. GridSpec basic construction
# ----------------------------------------------------------------
{
    my $fig = figure(width=>600, height=>400);
    my $gs  = $fig->add_gridspec(2, 3);
    isa_ok $gs, 'PDL::Graphics::Cairo::GridSpec', 'add_gridspec returns GridSpec';
    is $gs->nrows, 2, 'nrows=2';
    is $gs->ncols, 3, 'ncols=3';
}

# ----------------------------------------------------------------
# 2. GridSpec->at() returns GridSpecCell
# ----------------------------------------------------------------
{
    my $fig = figure(width=>600, height=>400);
    my $gs  = $fig->add_gridspec(2, 3);
    my $cell = $gs->at(0, 0);
    isa_ok $cell, 'PDL::Graphics::Cairo::GridSpecCell', 'at() returns GridSpecCell';
    is $cell->r0, 0, 'r0=0';
    is $cell->r1, 1, 'r1=1 (single row)';
    is $cell->c0, 0, 'c0=0';
    is $cell->c1, 1, 'c1=1 (single col)';
}

# ----------------------------------------------------------------
# 3. Slice notation
# ----------------------------------------------------------------
{
    my $fig = figure(width=>600, height=>400);
    my $gs  = $fig->add_gridspec(2, 3);

    my $cell_row = $gs->at(0, ':');     # row 0, all cols
    is $cell_row->c0, 0, 'slice : c0=0';
    is $cell_row->c1, 3, 'slice : c1=3';

    my $cell_span = $gs->at('1:2', '0:2');
    is $cell_span->r0, 1, 'slice 1:2 r0=1';
    is $cell_span->r1, 2, 'slice 1:2 r1=2';
    is $cell_span->c0, 0, 'slice 0:2 c0=0';
    is $cell_span->c1, 2, 'slice 0:2 c1=2';
}

# ----------------------------------------------------------------
# 4. pixel_rect produces reasonable values
# ----------------------------------------------------------------
{
    my $fig = figure(width=>600, height=>400);
    my $gs  = $fig->add_gridspec(2, 2);

    my ($x, $y, $w, $h) = $gs->at(0,0)->pixel_rect;
    ok $x >= 0 && $x < 300, "top-left x in range ($x)";
    ok $y >= 0 && $y < 200, "top-left y in range ($y)";
    ok $w > 50,              "width reasonable ($w)";
    ok $h > 50,              "height reasonable ($h)";

    my ($x2,$y2,$w2,$h2) = $gs->at(0,1)->pixel_rect;
    ok $x2 > $x, "right cell x > left cell x";

    my ($x3,$y3,$w3,$h3) = $gs->at(1,0)->pixel_rect;
    ok $y3 > $y, "bottom cell y > top cell y";
}

# ----------------------------------------------------------------
# 5. add_subplot(cell) creates Axes with correct position
# ----------------------------------------------------------------
{
    my $fig = figure(width=>600, height=>400);
    my $gs  = $fig->add_gridspec(2, 2);
    my $ax  = $fig->add_subplot($gs->at(0,0));
    isa_ok $ax, 'PDL::Graphics::Cairo::Axes', 'add_subplot(cell) returns Axes';
    ok $ax->width  > 0, 'Axes width > 0';
    ok $ax->height > 0, 'Axes height > 0';
}

# ----------------------------------------------------------------
# 6. PNG smoke: GridSpec 2x3 with span
# ----------------------------------------------------------------
{
    my $fig = figure(width=>800, height=>500);
    my $gs  = $fig->add_gridspec(2, 3);

    my $ax1 = $fig->add_subplot($gs->at(0, ':'));   # top row full width
    my $ax2 = $fig->add_subplot($gs->at(1, 0));
    my $ax3 = $fig->add_subplot($gs->at(1, '1:'));  # bottom right 2 cols

    $ax1->line(pdl(0..5), pdl(0,1,4,9,16,25));
    $ax2->scatter(pdl(1..4), pdl(2,4,1,3));
    $ax3->bar(pdl(1..3), pdl(3,1,4));

    $fig->suptitle('GridSpec Demo');
    $fig->tight_layout;

    my $tmp = "/tmp/gridspec_smoke_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "GridSpec 2x3 smoke: no die ($@)";
    ok -f $tmp && -s $tmp > 1000, 'PNG has content';
    unlink $tmp;
}

# ----------------------------------------------------------------
# 7. subplot_mosaic basic: "AB\nCC"
# ----------------------------------------------------------------
{
    my ($fig, %ax) = subplot_mosaic("AB\nCC", width=>600, height=>400);
    isa_ok $fig, 'PDL::Graphics::Cairo::Figure', 'subplot_mosaic returns Figure';
    isa_ok $ax{A}, 'PDL::Graphics::Cairo::Axes', 'ax{A} is Axes';
    isa_ok $ax{B}, 'PDL::Graphics::Cairo::Axes', 'ax{B} is Axes';
    isa_ok $ax{C}, 'PDL::Graphics::Cairo::Axes', 'ax{C} is Axes';
    is scalar(keys %ax), 3, '3 unique axes';
}

# ----------------------------------------------------------------
# 8. subplot_mosaic: C spans full width (c0=0, c1=2)
# ----------------------------------------------------------------
{
    my ($fig, %ax) = subplot_mosaic("AB\nCC", width=>600, height=>400);
    my ($gsinfo_c) = grep { $_->{ax} == $ax{C} } @{ $fig->_gs_axes };
    is $gsinfo_c->{c0}, 0, 'C c0=0';
    is $gsinfo_c->{c1}, 2, 'C c1=2 (spans full width)';
    is $gsinfo_c->{r0}, 1, 'C r0=1 (second row)';
}

# ----------------------------------------------------------------
# 9. subplot_mosaic PNG smoke
# ----------------------------------------------------------------
{
    my ($fig, %ax) = subplot_mosaic("AB\nCC", width=>700, height=>500);
    $ax{A}->line(pdl(0..4), pdl(0,1,4,9,16));
    $ax{B}->scatter(pdl(1..5), pdl(2,4,1,5,3));
    $ax{C}->bar(pdl(1..4), pdl(4,2,3,1));
    $ax{A}->title('Panel A');
    $ax{B}->title('Panel B');
    $fig->suptitle('Mosaic Layout');
    $fig->tight_layout;

    my $tmp = "/tmp/mosaic_smoke_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "subplot_mosaic smoke: no die ($@)";
    ok -f $tmp && -s $tmp > 1000, 'PNG has content';
    unlink $tmp;
}

# ----------------------------------------------------------------
# 10. subplot_mosaic with arrayref layout
# ----------------------------------------------------------------
{
    my ($fig, %ax) = subplot_mosaic(
        [['X','X'],['Y','Z']],
        width=>600, height=>400);
    isa_ok $ax{X}, 'PDL::Graphics::Cairo::Axes', 'arrayref layout: X';
    isa_ok $ax{Y}, 'PDL::Graphics::Cairo::Axes', 'arrayref layout: Y';
    isa_ok $ax{Z}, 'PDL::Graphics::Cairo::Axes', 'arrayref layout: Z';
    my ($gsinfo_x) = grep { $_->{ax} == $ax{X} } @{ $fig->_gs_axes };
    is $gsinfo_x->{c1}, 2, 'X spans 2 cols';
}

# ----------------------------------------------------------------
# 11. GridSpec with hspace/wspace options
# ----------------------------------------------------------------
{
    my $fig = figure(width=>600, height=>400);
    my $gs  = $fig->add_gridspec(2, 2, hspace=>0.5, wspace=>0.5);
    is $gs->hspace, 0.5, 'hspace stored';
    is $gs->wspace, 0.5, 'wspace stored';
    my ($x0,$y0,$w0,$h0) = $gs->at(0,0)->pixel_rect;
    my ($x1,$y1,$w1,$h1) = $gs->at(0,1)->pixel_rect;
    ok $x1 - ($x0+$w0) > 5, 'larger wspace creates gap';
}

# ----------------------------------------------------------------
# 12. add_subplot(nrows,ncols,idx) still works (regression)
# ----------------------------------------------------------------
{
    my $fig = figure(width=>400, height=>300);
    my $ax = $fig->add_subplot(2, 2, 1);
    isa_ok $ax, 'PDL::Graphics::Cairo::Axes', 'add_subplot(r,c,i) regression';
}

done_testing;
