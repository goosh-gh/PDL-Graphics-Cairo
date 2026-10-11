use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::Driver::GS;

# show_grid_scrub: latency selection in the main window (main_scrub) and panels
# excluded with _scrub_skip. Drives the driver's event dispatch and paint
# methods directly against real Figure/Axes; no giza-server is contacted.

my ($W, $H) = (900, 700);
my $t = sequence(101) * 8 - 200;                 # -200 .. 600 ms
use constant { CURSOR => 0x18, PICK => 0x19 };

# 2x3 grid; panel 5 stands for a panel that is not a time axis
my $grid_render = sub {
    my ($state, $w, $h) = @_;
    my $fig = figure(width => $w, height => $h);
    my @rows = $fig->subplots(2, 3);
    my $k = 0;
    for my $r (0, 1) { for my $c (0 .. 2) {
        my $ax = $rows[$r][$c];
        $ax->line($t, 10 * sin($t / (20 + 5 * $k)));
        $ax->xlim(-200, 600);
        $ax->{_scrub_skip} = 1 if $k == 5;
        $k++;
    } }
    $fig->tight_layout;
    return $fig;
};

my $drv = PDL::Graphics::Cairo::Driver::GS->new(width => $W, height => $H);
sub wm_for {
    my ($main_scrub) = @_;
    return {
        state => {}, grid_render => $grid_render, cell_render => sub { die 'unused' },
        zoom_w => $W, zoom_h => $H, vline => { color => [1, 0, 0], lw => 1.2 },
        marker => {}, readout => sub { '' }, cell_title => sub { '' },
        main_scrub => $main_scrub, wins => [], cells => {},
    };
}
sub main_win {
    my ($wm) = @_;
    my $win = { kind => 'main', w => $W, h => $H, dirty => 0, alive => 1 };
    my $fig = $drv->_paint_main($wm, $win);
    $drv->_figure_to_png($fig);                   # fixes the plot rectangles
    $win->{last_fig} = $fig;
    $wm->{main} = $win;
    return $win;
}
sub frac_at {                                        # image fraction of (xf, 0.5) in panel $i
    my ($win, $i, $xf) = @_;
    my $ax = $win->{last_fig}->axes_list->[$i];
    return (($ax->_plot_ml + $xf * ($ax->_plot_mr - $ax->_plot_ml)) / $W,
            ($ax->_plot_mt + 0.5 * ($ax->_plot_mb - $ax->_plot_mt)) / $H);
}
sub event { my ($wm, $win, $type, $fx, $fy, $btn) = @_;
            $drv->_dispatch($wm, $win, $type, pack('f< f< C', $fx, $fy, $btn)) }

# ---- main_scrub off (default): the main window ignores drags and clicks -------
{
    my $wm = wm_for(0); my $win = main_win($wm);
    event($wm, $win, CURSOR, frac_at($win, 1, 0.5), 1);
    event($wm, $win, PICK,   frac_at($win, 1, 0.5), 1);
    ok(!defined $wm->{state}{_scrub_lat}, 'main_scrub off: drag and click in the main window select nothing');
    ok(!$win->{dirty}, 'main_scrub off: main window not repainted');
}

# ---- main_scrub on ------------------------------------------------------------
{
    my $wm = wm_for(1); my $win = main_win($wm);

    event($wm, $win, CURSOR, frac_at($win, 2, 0.25), 0);
    ok(!defined $wm->{state}{_scrub_lat}, 'hover (no button) selects nothing');

    event($wm, $win, CURSOR, frac_at($win, 2, 0.25), 1);                 # -200 + 0.25*800 = 0
    cmp_ok(abs($wm->{state}{_scrub_lat} - 0), '<', 1.5, 'drag in panel 2 at 25% selects 0 ms');
    ok($win->{dirty}, 'drag: main window marked for repaint');
    ok($wm->{_scrub_stale}, 'drag: open cell windows marked to catch up');

    event($wm, $win, CURSOR, frac_at($win, 4, 0.75), 1);                 # 400 ms
    cmp_ok(abs($wm->{state}{_scrub_lat} - 400), '<', 1.5, 'drag continues in another panel: 400 ms');

    event($wm, $win, PICK, frac_at($win, 0, 0.5), 1);                    # 200 ms
    cmp_ok(abs($wm->{state}{_scrub_lat} - 200), '<', 1.5, 'single click in panel 0 at 50% selects 200 ms');

    my $before = $wm->{state}{_scrub_lat};
    event($wm, $win, CURSOR, frac_at($win, 5, 0.1), 1);
    is($wm->{state}{_scrub_lat}, $before, 'drag in a _scrub_skip panel selects nothing');
    event($wm, $win, CURSOR, 0.001, 0.001, 1);
    is($wm->{state}{_scrub_lat}, $before, 'drag outside every panel selects nothing');

    # repaint: a line at the selected latency in every panel but the skipped one
    my $fig = $drv->_paint_main($wm, $win);
    my @nv = map { my $ax = $_; scalar grep { ($_->{type} // '') eq 'vline' } @{ $ax->_queue } } @{ $fig->axes_list };
    is_deeply(\@nv, [1, 1, 1, 1, 1, 0], 'repaint: one latency line per panel, none in the _scrub_skip panel');
    ok(length($drv->_figure_to_png($fig)) > 0, 'repaint renders');
}

# ---- window size: the image has the size of the window, not of the driver ------
{
    use constant RESIZE => 0x16;
    sub png_size { unpack 'N N', substr($_[0], 16, 8) }           # IHDR width, height
    my $wm = wm_for(1); my $win = main_win($wm);
    is_deeply([ png_size($drv->_window_png($win->{last_fig})) ], [$W, $H], 'first frame: image of the window size');

    for my $size ([640, 480], [1300, 900]) {
        $drv->_dispatch($wm, $win, RESIZE, pack('L L', @$size));
        ok($win->{dirty}, "RESIZE to @$size: window marked for repaint");
        my $fig = $drv->_paint_main($wm, $win);
        is_deeply([ $fig->width, $fig->height ], $size, "RESIZE to @$size: figure laid out at the new size");
        my $png = $drv->_window_png($fig);
        is_deeply([ png_size($png) ], $size, "RESIZE to @$size: image of the new size");
        $win->{last_fig} = $fig; $win->{dirty} = 0;
        # a click at 50% of panel 0 in the resized window still selects 200 ms
        my $ax = $fig->axes_list->[0];
        event($wm, $win, PICK, ($ax->_plot_ml + $ax->_plot_mr) / 2 / $size->[0],
                               ($ax->_plot_mt + $ax->_plot_mb) / 2 / $size->[1], 1);
        cmp_ok(abs($wm->{state}{_scrub_lat} - 200), '<', 1.5, "RESIZE to @$size: click in panel 0 at 50% selects 200 ms");
        $wm->{state}{_scrub_lat} = undef;
    }
    is_deeply([ png_size($drv->_figure_to_png($win->{last_fig})) ], [$W, $H],
              '_figure_to_png without a size keeps the driver size (other display paths)');
}

done_testing;
