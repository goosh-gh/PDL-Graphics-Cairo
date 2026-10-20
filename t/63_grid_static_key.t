use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::Driver::GS;

# ==================================================================
# show_grid_scrub(static_key => ...): the main window keeps the panels that do
# not change (all but the _scrub_skip ones) as a background image, and each
# frame paints the background, the latency lines and the _scrub_skip panels.
# Checked without a giza-server, through _paint_main / _compose_main and the
# old path (_window_png), comparing the pixels before PNG encoding:
#   - the frames are the same except where a latency line meets the top and
#     bottom frame lines (the old path draws the frame over the line)
#   - the background is drawn again only when the key or the size changes
#   - clicks are read with the drawn layout (image_frac_to_data)
#   - negative control: a key that does not follow the data leaves the old
#     waveforms in the frame
# ==================================================================

my ($W, $H) = (600, 450);
my $t = sequence(501) - 100;
my $amp = 5;                                  # changed below for the negative control

my $grid_render = sub {
    my ($state, $w, $h) = @_;
    my $fig = figure(width => $w, height => $h);
    my $gs = $fig->add_gridspec(3, 3, left => 0.03, right => 0.97, top => 0.94, bottom => 0.06,
                                wspace => 0.15, hspace => 0.2, cell_margins => 0);
    my @cells = grep { !($_->[0] == 0 && $_->[1] == 1) } map { my $r = $_; map { [$r, $_] } 0 .. 2 } 0 .. 2;
    for my $k (0 .. $#cells) {
        my $ax = $fig->add_subplot($gs->at(@{ $cells[$k] }));
        $ax->line($t, $amp * sin(($t + 30 * $k) / 25), color => '#1565C0', lw => 0.9);
        $ax->axhline(0, color => '#999999', lw => 0.5);
        $ax->xlim(-100, 400);
        $ax->set_ylim(-6, 6);
        $ax->invert_yaxis;
        $ax->text(-90, -5, "ch$k", ha => 'left', va => 'top', fontsize => 10);
    }
    my $lat = $state->{_scrub_lat} // 0;
    my $m = $fig->add_subplot($gs->at(0, 1));
    $m->{_scrub_skip} = 1;
    $m->imshow(sin(sequence(30, 30) / 20 + $lat / 40));
    $m->text(15, 28, sprintf('%.0f ms', $lat), ha => 'center', fontsize => 9);
    # a figure text tied to the map panel (drawn by the figure after the panels)
    $fig->add_text(text => sprintf('lat %.0f', $lat), ax => $m, xy => [0.5, 0], coords => 'axes',
                   ha => 'center', va => 'top', offset => [0, 2], fontsize => 9);
    # and one in figure coordinates (part of the background)
    $fig->add_text(text => 'static note', xy => [0.02, 0.02], coords => 'figure', fontsize => 8);
    $fig->label_only($fig->axes_list->[6]);
    $fig->suptitle('grid', fontsize => 10);
    return $fig;
};

my $gs = PDL::Graphics::Cairo::Driver::GS->new(width => $W, height => $H, start => 'connect');

# capture the pixels instead of encoding a PNG; count the background renders
my ($pixels, $bg_renders) = (undef, 0);
no warnings 'redefine';
local *PDL::Graphics::Cairo::Driver::Cairo::png_bytes = sub { $pixels = $_[0]{surface}->get_data; 'png' };
my $orig_render_to = \&PDL::Graphics::Cairo::Figure::_render_to;
local *PDL::Graphics::Cairo::Figure::_render_to = sub {
    my ($fig, $d, %o) = @_;
    $bg_renders++ if $o{skip};
    $orig_render_to->(@_);
};
use warnings 'redefine';

my $vline = { color => [0.78, 0.16, 0.16], lw => 1.2 };
my %key = (k => 'grid');
my $wm_old = { state => {}, grid_render => $grid_render, vline => $vline };
my $wm_new = { state => {}, grid_render => $grid_render, vline => $vline,
               static_key => sub { $key{k} } };
my ($win_old, $win_new) = ({ w => $W, h => $H }, { w => $W, h => $H });

sub frame {
    my ($wm, $win, $lat, $new) = @_;
    $wm->{state}{_scrub_lat} = $lat;
    my $fig = $gs->_paint_main($wm, $win);
    $win->{last_fig} = $fig;
    $new ? $gs->_compose_main($wm, $win, $fig) : $gs->_window_png($fig);
    my $p = zeroes(byte, 4, $W, $H);
    ${ $p->get_dataref } = $pixels;
    $p->upd_data;
    return ($p, $fig);
}

sub differ {                                  # (number of differing pixels, of them by more than 40)
    my ($a1, $b1) = @_;
    my $d = ($a1->long - $b1->long)->abs->maximum;    # per pixel, over B, G, R, A
    return (($d > 0)->sum->sclr, ($d > 40)->sum->sclr);
}

my $npanels = 8;
for my $lat (50, 175.5, 333) {
    my ($p_old) = frame($wm_old, $win_old, $lat, 0);
    my ($p_new) = frame($wm_new, $win_new, $lat, 1);
    my ($n, $big) = differ($p_old, $p_new);
    cmp_ok($n, '<=', 8 * $npanels, "latency $lat: at most a few pixels per panel differ ($n)");
    cmp_ok($big, '<=', 2 * $npanels, "latency $lat: clear differences only where the line meets the frame ($big)");
}
is($bg_renders, 1, 'background drawn once for three latencies');

# clicks: the panels of the last frame were not drawn, but read the drawn layout
{
    my ($p_old, $fig_old) = frame($wm_old, $win_old, 210, 0);
    my ($p_new, $fig_new) = frame($wm_new, $win_new, 210, 1);
    my ($ok, $tried) = (1, 0);
    for my $i (0 .. $npanels - 1) {
        # a point inside the panel's plot rectangle of the full frame
        my $ao = $fig_old->axes_list->[$i];
        my $fx = (0.3 * $ao->_plot_ml + 0.7 * $ao->_plot_mr) / $W;
        my $fy = (0.6 * $ao->_plot_mt + 0.4 * $ao->_plot_mb) / $H;
        my @a = $ao->image_frac_to_data($fx, $fy);
        my @b = $fig_new->axes_list->[$i]->image_frac_to_data($fx, $fy);
        next unless defined $a[0];
        $tried++;
        $ok = 0 unless defined $b[0] && abs($a[0] - $b[0]) < 1e-9 && abs($a[1] - $b[1]) < 1e-9;
    }
    ok($tried > 0 && $ok, "image_frac_to_data on the composed frame matches the full frame ($tried panels)");
}

# the background is drawn again when the key or the size changes
{
    my $before = $bg_renders;
    $key{k} = 'other';
    frame($wm_new, $win_new, 100, 1);
    is($bg_renders, $before + 1, 'new key: background drawn again');
    frame($wm_new, $win_new, 120, 1);
    is($bg_renders, $before + 1, 'same key: background kept');
}

# negative control: the data change but the key does not -> old waveforms remain
{
    $amp = 2;
    my ($p_old) = frame($wm_old, $win_old, 150, 0);
    my ($p_new) = frame($wm_new, $win_new, 150, 1);
    my (undef, $big) = differ($p_old, $p_new);
    cmp_ok($big, '>', 100, 'negative control: a key that does not follow the data shows the old background');
    $key{k} = 'amp2';
    ($p_new) = frame($wm_new, $win_new, 150, 1);
    (undef, $big) = differ($p_old, $p_new);
    cmp_ok($big, '<=', 2 * $npanels, 'key following the data: the frame matches again');
}

done_testing;
