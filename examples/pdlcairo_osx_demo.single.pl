#!/usr/bin/env perl
# pdlcairo_osx_demo.pl
# PDL::Graphics::Cairo + OSXネイティブバックエンド デモ
# giza_osx_demo.c と同じ4パネル構成
#
# 実行方法:
#   cd ~/src/PDL_Graphics_Cairo
#   perl -Ilib examples/pdlcairo_osx_demo.pl
#
# キー操作:
#   q / ESC / Return → ウィンドウを閉じる

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

# ------------------------------------------------------------------
# Figure生成（2×2パネル）
# ------------------------------------------------------------------
my ($fig, $row1, $row2) = subplots(2, 2,
    width  => 900,
    height => 700,
);
my ($ax1, $ax2) = @$row1;
my ($ax3, $ax4) = @$row2;

$fig->set_suptitle('PDL::Graphics::Cairo — macOS Native Demo');

# ------------------------------------------------------------------
# パネル1: Sine / Cosine 折れ線
# ------------------------------------------------------------------
{
    my $x   = sequence(300) / 299 * 2 * 3.14159265;
    my $sin = sin($x);
    my $cos = cos($x);

    $ax1->line($x, $sin,
        color     => [0.85, 0.2,  0.2 ],
        linewidth => 2,
        label     => 'sin(x)',
    );
    $ax1->line($x, $cos,
        color     => [0.2,  0.4,  0.85],
        linewidth => 2,
        linestyle => 'dashed',
        label     => 'cos(x)',
    );
    $ax1->set_title('Sine & Cosine');
    $ax1->set_xlabel('x');
    $ax1->set_ylabel('y');
    $ax1->legend();
    $ax1->set_grid(1);
}

# ------------------------------------------------------------------
# パネル2: 散布図（相関あり正規乱数）
# ------------------------------------------------------------------
{
    my $n  = 300;
    my $rx = grandom($n);
    my $ry = grandom($n) * 0.5 + $rx * 0.6;

    $ax2->scatter($rx, $ry,
        color  => [0.15, 0.65, 0.35],
        marker => 'o',
        size   => 4,
        alpha  => 0.7,
    );
    $ax2->set_title('Scatter plot (N=300)');
    $ax2->set_xlabel('x');
    $ax2->set_ylabel('y');
    $ax2->set_grid(1);
}

# ------------------------------------------------------------------
# パネル3: 棒グラフ
# ------------------------------------------------------------------
{
    my @labels = (1..8);
    my @vals   = (3.2, 5.1, 7.8, 6.4, 4.9, 8.3, 5.6, 3.7);
    my @colors = (
        [0.85, 0.2,  0.2 ],
        [0.2,  0.65, 0.3 ],
        [0.2,  0.3,  0.85],
        [0.3,  0.55, 0.55],
        [0.6,  0.25, 0.65],
        [0.15, 0.7,  0.75],
        [0.9,  0.45, 0.1 ],
        [0.5,  0.55, 0.6 ],
    );

    for my $i (0..$#vals) {
        $ax3->bar(
            pdl($labels[$i]), pdl($vals[$i]),
            color => $colors[$i],
            width => 0.7,
        );
    }
    $ax3->set_title('Bar chart');
    $ax3->set_xlabel('Category');
    $ax3->set_ylabel('Value');
    $ax3->set_grid(1);
}

# ------------------------------------------------------------------
# パネル4: 2Dガウシアン カラーマップ
# ------------------------------------------------------------------
{
    my $nx = 64;
    my $ny = 64;
    my $xi = (sequence($nx) - $nx/2) / ($nx/8);
    my $yi = (sequence($ny) - $ny/2) / ($ny/8);

    # グリッド生成
    my $X = $xi->dummy(0, $ny);  # [$ny, $nx]
    my $Y = $yi->dummy(1, $nx);  # [$ny, $nx]
    my $Z = exp(-($X**2 + $Y**2) / 2)
          + 0.5 * exp(-(($X-2)**2 + ($Y-2)**2) / 1.5);

    $ax4->imshow($Z,
        cmap   => 'hot',
        extent => [-4, 4, -4, 4],
    );
    $ax4->set_title('2D Gaussian colormap');
    $ax4->set_xlabel('x');
    $ax4->set_ylabel('y');
    $ax4->colorbar(label => 'intensity');
}

# ------------------------------------------------------------------
# 表示（macOSネイティブCocoaウィンドウ）
# ------------------------------------------------------------------
$fig->tight_layout();
$fig->show(backend => 'osx', title => 'PDL::Graphics::Cairo Demo');

