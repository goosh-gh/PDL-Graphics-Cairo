use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
use PDL;
use Cairo;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::ColorMap;

# add_gridspec(cell_margins), Figure::label_only / label_outer,
# colorbar(cmap => ..., reserve => 0) and the margin guard of narrow cells.

my ($fh, $png) = tempfile(SUFFIX => '.png', UNLINK => 1);
close $fh;
my ($W, $H) = (1100, 850);

# 5x5 grid with 6 empty cells (the 10-20 layout): corners and (4,2)
my @CELLS = ([0, 1], [0, 3], (map { my $r = $_; map { [$r, $_] } 0 .. 4 } 1 .. 3), [4, 1], [4, 3]);
sub holey {
    my (%gs) = @_;
    my $fig = figure(width => $W, height => $H);
    my $gs  = $fig->add_gridspec(5, 5, left => 0.02, right => 0.98, top => 0.955,
                                 bottom => 0.045, wspace => 0.12, hspace => 0.17, %gs);
    my @ax;
    for my $c (@CELLS) {
        my $ax = $fig->add_subplot($gs->at(@$c));
        $ax->line(pdl(-250, 800), pdl(-5, 5));
        $ax->xlim(-250, 800); $ax->set_ylim(-5, 5);
        push @ax, $ax;
    }
    return ($fig, $gs, @ax);
}
sub rect  { my ($ax) = @_; ($ax->_plot_ml, $ax->_plot_mt, $ax->_plot_mr, $ax->_plot_mb) }
sub sizes { my %s; $s{ sprintf('%.0fx%.0f', $_->_plot_mr - $_->_plot_ml, $_->_plot_mb - $_->_plot_mt) }++ for @_; \%s }

# ---- default: the plot areas differ with the position in the grid --------------
{
    my ($fig, $gs, @ax) = holey();
    $fig->save($png);
    cmp_ok(scalar keys %{ sizes(@ax) }, '>', 1, 'without cell_margins the plot areas are not all the same');
}

# ---- cell_margins => 0: every plot rectangle is its grid cell -------------------
{
    my ($fig, $gs, @ax) = holey(cell_margins => 0);
    $fig->save($png);
    my $s = sizes(@ax);
    is(scalar keys %$s, 1, 'cell_margins => 0: 19 panels, one plot-area size (' . join(',', keys %$s) . ')');
    my $ok = 1;
    for my $i (0 .. $#ax) {
        my ($x, $y, $w, $h) = $gs->pixel_rect($CELLS[$i][0], $CELLS[$i][0] + 1, $CELLS[$i][1], $CELLS[$i][1] + 1);
        my @r = rect($ax[$i]);
        $ok = 0 unless $r[0] == $x && $r[1] == $y && $r[2] == $x + $w && $r[3] == $y + $h;
    }
    ok($ok, 'cell_margins => 0: each plot rectangle is exactly the pixel rectangle of its cell');
    # same again after an explicit tight_layout, with or without uniform_margins
    $fig->tight_layout(uniform_margins => 1);
    $fig->save($png);
    is_deeply(sizes(@ax), $s, 'unchanged by tight_layout(uniform_margins => 1)');
}

# ---- number and hash forms ------------------------------------------------------
{
    my ($fig, $gs, @ax) = holey(cell_margins => 6);
    $fig->save($png);
    is_deeply([ map { $ax[0]->$_ } qw(margin_left margin_right margin_top margin_bottom) ], [6, 6, 6, 6],
              'cell_margins => 6: 6 px on every side');
    is(scalar keys %{ sizes(@ax) }, 1, 'cell_margins => 6: one plot-area size');

    ($fig, $gs, @ax) = holey(cell_margins => { left => 30, bottom => 20 });
    $fig->save($png);
    is_deeply([ map { $ax[7]->$_ } qw(margin_left margin_right margin_top margin_bottom) ], [30, 0, 0, 20],
              'cell_margins => { left, bottom }: unnamed sides are 0');
    is(scalar keys %{ sizes(@ax) }, 1, 'hash form: one plot-area size');

    is_deeply([ $fig->add_gridspec(2, 2)->cell_margins_px ], [], 'cell_margins unset: cell_margins_px is empty');
    eval { $fig->add_gridspec(2, 2, cell_margins => { lft => 3 })->cell_margins_px };
    like($@, qr/no side 'lft'/, 'unknown side in the hash dies');
    eval { $fig->add_gridspec(2, 2, cell_margins => [1, 2, 3, 4])->cell_margins_px };
    like($@, qr/number or a hash/, 'array reference dies');
}

# ---- label_only / label_outer ---------------------------------------------------
sub numbered {
    my ($which, @ax) = @_;      # indices of the panels that show the numbers of that axis
    my $key = $which eq 'x' ? 'x_labelbottom' : 'y_labelleft';
    return [ grep { $ax[$_]->_tick_params->{$key} // 1 } 0 .. $#ax ];
}
{
    my ($fig, $gs, @ax) = holey(cell_margins => 0);
    my $o1 = 17;                                                  # cell (4,1)
    $fig->label_only($ax[$o1]);
    is_deeply(numbered('x', @ax), [$o1], 'label_only: x numbers on that panel only');
    is_deeply(numbered('y', @ax), [$o1], 'label_only: y numbers on that panel only');

    $fig->label_outer;
    # leftmost of each row: (0,1) (1,0) (2,0) (3,0) (4,1); lowest of each column:
    # (3,0) (4,1) (3,2) (4,3) (3,4)
    is_deeply(numbered('y', @ax), [0, 2, 7, 12, 17], 'label_outer: y numbers on the leftmost panel of each row');
    is_deeply(numbered('x', @ax), [12, 14, 16, 17, 18], 'label_outer: x numbers on the lowest panel of each column');

    $fig->label_only([ @ax[0, 1] ], axis => 'x');
    is_deeply(numbered('x', @ax), [0, 1], 'label_only(axis => x) with a list of panels');
    is_deeply(numbered('y', @ax), [0, 2, 7, 12, 17], 'label_only(axis => x) leaves the y numbers');

    # an axis('off') panel is left alone and does not count as an edge
    my $map = $fig->add_subplot($gs->at(0, 2));
    $map->axis('off');
    $fig->label_outer;
    ok(!exists $map->_tick_params->{x_labelbottom}, 'label_outer does not touch an axis(off) panel');
    eval { $fig->save($png) };
    ok(!$@ && -s $png, "figure with numbers on some panels renders ($@)");
}

# ---- colorbar(cmap => ...) on an axis('off') panel ------------------------------
sub red_at {                       # is there a strongly red pixel in the box?
    my ($file, $x0, $y0, $x1, $y1) = @_;
    my $s = Cairo::ImageSurface->create_from_png($file);
    my ($data, $stride) = ($s->get_data, $s->get_stride);
    for my $y (int($y0) .. int($y1)) { for my $x (int($x0) .. int($x1)) {
        my ($b, $g, $r) = unpack 'C3', substr($data, $y * $stride + 4 * $x, 3);
        return 1 if $r > 150 && $g < 80 && $b < 80;
    } }
    return 0;
}
{
    my $img = zeroes(3, 40, 40) + 1;                              # white RGB image
    my $cm  = PDL::Graphics::Cairo::ColorMap->new('jet');           # red at the top
    for my $reserve (1, 0) {
        my $fig = figure(width => 600, height => 300);
        my $gs  = $fig->add_gridspec(1, 3, left => 0.05, right => 0.95, top => 0.9, bottom => 0.1,
                                     wspace => 0.2, cell_margins => 0);
        my $ax  = $fig->add_subplot($gs->at(0, 1));
        $ax->imshow($img->mv(0, 2), origin => 'lower');
        $ax->set_aspect('equal'); $ax->axis('off');
        $ax->_colorbar(undef);
        ok(!$ax->_colorbar_shown, 'no colorbar yet') if $reserve;
        $ax->colorbar(cmap => ($reserve ? $cm : 'jet'), vmin => -3, vmax => 3, width => 8, pad => 3,
                      reserve => $reserve);          # object and name
        ok($ax->_colorbar_shown, "colorbar(cmap) is shown on an axis(off) panel (reserve => $reserve)");
        $fig->save($png);
        if ($reserve) {
            cmp_ok($ax->margin_right, '>', 8 + 3, 'reserve default: the right margin makes room for the bar');
        } else {
            is($ax->margin_right, 0, 'reserve => 0: the margins stay those of the grid');
            my ($cx, $cy) = ($ax->fig_x + $ax->width / 2, $ax->fig_y + $ax->height / 2);
            cmp_ok(abs(($ax->_plot_ml + $ax->_plot_mr) / 2 - $cx), '<', 0.5,
                   'reserve => 0: the equal-aspect image stays centred in its cell');
        }
        # the bar is right of the image: red (vmax end) in its upper part
        my ($l, $t, $r, $b) = rect($ax);
        ok(red_at($png, $r + 3, $t, $r + 3 + 8, $t + 0.2 * ($b - $t)), 'the bar is drawn right of the image');
    }
    my $ax = figure()->axes;
    eval { $ax->colorbar(cmap => $cm) };
    like($@, qr/needs vmin and vmax/, 'colorbar(cmap) without limits dies');

    # tick_step: ticks at the multiples of the step, thinned on a short bar
    $ax->colorbar(cmap => $cm, vmin => -3, vmax => 3, tick_step => 1);
    is_deeply([ $ax->_colorbar_ticks(200, 10) ], [-3 .. 3], 'tick_step => 1 on +-3: every integer');
    $ax->colorbar(cmap => $cm, vmin => -2.6, vmax => 2.6, tick_step => 1);
    is_deeply([ $ax->_colorbar_ticks(200, 10) ], [-2 .. 2], 'limits between multiples: the multiples inside');
    $ax->colorbar(cmap => $cm, vmin => -1, vmax => 1, tick_step => 0.5);
    is_deeply([ $ax->_colorbar_ticks(200, 10) ], [-1, -0.5, 0, 0.5, 1], 'tick_step => 0.5');
    $ax->colorbar(cmap => $cm, vmin => -12, vmax => 12, tick_step => 1);
    is_deeply([ $ax->_colorbar_ticks(80, 10) ], [-12, -9, -6, -3, 0, 3, 6, 9, 12],
              'short bar (3.3 px per step, 10 px per number): every 3rd multiple, 0 among them');
    is_deeply([ $ax->_colorbar_ticks ], [-12 .. 12], 'no bar length given: not thinned');
    $ax->colorbar(cmap => $cm, vmin => 0.2, vmax => 0.4, tick_step => 1);
    is_deeply([ $ax->_colorbar_ticks(80, 10) ], [], 'no multiple inside the limits: no ticks');
    $ax->colorbar(cmap => $cm, vmin => -3, vmax => 3);
    ok(!defined $ax->colorbar_tick_step, 'a later colorbar() without tick_step goes back to automatic ticks');
    eval { $ax->colorbar(tick_step => 0) };
    like($@, qr/tick_step must be positive/, 'tick_step => 0 dies');
}

# ---- a cell narrower than its margins still gets a plot rectangle ---------------
{
    my $fig = figure(width => 1100, height => 400);
    my $gs  = $fig->add_gridspec(1, 2, width_ratios => [40, 1], left => 0.05, right => 0.99, wspace => 0.02);
    my $ax  = $fig->add_subplot($gs->at(0, 0));
    my $cax = $fig->add_subplot($gs->at(0, 1));
    $ax->line(pdl(0, 1), pdl(0, 1));
    $cax->line(pdl(0, 1), pdl(0, 1));
    cmp_ok($cax->width, '<', 44 + 14, 'the test cell is narrower than the default margins');
    $fig->save($png);
    cmp_ok($cax->_plot_mr - $cax->_plot_ml, '>', 0, 'narrow cell: the plot rectangle has a positive width');
    my ($xa) = $cax->data_to_pixel(0, 0);
    my ($xb) = $cax->data_to_pixel(1, 0);
    cmp_ok($xb, '>', $xa, 'narrow cell: data_to_pixel runs left to right');
}

done_testing;
