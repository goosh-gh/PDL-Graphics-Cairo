#!/usr/bin/env perl
# =============================================================
# pdlcairo_osx_demo.pl  --  macOS native Cocoa backend demo
#
# Run from PDL-Graphics-Cairo/ root:
#   perl -I./lib examples/pdlcairo_osx_demo.pl          # macOS native
#   perl -I./lib examples/pdlcairo_osx_demo.pl gnuplot  # via gnuplot/AquaTerm
#
# Requires:
#   pdlcairo_viewer (built by: make)
# =============================================================

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

my $PI = 3.14159265358979;
my $backend = $ARGV[0] // 'osx';

sub show_fig {
    my ($fig, %opt) = @_;
    if ($backend eq 'gnuplot') {
        $fig->show(terminal => 'aqua');
    } else {
        $fig->show(backend => 'osx',
                   title   => $opt{title} // 'PDL::Graphics::Cairo');
    }
}

# =============================================================
# 4パネルデモ（giza_osx_demo.cと同じ構成）
# =============================================================
{
    my ($fig, $row1, $row2) = subplots(2, 2, width => 900, height => 700);
    my ($ax1, $ax2) = @$row1;
    my ($ax3, $ax4) = @$row2;

    $fig->set_suptitle('PDL::Graphics::Cairo — macOS Native Demo');

    # パネル1: Sine / Cosine
    {
        my $x = sequence(300) / 299 * 2 * $PI;
        $ax1->title('Sine & Cosine');
        $ax1->xlabel('x');
        $ax1->ylabel('y');
        $ax1->set_grid(1);
        $ax1->line($x, sin($x),
            color => [0.85, 0.2,  0.2], lw => 2, label => 'sin(x)');
        $ax1->line($x, cos($x),
            color => [0.2,  0.4,  0.85], lw => 2,
            ls => 'dashed', label => 'cos(x)');
        $ax1->legend();
    }

    # パネル2: 散布図
    {
        my $n  = 300;
        my $rx = grandom($n);
        my $ry = grandom($n) * 0.5 + $rx * 0.6;
        $ax2->title('Scatter plot (N=300)');
        $ax2->xlabel('x');
        $ax2->ylabel('y');
        $ax2->set_grid(1);
        $ax2->scatter($rx, $ry,
            color => [0.15, 0.65, 0.35], marker => 'o',
            s => 4, alpha => 0.7);
    }

    # パネル3: 棒グラフ
    {
        my @cats   = (1..8);
        my @vals   = (3.2, 5.1, 7.8, 6.4, 4.9, 8.3, 5.6, 3.7);
        my @colors = (
            [0.85, 0.2,  0.2 ], [0.2,  0.65, 0.3 ],
            [0.2,  0.3,  0.85], [0.3,  0.55, 0.55],
            [0.6,  0.25, 0.65], [0.15, 0.7,  0.75],
            [0.9,  0.45, 0.1 ], [0.5,  0.55, 0.6 ],
        );
        $ax3->title('Bar chart');
        $ax3->xlabel('Category');
        $ax3->ylabel('Value');
        $ax3->set_grid(1);
        for my $i (0..$#vals) {
            $ax3->bar(pdl($cats[$i]), pdl($vals[$i]),
                color => $colors[$i], width => 0.7);
        }
    }

    # パネル4: 2Dガウシアン カラーマップ
    {
        my $nx = 64; my $ny = 64;
        my $X  = (sequence($nx) - $nx/2)->dummy(0, $ny) / ($nx/8);
        my $Y  = (sequence($ny) - $ny/2)->dummy(1, $nx) / ($ny/8);
        my $Z  = exp(-($X**2 + $Y**2) / 2)
               + 0.5 * exp(-(($X-2)**2 + ($Y-2)**2) / 1.5);
        $ax4->title('2D Gaussian colormap');
        $ax4->xlabel('x');
        $ax4->ylabel('y');
        $ax4->imshow($Z, cmap => 'hot', extent => [-4, 4, -4, 4]);
        $ax4->colorbar(label => 'intensity');
    }

    $fig->tight_layout();
    show_fig($fig, title => 'PDL::Graphics::Cairo Demo');
}

print "Done.\n";
