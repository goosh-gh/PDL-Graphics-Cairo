use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
use PDL;
use PDL::Graphics::Cairo qw(subplots);

my ($fh, $png) = tempfile(SUFFIX => '.png', UNLINK => 1);
close $fh;

# ---- pixel helpers ----------------------------------------------------------
{
    my ($fig, $a1, $a2) = subplots(2, 1, width => 600, height => 500);
    $a1->line(pdl(0, 10), pdl(0, 5));
    $a2->line(pdl(-1, 1), pdl(-2, 2));
    $a1->xlim(0, 10); $a1->set_ylim(0, 5);
    $a2->xlim(-1, 1); $a2->set_ylim(-2, 2);
    is_deeply([ $a1->data_to_pixel(1, 1) ], [], 'data_to_pixel: empty before the axes is drawn');
    is_deeply([ $a1->axes_to_pixel(0, 0) ], [], 'axes_to_pixel: empty before the axes is drawn');

    $fig->add_connection(axA => $a1, xyA => [5, 0], axB => $a2, xyB => [0.5, 1], coordsB => 'axes');
    $fig->add_connection(axA => $a1, xyA => [2, 0], coordsA => ['data', 'axes'],
                         xyB => [0.5, 0.02], coordsB => 'figure', color => '#C62828', lw => 2, ls => 'dashed');
    is(scalar @{ $fig->{_connections} }, 2, 'add_connection: stored');
    eval { $fig->save($png) };
    ok(!$@, "save with connections ($@)");
    ok(-s $png, 'PNG written');

    my ($l, $b) = $a1->axes_to_pixel(0, 0);
    my ($r, $t) = $a1->axes_to_pixel(1, 1);
    ok($r > $l && $b > $t, 'axes_to_pixel: (0,0) bottom-left, (1,1) top-right in pixels');
    my ($x0, $y0) = $a1->data_to_pixel(0, 0);
    my ($x1, $y1) = $a1->data_to_pixel(10, 5);
    cmp_ok(abs($x0 - $l), '<', 1e-6, 'data_to_pixel: xmin at the left edge');
    cmp_ok(abs($y0 - $b), '<', 1e-6, 'data_to_pixel: ymin at the bottom edge');
    cmp_ok(abs($x1 - $r), '<', 1e-6, 'data_to_pixel: xmax at the right edge');
    cmp_ok(abs($y1 - $t), '<', 1e-6, 'data_to_pixel: ymax at the top edge');
    my ($xm) = $a1->data_to_pixel(5, 0);
    cmp_ok(abs($xm - ($l + $r) / 2), '<', 1e-6, 'data_to_pixel: linear in between');

    # end points the figure resolves for the two connections
    my @p = $fig->_connection_point($a2, [0.5, 1], 'axes');
    my ($l2, $t2) = ($a2->axes_to_pixel(0, 1));
    my ($r2)      = ($a2->axes_to_pixel(1, 1));
    cmp_ok(abs($p[0] - ($l2 + $r2) / 2), '<', 1e-6, 'connection: axes x');
    cmp_ok(abs($p[1] - $t2), '<', 1e-6, 'connection: axes y');
    my @q = $fig->_connection_point($a1, [2, 0], ['data', 'axes']);
    cmp_ok(abs($q[0] - ($a1->data_to_pixel(2, 0))[0]), '<', 1e-6, 'connection: mixed coords, x in data');
    cmp_ok(abs($q[1] - $b), '<', 1e-6, 'connection: mixed coords, y in axes fraction');
    my @f = $fig->_connection_point(undef, [0.5, 0.02], 'figure');
    is_deeply(\@f, [300, 490], 'connection: figure fraction, y from the bottom');

    # The dashed red line (#C62828) runs from the upper axes to the bottom of the
    # figure; nothing else in the figure is red. Read the PNG back with Cairo
    # itself (ARGB32: bytes B,G,R,A per pixel), independent of any PNG reader.
    {
        require Cairo;
        my $surf = Cairo::ImageSurface->create_from_png($png);
        my ($w, $h, $stride) = ($surf->get_width, $surf->get_height, $surf->get_stride);
        my $data = $surf->get_data;
        my ($red, $below) = (0, 0);
        my (undef, $bot2) = $a2->axes_to_pixel(0, 0);          # bottom edge of the lower axes
        for my $y (0 .. $h - 1) {
            my $row = substr($data, $y * $stride, 4 * $w);
            my @px  = unpack('C*', $row);
            for (my $k = 0; $k < @px; $k += 4) {
                next unless $px[$k + 2] > 150 && $px[$k + 1] < 90 && $px[$k] < 90;
                $red++;
                $below++ if $y > $bot2 + 2;
            }
        }
        cmp_ok($red, '>', 20, "connection: line pixels present in the image ($red red pixels)");
        cmp_ok($below, '>', 0, 'connection: drawn outside the plot rectangles too (unclipped)');
    }
    $fig->clf;
    is(scalar @{ $fig->{_connections} }, 0, 'clf removes connections');
}

# ---- argument checks ---------------------------------------------------------
{
    my ($fig, $ax) = subplots(1, 1, width => 300, height => 200);
    eval { $fig->add_connection(axA => $ax, xyA => [0, 0], xyB => [1, 1]) };
    like($@, qr/axB required/, 'add_connection: axes needed for data coords');
    eval { $fig->add_connection(axA => $ax, xyA => [0, 0], axB => $ax, xyB => [1, 1], coordsB => 'polar') };
    like($@, qr/coordsB must be/, 'add_connection: unknown coords refused');
    eval { $fig->add_connection(axA => $ax, xyA => [0], axB => $ax, xyB => [1, 1]) };
    like($@, qr/xyA/, 'add_connection: xy must have two values');
}

# ---- add_text ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1, 1, width => 300, height => 200);
    $ax->line(pdl(0, 1), pdl(0, 1));
    is($fig->add_text(text => 'N = 5', ax => $ax, xy => [1, 1], coords => 'axes',
                      ha => 'right', va => 'bottom', offset => [0, -3]), $fig, 'add_text returns the figure');
    $fig->add_text(text => 'note', xy => [0.5, 0.5], coords => 'figure', ha => 'center', va => 'middle',
                   fontsize => 8, color => '#C62828', weight => 'bold');
    is(scalar @{ $fig->{_fig_texts} }, 2, 'add_text: stored');
    eval { $fig->save($png) };
    ok(!$@, "save with figure texts ($@)");
    eval { $fig->add_text(ax => $ax, xy => [0, 0]) };
    like($@, qr/text required/, 'add_text: text required');
    eval { $fig->add_text(text => 'x', xy => [0, 0]) };
    like($@, qr/ax required/, 'add_text: axes needed for data coords');
    eval { $fig->add_text(text => 'x', ax => $ax, xy => [0, 0], coords => 'polar') };
    like($@, qr/coords must be/, 'add_text: unknown coords refused');
    $fig->clf;
    is(scalar @{ $fig->{_fig_texts} }, 0, 'clf removes figure texts');
}

# ---- clip_pad_top ------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1, 1, width => 300, height => 200);
    is($ax->clip_pad_top, 15, 'clip_pad_top: default 15');
    is($ax->clip_pad_top(0), $ax, 'clip_pad_top: setter returns the axes');
    is($ax->clip_pad_top, 0, 'clip_pad_top: 0 kept');
    $ax->line(pdl(0, 1), pdl(0, 10)); $ax->set_ylim(0, 5);
    eval { $fig->save($png) };
    ok(!$@, "save with clip_pad_top(0) ($@)");
}

done_testing;
