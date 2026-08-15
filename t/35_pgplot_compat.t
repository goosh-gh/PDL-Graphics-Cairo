use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo::PGPLOT;
use Cairo;

# ==================================================================
# Mechanical checks for the PGPLOT-compatibility "gaps" filled in P:G:C17.
#
#   #105 cpghist / pghist             -- implemented but had no test coverage
#   #108 cpgaxis / cpgtick            -- newly implemented (general axis/tick)
#   #110 CI0/CI1 background convention -- verified on real pixels, not just logic
#   #111 cpggray with FG<BG           -- swapping the FG/BG value order inverts
#                                       the grayscale (inverse video)
#
# As in t/31, pixel checks are done by reading the rendered PNG back into a
# BGRA byte PDL via Cairo (no external dependency such as Pillow).
#
# NOTE: the background convention is driven by the PGPLOT_BACKGROUND
# environment variable. Tests that reason about "ink on a white page" pin
# PGPLOT_BACKGROUND=white locally so they are independent of the caller's
# shell environment (a long-time PGPLOT user may well have it set to black,
# which is the authentic PGPLOT default).
# ==================================================================

# Read a PNG into a [4,W,H] BGRA byte pdl (same pattern as t/31).
sub load_png_pixels {
    my ($path) = @_;
    my $surface = Cairo::ImageSurface->create_from_png($path);
    $surface->flush;
    my $w      = $surface->get_width;
    my $h      = $surface->get_height;
    my $stride = $surface->get_stride;
    my $raw    = $surface->get_data;

    my $padded = PDL->zeroes(PDL::byte, $stride, $h);
    ${ $padded->get_dataref } = $raw;
    $padded->upd_data;
    my $cropped = $padded->slice("0:" . ($w*4-1) . ",:");   # [W*4, H]
    my $pdl     = $cropped->reshape(4, $w, $h);              # [4,W,H] BGRA
    return ($pdl, $w, $h);
}

# Number of "ink" pixels (i.e. non-white drawing) on a white page.
sub ink_count {
    my ($pdl) = @_;
    my $blue = $pdl->slice("2,:,:")->sever->flat;
    return (($blue < 200)->sum);
}

# Min/max device row (y) that contains any ink.
sub ink_y_span {
    my ($pdl, $w, $h) = @_;
    my $blue = $pdl->slice("2,:,:")->sever->reshape($w, $h);   # [W,H]
    my $ink  = ($blue < 200);
    my ($y0, $y1) = (-1, -1);
    for my $iy (0 .. $h-1) {
        if ($ink->slice(":,$iy")->sum > 0) {
            $y0 = $iy if $y0 < 0;
            $y1 = $iy;
        }
    }
    return ($y0, $y1);
}

# Most frequent grey value in the image, ignoring the white page (>=250).
# For a uniform-value image this picks up the fill colour of the image.
sub modal_gray {
    my ($pdl) = @_;
    my $blue = $pdl->slice("2,:,:")->sever->flat;
    my $sub  = $blue->where($blue < 250);
    return -1 unless $sub->nelem;
    my %cnt;
    $cnt{$_}++ for $sub->list;
    my ($m) = sort { $cnt{$b} <=> $cnt{$a} } keys %cnt;
    return $m;
}

# ------------------------------------------------------------------
# #105  cpghist / pghist
# ------------------------------------------------------------------
{
    ok defined &cpghist, 'cpghist is defined/exported';
    ok defined &pghist,  'pghist alias is defined/exported';

    # Pin a white background so "ink" means bars drawn on a white page,
    # regardless of the caller's PGPLOT_BACKGROUND setting.
    local $ENV{PGPLOT_BACKGROUND} = 'white';

    # 10 counts each of 0..9 -> a flat histogram (deterministic data).
    my $data = sequence(100) % 10;

    my $f = "/tmp/test_pghist_$$.png";
    my $ret = cpgbeg(0, "$f/PNG", 1, 1);
    is $ret, 1, 'cpgbeg for hist';
    cpgenv(0, 10, 0, 20, 0, 0);
    cpgsci(1);
    eval { cpghist(100, $data, 0, 10, 10, 0) };
    is $@, '', 'cpghist no error';
    cpgend();

    ok -f $f, 'cpghist PNG created';
    my ($px) = load_png_pixels($f);
    cmp_ok ink_count($px), '>', 200, 'cpghist actually drew histogram bars';
    unlink $f;
}

# ------------------------------------------------------------------
# #108  cpgaxis / cpgtick
# ------------------------------------------------------------------
{
    ok defined &cpgaxis, 'cpgaxis is defined/exported';
    ok defined &cpgtick, 'cpgtick is defined/exported';
    ok defined &pgaxis,  'pgaxis alias is defined/exported';
    ok defined &pgtick,  'pgtick alias is defined/exported';

    # ink_count / ink_y_span assume drawing on a white page, so pin the
    # background to white and do not depend on the caller's PGPLOT_BACKGROUND.
    local $ENV{PGPLOT_BACKGROUND} = 'white';

    # --- cpgaxis draws an axis line + ticks + numeric labels ---
    # With 'N' (labels) there is clearly more ink than without 'N'.
    my $draw = sub {
        my ($opt) = @_;
        my $f = "/tmp/test_pgaxis_${opt}_$$.png";
        cpgbeg(0, "$f/PNG", 1, 1);
        cpgenv(0, 10, 0, 10, 0, -2);     # axis=-2: no box, draw only our axis
        cpgsci(1);
        cpgaxis($opt, 1,3, 9,3, 0,100, 20, 2, 0.6, 0.0, 0.5, 1.0, 0);
        cpgend();
        my ($px) = load_png_pixels($f);
        my $ink  = ink_count($px);
        unlink $f;
        return $ink;
    };
    my $ink_with_labels = $draw->('N');
    my $ink_no_labels   = $draw->('');
    cmp_ok $ink_no_labels,   '>', 50,
        'cpgaxis without N draws axis line + tick marks';
    cmp_ok $ink_with_labels, '>', $ink_no_labels,
        'cpgaxis with N adds numeric-label ink beyond bare ticks';

    # --- cpgtick left/right convention (perpendicular in device space) ---
    # For a left-to-right horizontal axis: right = below, left = above.
    my $tick_span = sub {
        my ($tikl, $tikr) = @_;
        my $f = "/tmp/test_pgtick_$$.png";
        cpgbeg(0, "$f/PNG", 1, 1);
        cpgenv(0, 10, 0, 10, 0, -2);
        cpgsci(1);
        cpgtick(1,5, 9,5, 0.5, $tikl, $tikr, 0, 0, "");
        cpgend();
        my ($px, $w, $h) = load_png_pixels($f);
        my @s = ink_y_span($px, $w, $h);
        unlink $f;
        return @s;
    };
    my ($sy0, $sy1) = $tick_span->(1.5, 1.5);       # symmetric -> centre = axis row
    my $axis_row = ($sy0 + $sy1) / 2;
    my ($ry0, $ry1) = $tick_span->(0.0, 2.0);       # right only
    my ($ly0, $ly1) = $tick_span->(2.0, 0.0);       # left only

    cmp_ok $ry1, '>', $axis_row,
        'cpgtick right tick extends below axis (device y increases)';
    cmp_ok $ly0, '<', $axis_row,
        'cpgtick left tick extends above axis (device y decreases)';
    cmp_ok $ry0, '>=', $axis_row - 3,
        'cpgtick right tick starts at the axis (not crossing to the left side)';
    cmp_ok $ly1, '<=', $axis_row + 3,
        'cpgtick left tick starts at the axis (not crossing to the right side)';
}

# ------------------------------------------------------------------
# #110  CI0/CI1 background convention -- verified on real pixels
#   default (white bg): page is white, CI1 (foreground = black) ink is black.
#   PGPLOT_BACKGROUND=black: page is black, CI1 (foreground = white) ink is white.
# ------------------------------------------------------------------
sub render_ci1_line {
    my ($f) = @_;
    cpgbeg(0, "$f/PNG", 1, 1);
    cpgenv(0, 10, 0, 10, 0, 0);
    cpgsci(1);                       # CI1 = foreground colour (opposite of bg)
    cpgline(2, [0, 10], [0, 10]);
    cpgend();
}

{
    # --- white background (explicit) ---
    # The default is white, but a user who exports PGPLOT_BACKGROUND=black
    # would otherwise get a black default here, so pin white for this test.
    local $ENV{PGPLOT_BACKGROUND} = 'white';
    my $f = "/tmp/test_pgwhitebg_$$.png";
    render_ci1_line($f);
    my ($px, $w, $h) = load_png_pixels($f);
    my $b = $px->slice("2,:,:")->sever->flat;
    my $g = $px->slice("1,:,:")->sever->flat;
    my $r = $px->slice("0,:,:")->sever->flat;
    my $n = $b->nelem;
    my $white = (($b>215)&($g>215)&($r>215))->sum;
    my $black = (($b<40) &($g<40) &($r<40))->sum;
    cmp_ok $white, '>', 0.5 * $n, 'white-bg: page is predominantly white';
    cmp_ok $black, '>', 0,        'white-bg: CI1 draws black foreground ink';
    unlink $f;
}

{
    # --- black background (PGPLOT_BACKGROUND=black) ---
    local $ENV{PGPLOT_BACKGROUND} = 'black';
    my $f = "/tmp/test_pgblackbg_$$.png";
    render_ci1_line($f);
    my ($px, $w, $h) = load_png_pixels($f);
    my $b = $px->slice("2,:,:")->sever->flat;
    my $g = $px->slice("1,:,:")->sever->flat;
    my $r = $px->slice("0,:,:")->sever->flat;
    my $n = $b->nelem;
    my $black = (($b<40) &($g<40) &($r<40))->sum;
    my $white = (($b>215)&($g>215)&($r>215))->sum;
    cmp_ok $black, '>', 0.5 * $n, 'black-bg: page is predominantly black';
    cmp_ok $white, '>', 0,        'black-bg: CI1 draws white foreground ink';
    unlink $f;
}

# ------------------------------------------------------------------
# #111  cpggray with FG<BG (inverse video)
#   cpggray(A, IDIM,JDIM, I1,I2,J1,J2, FG, BG, TR):
#     value FG -> foreground colour (light), value BG -> background colour (dark).
#   FG>BG is normal; FG<BG gives inverse video.
# ------------------------------------------------------------------
{
    # Pin white: modal_gray excludes the white page (>=250) to read the image
    # fill colour, so a black page would otherwise pollute the measurement.
    local $ENV{PGPLOT_BACKGROUND} = 'white';

    my $ni = 4;
    my $nj = 4;
    my $val = 0.75;                       # uniform-value image
    my $img = zeroes($ni, $nj) + $val;
    my @tr  = (0, 1, 0, 0, 0, 1);         # unused by impl (imshow handles mapping)

    my $render = sub {
        my ($fg, $bg) = @_;
        my $f = "/tmp/test_pggray_$$.png";
        cpgbeg(0, "$f/PNG", 1, 1);
        cpgenv(0, $ni, 0, $nj, 0, 0);
        cpggray($img, $ni, $nj, 1, $ni, 1, $nj, $fg, $bg, \@tr);
        cpgend();
        my ($px) = load_png_pixels($f);
        my $mg = modal_gray($px);
        unlink $f;
        return $mg;
    };

    # normal: FG=1(light) > BG=0(dark) -> value 0.75 is light (>128)
    my $normal = $render->(1, 0);
    # inverse: FG=0 < BG=1 -> the same value 0.75 becomes dark (<128)
    my $invert = $render->(0, 1);

    cmp_ok $normal, '>', 128,
        'cpggray FG>BG: high value maps toward foreground (light)';
    cmp_ok $invert, '<', 128,
        'cpggray FG<BG: same value maps toward background (dark) -- inverse video';
    cmp_ok $normal, '>', $invert + 40,
        'cpggray: swapping FG/BG order actually inverts the grayscale';
}

done_testing;
