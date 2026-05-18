#!/usr/bin/env perl
# =============================================================
# example_show.pl  --  PDL::Graphics::Cairo interactive display demo
#
# Run from PDL-Graphics-Cairo/ root:
#   perl -I./lib examples/example_show.pl              # auto-detect terminal
#   perl -I./lib examples/example_show.pl aqua         # macOS Aquaterm
#   perl -I./lib examples/example_show.pl x11          # X11 / XQuartz
#   perl -I./lib examples/example_show.pl wxt          # wxWidgets
#
# Also demonstrates the PGPLOT compatibility layer with /xw device:
#   perl -I./lib examples/example_show.pl pgplot_xw
#
# Requirements:
#   gnuplot  (installed separately via OS package manager)
#
#   macOS (MacPorts):
#     sudo port install gnuplot +aquaterm
#     sudo port install aquaterm        # from https://aquaterm.sourceforge.net
#
#   Ubuntu/Debian:
#     sudo apt install gnuplot-x11
#
# How it works:
#   $fig->show() writes a temporary PNG to /tmp/pdlcairo_XXXXXX.png
#   and passes it to gnuplot for display.
#   The file is removed when the Perl process exits.
#   Use show(keep=>1) to retain the temporary file for debugging.
#
# Device strings for PGPLOT layer:
#   "/xw"   -> gnuplot x11   (X11 / XQuartz)
#   "/AQT"  -> gnuplot aqua  (macOS Aquaterm)
#   "/wxt"  -> gnuplot wxt
#   "/PNG"  -> Cairo PNG file output (no gnuplot)
# =============================================================

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);
use PDL::Graphics::Cairo::PGPLOT qw(:all);

my $PI = 3.14159265358979;

# Ensure white background for this example regardless of PGPLOT_BACKGROUND setting.
# Remove this line if you prefer a black background:
#   PGPLOT_BACKGROUND=black perl -I./lib examples/example_show.pl
$ENV{PGPLOT_BACKGROUND} //= 'white';

# Terminal selection
# argv[0]: 'aqua' | 'x11' | 'wxt' | 'pgplot_xw' | (empty = auto)
my $term_arg = $ARGV[0] // '';

# =============================================================
# Helper: show() wrapper that passes terminal if specified
# =============================================================
sub show_fig {
    my ($fig) = @_;
    if ($term_arg ne '') {
        # Pass user-specified terminal unconditionally.
        # Driver::Gnuplot will warn if it falls back to another terminal.
        $fig->show(terminal => lc($term_arg));
    } else {
        $fig->show();   # auto-detect
    }
}

# =============================================================
# PGPLOT /xw demo (run with: perl example_show.pl pgplot_xw)
# =============================================================
if ($term_arg eq 'pgplot_xw') {
    print "PGPLOT layer -- interactive display via /xw (X11)\n";
    print "Requires gnuplot with x11 terminal.\n\n";

    # Device strings:
    #   "/xw"  or "/XW"   -> gnuplot x11
    #   "/AQT"            -> gnuplot aqua (macOS)
    #   "/wxt"            -> gnuplot wxt
    my $dev = "/xw";   # change to "/AQT" on macOS with Aquaterm

    # --- Demo A: basic line + pgbox ---
    {
        print "Demo A: line + pgbox via $dev ...\n";
        pgbegin(0, $dev, 1, 1);
        pgpap(8, 0.75);

        my $n = 200;
        my @t = map { $_ / 10 } 0..$n-1;
        my @y = map { sin($t[$_]) * exp(-$t[$_]/8) } 0..$n-1;

        pgenv(0, 20, -1.1, 1.1, 0, -2);
        pgsci(3); pgslw(2);
        pgline($n, \@t, \@y);
        pgsci(1); pgslw(1);
        pgbox("ANST", 0.0, 1, "ANTV", 0.5, 2);
        pgmtxt("TR", -1, 0.1, 1.0, "damped sin");
        pgend();
        print "  -> window opened (close to continue)\n";
        sleep 1;
    }

    # --- Demo B: 2x3 subpanels ---
    {
        print "Demo B: 2x3 subpanels via $dev ...\n";
        pgbegin(0, $dev, -2, 3);
        pgpap(10, 0.75);

        my $n = 200;
        my @t = map { $_ / 10 } 0..$n-1;
        my @titles = ("sin", "cos", "sin+cos", "damped", "square", "noise");
        my @funcs  = (
            sub { sin($_[0]) },
            sub { cos($_[0]) },
            sub { sin($_[0]) + cos($_[0]) },
            sub { sin($_[0]*3) * exp(-$_[0]/5) },
            sub { sin($_[0]) > 0 ? 1 : -1 },
            sub { sin($_[0]) + (rand()-0.5)*0.3 },
        );

        for my $i (0..$#titles) {
            my @y = map { $funcs[$i]->($t[$_]) } 0..$n-1;
            my $ymax = 2.0;
            pgenv(-100, 899, $ymax, -$ymax, 0, -2);
            pgsci(3); pgslw(1);
            pgline($n, \@t, \@y);
            pgsci(1);
            pgbox("ANST", 0.0, 1, "ANTV", 1.0, 2);
            pgmtxt("TR", -1, 0.1, 1.0, $titles[$i]);
            pgpage();
        }
        pgend();
        print "  -> window opened\n";
    }

    print "\nPGPLOT /xw demos done.\n";
    exit 0;
}

# =============================================================
# Cairo API interactive demos
# =============================================================

print "PDL::Graphics::Cairo -- interactive display demo\n";
if ($term_arg) {
    print "Terminal: $term_arg\n\n";
} else {
    print "Terminal: auto-detect (aqua -> wxt -> x11 -> qt)\n\n";
}

# =============================================================
# Demo 1: Basic line plot (sin / cos)
# =============================================================
{
    print "Demo 1/4: Line plot (sin/cos) ...\n";

    my $x = sequence(300) / 15;

    my $fig = figure(width => 800, height => 500);
    my $ax  = $fig->axes();

    $ax->title("sin(x) and cos(x)");
    $ax->xlabel("x");
    $ax->ylabel("y");
    $ax->set_grid(1);
    $ax->line($x, sin($x), color=>'blue',   lw=>2, label=>'sin(x)');
    $ax->line($x, cos($x), color=>'orange', lw=>2, label=>'cos(x)', ls=>'dashed');
    $ax->axhline(0, color=>'gray', lw=>0.8, ls=>'dotted');
    $ax->legend(loc=>'upper right');

    show_fig($fig);
    print "  -> window opened\n";
    sleep 1;
}

# =============================================================
# Demo 2: Scatter plot with colormap
# =============================================================
{
    print "Demo 2/4: Scatter plot (colormap: plasma) ...\n";

    my $n  = 400;
    my $sx = grandom($n);
    my $sy = grandom($n);
    my $sc = sqrt($sx*$sx + $sy*$sy);

    my $fig = figure(width => 700, height => 600);
    my $ax  = $fig->axes();
    $ax->margin_right(70);

    $ax->title("Scatter plot with colormap");
    $ax->scatter($sx, $sy, c=>$sc, cmap=>'plasma', s=>5, alpha=>0.8);
    $ax->axhline(0, color=>'gray', lw=>0.5, ls=>'dotted');
    $ax->axvline(0, color=>'gray', lw=>0.5, ls=>'dotted');
    $ax->set_grid(1);
    $ax->xlabel("x"); $ax->ylabel("y");

    show_fig($fig);
    print "  -> window opened\n";
    sleep 1;
}

# =============================================================
# Demo 3: Dual Y axis (twinx)
# =============================================================
{
    print "Demo 3/4: Dual Y axis (twinx) ...\n";

    my $h    = sequence(24);
    my $temp = 15 + 10 * sin(($h - 6) * $PI / 12);
    my $hum  = 70 - 20 * sin(($h - 6) * $PI / 12);

    my $fig = figure(width => 860, height => 500);
    my $ax1 = $fig->axes();
    my $ax2 = $ax1->twinx();
    $fig->add_axes($ax2);

    $ax1->title("Temperature & Humidity  (twinx)");
    $ax1->xlabel("Hour");
    $ax1->ylabel("Temperature (\x{00B0}C)");
    $ax1->line($h, $temp, color=>'red',  lw=>2.5, label=>"Temp (\x{00B0}C)");
    $ax1->legend(loc=>'upper left');
    $ax1->set_grid(1);
    $ax1->ylim(0, 35);

    $ax2->line($h, $hum, color=>'blue', lw=>2.0, ls=>'dashed',
               label=>"Humidity (%)");
    $ax2->set_right_ylabel("Humidity (%)");
    $ax2->legend(loc=>'upper right');
    $ax2->ylim(40, 100);

    show_fig($fig);
    print "  -> window opened\n";
    sleep 1;
}

# =============================================================
# Demo 4: 2x2 subplot
# =============================================================
{
    print "Demo 4/4: 2x2 subplot ...\n";

    my ($fig, @axes) = subplots(2, 2, width=>1000, height=>800);
    my ($ax1, $ax2) = @{ $axes[0] };
    my ($ax3, $ax4) = @{ $axes[1] };
    $fig->set_suptitle("PDL::Graphics::Cairo -- 2x2 subplot");

    # [1,1] Damped oscillation
    my $t = sequence(200) / 10;
    my $y = sin($t * 3) * exp(-$t / 5);
    $ax1->title("Damped oscillation");
    $ax1->line($t, $y, color=>'blue', lw=>2);
    $ax1->axhline(0, color=>'gray', lw=>0.5, ls=>'dotted');
    $ax1->set_grid(1);
    $ax1->xlabel("t"); $ax1->ylabel("y");

    # [1,2] Histogram
    my $data = grandom(600);
    $ax2->title("Histogram  N(0,1)");
    $ax2->hist($data, bins=>25, color=>'steelblue', alpha=>0.8);
    $ax2->axvline(0, color=>'red', lw=>1.2, ls=>'dashed');
    $ax2->set_grid(1);
    $ax2->xlabel("value"); $ax2->ylabel("count");

    # [2,1] Bar chart
    my @cats = (1..6);
    my @vals = (3.2, 4.8, 2.1, 5.5, 3.9, 4.4);
    $ax3->title("Bar chart");
    $ax3->bar(pdl(@cats), pdl(@vals), width=>0.6, color=>'coral', alpha=>0.85);
    $ax3->xticks(\@cats, [qw(Jan Feb Mar Apr May Jun)]);
    $ax3->ylim(0, 7); $ax3->set_grid(1);
    $ax3->xlabel("Month"); $ax3->ylabel("Value");

    # [2,2] Pie chart
    $ax4->title("Pie chart");
    $ax4->pie(pdl(35, 25, 20, 12, 8),
        labels  => [qw(Alpha Beta Gamma Delta Other)],
        autopct => "%.0f%%",
        explode => [0.06, 0, 0, 0, 0],
    );

    show_fig($fig);
    print "  -> window opened\n";
}

print "\nAll demos done.\n";
print "Close the windows or press Ctrl-C to exit.\n";
