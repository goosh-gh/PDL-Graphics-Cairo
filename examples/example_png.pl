#!/usr/bin/env perl
# =============================================================
# example_png.pl  --  PDL::Graphics::Cairo PNG output demo
#
# Run from PDL-Graphics-Cairo/ root:
#   perl -I./lib examples/example_png.pl
#   perl -I./lib examples/example_png.pl ~/Desktop/plots   # custom output dir
#
# Output files:
#   ex01_line.png       Line styles, legend, grid
#   ex02_scatter.png    Scatter plot (colormap, markers)
#   ex03_bar_hist.png   Bar charts + histogram overlay
#   ex04_errorbar.png   Error bars + fill_between confidence band
#   ex05_step_stem.png  Step / stem plots
#   ex06_pie.png        Pie chart
#   ex07_imshow.png     imshow colormap gallery
#   ex08_contourf.png   Filled contour
#   ex09_annotate.png   annotate / axvspan / axhspan
#   ex10_logscale.png   Log scale (semilog-y / log-log)
#   ex11_twinx.png      Dual Y axis (twinx)
#   ex12_dashboard.png  Statistical dashboard (2x2 subplot)
# =============================================================

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

my $PI = 3.14159265358979;

my $OUT = $ARGV[0] // '.';
die "Output directory not found: $OUT\n" unless -d $OUT;

# =============================================================
# ex01: Line styles, legend, grid
# =============================================================
{
    my $x = sequence(200) / 10;

    my $fig = figure(width => 800, height => 500);
    my $ax  = $fig->axes();

    $ax->title("Line styles, legend & grid");
    $ax->xlabel("x");
    $ax->ylabel("y");
    $ax->set_grid(1);

    $ax->line($x, sin($x),         color=>'blue',   lw=>2, ls=>'solid',   label=>'sin(x)');
    $ax->line($x, cos($x),         color=>'orange', lw=>2, ls=>'dashed',  label=>'cos(x)');
    $ax->line($x, sin($x)*0.5 + 2, color=>'green',  lw=>2, ls=>'dotted',  label=>'0.5 sin+2');
    $ax->line($x, cos($x)*0.5 + 2, color=>'red',    lw=>2, ls=>'dashdot', label=>'0.5 cos+2');
    $ax->axhline(0, color=>'gray', lw=>0.8, ls=>'dashed');
    $ax->legend(loc=>'upper right');

    $fig->save("$OUT/ex01_line.png");
    print "ex01_line.png\n";
}

# =============================================================
# ex02: Scatter plot (colormap, marker styles)
# =============================================================
{
    my ($fig, $ax1, $ax2) = subplots(1, 2, width=>1100, height=>500);
    $fig->set_suptitle("Scatter plots");

    # Left: color-mapped scatter
    my $n  = 300;
    my $sx = grandom($n);
    my $sy = grandom($n);
    my $sc = sqrt($sx*$sx + $sy*$sy);
    $ax1->title("Color-mapped scatter");
    $ax1->scatter($sx, $sy, c=>$sc, cmap=>'plasma', s=>5, alpha=>0.8);
    $ax1->axhline(0, color=>'gray', lw=>0.5, ls=>'dotted');
    $ax1->axvline(0, color=>'gray', lw=>0.5, ls=>'dotted');
    $ax1->set_grid(1);
    $ax1->xlabel("x"); $ax1->ylabel("y");
    $ax1->margin_right(70);

    # Right: marker styles
    my @markers = ('o', 's', '^', 'd', '+', 'x');
    my @mlabels = ('circle', 'square', 'triangle', 'diamond', 'plus', 'cross');
    my @mcolors = ('blue', 'orange', 'green', 'red', 'purple', 'brown');
    my $mx = sequence(6) + 1;
    my $my = sin($mx);
    $ax2->title("Marker styles");
    for my $i (0..$#markers) {
        $ax2->scatter(pdl($mx->at($i)), pdl($my->at($i)),
            marker => $markers[$i],
            color  => $mcolors[$i],
            s      => 8,
            label  => $mlabels[$i],
        );
    }
    $ax2->legend(loc=>'upper right');
    $ax2->set_grid(1);
    $ax2->xlabel("x"); $ax2->ylabel("y");

    $fig->save("$OUT/ex02_scatter.png");
    print "ex02_scatter.png\n";
}

# =============================================================
# ex03: Bar charts + histogram overlay
# =============================================================
{
    my ($fig, $ax1, $ax2, $ax3) = subplots(1, 3, width=>1400, height=>480);
    $fig->set_suptitle("Bar & Histogram");

    # Vertical bar
    my @cats = (1..6);
    my @vals = (3.2, 4.8, 2.1, 5.5, 3.9, 4.4);
    $ax1->title("Vertical bar");
    $ax1->bar(pdl(@cats), pdl(@vals), width=>0.6, color=>'steelblue', alpha=>0.85);
    $ax1->xticks(\@cats, [qw(Jan Feb Mar Apr May Jun)]);
    $ax1->xlabel("Month"); $ax1->ylabel("Value");
    $ax1->ylim(0, 7); $ax1->set_grid(1);

    # Horizontal bar
    my $ys = pdl(0,1,2,3,4);
    my $ws = pdl(3.1, 4.8, 2.4, 5.2, 3.7);
    $ax2->title("Horizontal bar");
    $ax2->barh($ys, $ws, color=>'coral', alpha=>0.85);
    $ax2->yticks([0,1,2,3,4], [qw(Alpha Beta Gamma Delta Epsilon)]);
    $ax2->xlabel("Score");
    $ax2->xlim(0, 7); $ax2->set_grid(1);

    # Overlapping histograms
    my $d1 = grandom(500);
    my $d2 = grandom(500) * 0.7 + 1.5;
    $ax3->title("Overlapping histograms");
    $ax3->hist($d1, bins=>25, color=>'steelblue', alpha=>0.6, label=>'N(0,1)');
    $ax3->hist($d2, bins=>25, color=>'coral',     alpha=>0.6, label=>'N(1.5,0.7)');
    $ax3->axvline(0,   color=>'steelblue', lw=>1.2, ls=>'dashed');
    $ax3->axvline(1.5, color=>'coral',     lw=>1.2, ls=>'dashed');
    $ax3->legend(loc=>'upper right');
    $ax3->xlabel("Value"); $ax3->ylabel("Count");
    $ax3->set_grid(1);

    $fig->save("$OUT/ex03_bar_hist.png");
    print "ex03_bar_hist.png\n";
}

# =============================================================
# ex04: Error bars + fill_between confidence band
# =============================================================
{
    my ($fig, $ax1, $ax2) = subplots(1, 2, width=>1100, height=>480);
    $fig->set_suptitle("Errorbar & Fill-between");

    # Error bars
    my $xe   = sequence(10);
    my $ye   = sin($xe * 0.7);
    my $yerr = 0.1 + random(10) * 0.25;
    $ax1->title("Error bars");
    $ax1->set_grid(1);
    $ax1->errorbar($xe, $ye, yerr=>$yerr,
        color=>'navy', capsize=>6, marker=>'o', markersize=>5,
        label=>"mean\x{00B1}std");
    $ax1->fill_between($xe, $ye - $yerr*2, $ye + $yerr*2,
        color=>'navy', alpha=>0.12, label=>'95% CI');
    $ax1->axhline(0, color=>'gray', lw=>0.8, ls=>'dashed');
    $ax1->legend(loc=>'upper right');
    $ax1->xlabel("x"); $ax1->ylabel("y");

    # Confidence bands
    my $xf = sequence(150) / 15;
    my $yf = cos($xf) * exp(-$xf / 5);
    $ax2->title("Confidence bands");
    $ax2->set_grid(1);
    $ax2->fill_between($xf, $yf-0.30, $yf+0.30, color=>'royalblue', alpha=>0.12, label=>'90%');
    $ax2->fill_between($xf, $yf-0.15, $yf+0.15, color=>'royalblue', alpha=>0.22, label=>'50%');
    $ax2->line($xf, $yf, color=>'royalblue', lw=>2.0, label=>'mean');
    $ax2->axhline(0, color=>'gray', lw=>0.8, ls=>'dotted');
    $ax2->legend(loc=>'upper right');
    $ax2->xlabel("x"); $ax2->ylabel("y");

    $fig->save("$OUT/ex04_errorbar.png");
    print "ex04_errorbar.png\n";
}

# =============================================================
# ex05: Step / stem plots
# =============================================================
{
    my ($fig, $ax1, $ax2) = subplots(1, 2, width=>1100, height=>460);
    $fig->set_suptitle("Step & Stem");

    my $xs = sequence(12);
    my $ys = pdl(2, 3, 1, 4, 2, 5, 3, 4, 2, 3, 1, 2);
    $ax1->title("Step plot (post)");
    $ax1->set_grid(1);
    $ax1->step($xs, $ys, color=>'steelblue', lw=>2.0, where=>'post', label=>'step');
    $ax1->axhline(0, color=>'gray', lw=>0.5, ls=>'dotted');
    $ax1->legend(loc=>'upper right');
    $ax1->xlabel("x"); $ax1->ylabel("y");

    my $xt = sequence(20) * $PI / 5;
    my $yt = sin($xt) * exp(-$xt / 8);
    $ax2->title("Stem plot");
    $ax2->set_grid(1);
    $ax2->stem($xt, $yt, color=>'coral', ms=>5);
    $ax2->axhline(0, color=>'gray', lw=>0.5, ls=>'dotted');
    $ax2->xlabel("x"); $ax2->ylabel("y");

    $fig->save("$OUT/ex05_step_stem.png");
    print "ex05_step_stem.png\n";
}

# =============================================================
# ex06: Pie chart
# =============================================================
{
    my $fig = figure(width=>700, height=>580);
    my $ax  = $fig->axes();
    $ax->title("Pie chart");
    $ax->pie(pdl(35, 25, 20, 12, 8),
        labels  => [qw(Alpha Beta Gamma Delta Other)],
        autopct => "%.0f%%",
        explode => [0.06, 0, 0, 0, 0],
    );
    $fig->save("$OUT/ex06_pie.png");
    print "ex06_pie.png\n";
}

# =============================================================
# ex07: imshow colormap gallery
# =============================================================
{
    my ($fig, @axes) = subplots(2, 3, width=>1400, height=>900);
    $fig->set_suptitle("imshow  --  colormap gallery");

    my ($rows, $cols) = (50, 60);
    my $mat = zeroes($rows, $cols);
    for my $r (0..$rows-1) {
        for my $c (0..$cols-1) {
            my $u = ($c - $cols/2) / 10;
            my $v = ($r - $rows/2) / 10;
            $mat->set($r, $c, sin($u) * cos($v));
        }
    }

    my @cmaps = qw(viridis plasma jet hot RdBu gray);
    for my $i (0..$#cmaps) {
        my $ax = $axes[int($i/3)][$i % 3];
        $ax->title($cmaps[$i]);
        $ax->imshow($mat, cmap=>$cmaps[$i]);
    }

    $fig->save("$OUT/ex07_imshow.png");
    print "ex07_imshow.png\n";
}

# =============================================================
# ex08: Filled contour
# =============================================================
{
    my $fig = figure(width=>820, height=>640);
    my $ax  = $fig->axes();
    $ax->margin_right(80);
    $ax->title("contourf  --  sin(x)*cos(y)");
    $ax->xlabel("x"); $ax->ylabel("y");

    my ($nx, $ny) = (60, 50);
    my @xs = map { -$PI + $_ * 2*$PI / ($nx-1) } 0..$nx-1;
    my @ys = map { -$PI + $_ * 2*$PI / ($ny-1) } 0..$ny-1;
    my $z  = zeroes($ny, $nx);
    for my $r (0..$ny-1) {
        for my $c (0..$nx-1) {
            $z->set($r, $c, sin($xs[$c]) * cos($ys[$r]));
        }
    }
    $ax->contourf(pdl(@xs), pdl(@ys), $z, cmap=>'RdBu');
    $fig->save("$OUT/ex08_contourf.png");
    print "ex08_contourf.png\n";
}

# =============================================================
# ex09: annotate / axvspan / axhspan
# =============================================================
{
    my $fig = figure(width=>820, height=>500);
    my $ax  = $fig->axes();
    $ax->title("annotate / axvspan / axhspan");
    $ax->set_grid(1);
    $ax->xlabel("x"); $ax->ylabel("y");

    my $x = sequence(200) / 10;
    my $y = sin($x) * exp(-$x / 8);
    $ax->line($x, $y, color=>'navy', lw=>2.0, label=>'damped sin');
    $ax->annotate("peak",
        xy     => [1.57,  sin(1.57) * exp(-1.57/8)],
        xytext => [3.8,   0.82],
        color  => 'red',
    );
    $ax->axvspan(0, $PI,    color=>'gold',  alpha=>0.12);
    $ax->axhspan(-0.1, 0.1, color=>'green', alpha=>0.15);
    $ax->axhline(0, color=>'gray', lw=>0.8, ls=>'dashed');
    $ax->legend(loc=>'upper right');
    $fig->save("$OUT/ex09_annotate.png");
    print "ex09_annotate.png\n";
}

# =============================================================
# ex10: Log scale (semilog-y / log-log)
# =============================================================
{
    my ($fig, $ax1, $ax2) = subplots(1, 2, width=>1100, height=>460);
    $fig->set_suptitle("Log scale");

    my $x = sequence(100) * 0.1 + 0.1;
    $ax1->title("semilog-y");
    $ax1->set_yscale('log');
    $ax1->set_grid(1);
    $ax1->line($x, exp($x),       color=>'blue',   lw=>2, label=>"e^x");
    $ax1->line($x, exp($x * 0.5), color=>'orange', lw=>2, label=>"e^{0.5x}", ls=>'dashed');
    $ax1->line($x, $x**3,         color=>'green',  lw=>2, label=>"x^3",      ls=>'dotted');
    $ax1->xlabel("x"); $ax1->ylabel("y  (log)");
    $ax1->legend(loc=>'upper left');

    my $xp = sequence(50) * 0.2 + 0.2;
    $ax2->title("log-log");
    $ax2->set_xscale('log');
    $ax2->set_yscale('log');
    $ax2->set_grid(1);
    $ax2->line($xp, $xp**2,   color=>'blue', lw=>2, label=>"x^2");
    $ax2->line($xp, $xp**0.5, color=>'red',  lw=>2, label=>"x^{0.5}", ls=>'dashed');
    $ax2->line($xp, $xp,      color=>'gray', lw=>1, label=>"x",       ls=>'dotted');
    $ax2->xlabel("x  (log)"); $ax2->ylabel("y  (log)");
    $ax2->legend(loc=>'upper left');

    $fig->save("$OUT/ex10_logscale.png");
    print "ex10_logscale.png\n";
}

# =============================================================
# ex11: Dual Y axis (twinx)
# =============================================================
{
    my $fig = figure(width=>860, height=>500);
    my $ax1 = $fig->axes();
    my $ax2 = $ax1->twinx();
    $fig->add_axes($ax2);

    my $h    = sequence(24);
    my $temp = 15 + 10 * sin(($h - 6) * $PI / 12);
    my $hum  = 70 - 20 * sin(($h - 6) * $PI / 12);

    $ax1->title("Temperature & Humidity  (twinx)");
    $ax1->xlabel("Hour");
    $ax1->ylabel("Temperature (\x{00B0}C)");
    $ax1->line($h, $temp, color=>'red', lw=>2.5, label=>"Temp (\x{00B0}C)");
    $ax1->legend(loc=>'upper left');
    $ax1->set_grid(1);
    $ax1->ylim(0, 35);

    $ax2->line($h, $hum, color=>'blue', lw=>2.0, ls=>'dashed', label=>"Humidity (%)");
    $ax2->set_right_ylabel("Humidity (%)");
    $ax2->legend(loc=>'upper right');
    $ax2->ylim(40, 100);
    $ax2->xlim(0, 23);

    $fig->save("$OUT/ex11_twinx.png");
    print "ex11_twinx.png\n";
}

# =============================================================
# ex12: Statistical dashboard (2x2 subplot)
# =============================================================
{
    my ($fig, @axes) = subplots(2, 2, width=>1100, height=>900);
    my ($ax1, $ax2) = @{ $axes[0] };
    my ($ax3, $ax4) = @{ $axes[1] };
    $fig->set_suptitle("Statistical Analysis Dashboard");

    # [1,1] Time series + confidence band
    my $t      = sequence(200) / 10;
    my $signal = sin($t * 2) * exp(-$t/15) + grandom(200) * 0.1;
    my $smooth = sin($t * 2) * exp(-$t/15);
    $ax1->title("Time series");
    $ax1->fill_between($t, $smooth - 0.2, $smooth + 0.2, color=>'blue', alpha=>0.15);
    $ax1->line($t, $signal, color=>'lightblue', lw=>0.8, alpha=>0.5);
    $ax1->line($t, $smooth, color=>'blue',      lw=>2.0, label=>"model");
    $ax1->legend(loc=>'upper right');
    $ax1->set_grid(1);
    $ax1->xlabel("t"); $ax1->ylabel("amplitude");

    # [1,2] Overlapping histograms
    my $d1 = grandom(400);
    my $d2 = grandom(400) * 0.6 + 1.0;
    $ax2->title("Overlapping histograms");
    $ax2->hist($d1, bins=>25, color=>'steelblue', alpha=>0.6, label=>"N(0,1)");
    $ax2->hist($d2, bins=>25, color=>'coral',     alpha=>0.6, label=>"N(1,0.6)");
    $ax2->axvline(0,   color=>'steelblue', lw=>1.2, ls=>'dashed');
    $ax2->axvline(1.0, color=>'coral',     lw=>1.2, ls=>'dashed');
    $ax2->legend(loc=>'upper right');
    $ax2->set_grid(1);
    $ax2->xlabel("value"); $ax2->ylabel("count");

    # [2,1] Empirical CDF
    my @sorted = sort { $a <=> $b } list($d1);
    my $nn     = scalar @sorted;
    my $cdf_x  = pdl(@sorted);
    my $cdf_y  = sequence($nn) / ($nn - 1);
    $ax3->title("Empirical CDF");
    $ax3->step($cdf_x, $cdf_y, color=>'blue', lw=>2, where=>'post', label=>"N(0,1) CDF");
    $ax3->axhline(0.5, color=>'gray', lw=>1.0, ls=>'dashed');
    $ax3->axvline(0,   color=>'gray', lw=>1.0, ls=>'dotted');
    $ax3->ylim(0, 1.05);
    $ax3->legend(loc=>'lower right');
    $ax3->set_grid(1);
    $ax3->xlabel("x"); $ax3->ylabel("P(X <= x)");

    # [2,2] Bar + error bars
    my @grps  = (1..5);
    my @means = (2.3, 4.1, 3.5, 5.2, 2.8);
    my @stds  = (0.3, 0.5, 0.4, 0.6, 0.3);
    $ax4->title("Bar + Errorbar");
    $ax4->bar(pdl(@grps), pdl(@means), width=>0.6, color=>'steelblue', alpha=>0.7);
    $ax4->errorbar(pdl(@grps), pdl(@means),
        yerr    => pdl(@stds),
        color   => 'black',
        lw      => 1.5,
        capsize => 5,
        marker  => 'none',
    );
    $ax4->xticks(\@grps, [qw(A B C D E)]);
    $ax4->ylim(0, 7);
    $ax4->set_grid(1);
    $ax4->xlabel("Group"); $ax4->ylabel("Mean \x{00B1} SD");

    $fig->save("$OUT/ex12_dashboard.png");
    print "ex12_dashboard.png\n";
}

print "\nAll examples done. Output: $OUT/\n";
