#!/usr/bin/env perl
# example_gridspec.pl — PDL::Graphics::Cairo GridSpec / subplot_mosaic デモ
# 実行: perl -I./lib examples/example_gridspec.pl

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots subplot_mosaic);

my $PI = 3.14159265358979;

# ============================================================
# Demo 1: GridSpec — 非均一サブプロット
#   ┌─────────────────────┐
#   │       ax1 (top)     │  ← 2列分スパン
#   ├──────────┬──────────┤
#   │  ax2 (L) │  ax3 (R) │
#   └──────────┴──────────┘
# ============================================================
{
    my $fig = figure(width=>800, height=>550);
    my $gs  = $fig->add_gridspec(2, 2,
        top    => 0.90,
        bottom => 0.08,
        left   => 0.10,
        right  => 0.95,
        hspace => 0.40,
        wspace => 0.30,
    );

    my $ax1 = $fig->add_subplot($gs->at(0, ':'));
    my $ax2 = $fig->add_subplot($gs->at(1, 0));
    my $ax3 = $fig->add_subplot($gs->at(1, 1));

    my $t = sequence(500) / 100;
    $ax1->line($t, sin(2*$PI*$t), color=>'steelblue', lw=>2, label=>'sin(2πt)');
    $ax1->line($t, cos(2*$PI*$t), color=>'tomato',    lw=>2, label=>'cos(2πt)');
    $ax1->xlabel('Time (s)'); $ax1->ylabel('Amplitude');
    $ax1->title('Sine and Cosine waves');
    $ax1->legend; $ax1->grid(1);
    $ax1->ylim(-1.3, 1.3);

    my $data = grandom(500) * 2 + 3;
    $ax2->hist($data, bins=>20, color=>'steelblue', alpha=>0.75);
    $ax2->xlabel('Value'); $ax2->ylabel('Count');
    $ax2->title('Normal Distribution');

    my $x = grandom(80);
    my $y = $x * 1.5 + grandom(80) * 0.5;
    $ax3->scatter($x, $y, s=>20, color=>'tomato', alpha=>0.7);
    $ax3->xlabel('X'); $ax3->ylabel('Y');
    $ax3->title('Y ≈ 1.5X + noise');

    $fig->suptitle('GridSpec: Non-uniform Layout', fontsize=>14);
    $fig->tight_layout;
    $fig->save('/tmp/gridspec_demo_basic.png');
    print "Saved: /tmp/gridspec_demo_basic.png\n";
}

# ============================================================
# Demo 2: GridSpec 2x3 — 複雑なスパン
# ============================================================
{
    my $fig = figure(width=>800, height=>600);
    my $gs  = $fig->add_gridspec(2, 3,
        top=>0.88, bottom=>0.09,
        left=>0.09, right=>0.96,
        hspace=>0.45, wspace=>0.35,
    );

    my $axA = $fig->add_subplot($gs->at(0, '0:2'));
    my $axB = $fig->add_subplot($gs->at(0, 2));
    my $axC = $fig->add_subplot($gs->at(1, 0));
    my $axD = $fig->add_subplot($gs->at(1, '1:3'));

    my $img = sin(sequence(30)->slice(':,*1') * 0.3)
            * cos(sequence(30)->slice('*1,:') * 0.3);
    $axA->imshow($img, cmap=>'RdBu', vmin=>-1, vmax=>1);
    $axA->title('A: 2D map (30×30)');

    $axB->bar(pdl(1..4), pdl(3.2, 1.8, 4.5, 2.1), color=>'steelblue', alpha=>0.8);
    $axB->title('B: Bar'); $axB->tick_params(labelsize=>7);

    my $xc = sequence(20) * 0.5;
    $axC->line($xc, $xc**2 * 0.1, color=>'seagreen', lw=>2);
    $axC->title('C: Quadratic'); $axC->tick_params(labelsize=>7);

    my $td = sequence(100) / 10;
    $axD->line($td, sin($td),         color=>'royalblue', lw=>1.5, label=>'sin(t)');
    $axD->line($td, sin($td*2)*0.5,   color=>'tomato',   lw=>1.5, label=>'sin(2t)/2');
    $axD->legend; $axD->title('D: Waveforms'); $axD->grid(1);

    $fig->suptitle('GridSpec 2×3: Spanning Panels', fontsize=>13);
    $fig->tight_layout;
    $fig->save('/tmp/gridspec_demo_complex.png');
    print "Saved: /tmp/gridspec_demo_complex.png\n";
}

# ============================================================
# Demo 3: subplot_mosaic
#   "AAB"
#   "CDB"
#   "CDE"
# ============================================================
{
    my ($fig, %ax) = subplot_mosaic(
        "AAB\nCDB\nCDE",
        width  => 800,
        height => 650,
        top    => 0.88,
        bottom => 0.07,
        left   => 0.10,
        right  => 0.97,
        hspace => 0.45,
        wspace => 0.40,
    );

    # A: 対数スペクトル
    my $freq = sequence(50) + 1;
    $ax{A}->line($freq, 1.0 / $freq**1.5, color=>'purple', lw=>2);
    $ax{A}->xlabel('Frequency (Hz)'); $ax{A}->ylabel('Power');
    $ax{A}->title('A: Power spectrum (1/f^1.5)');
    $ax{A}->grid(1); $ax{A}->ylim(0, 1.1);

    # B: 水平棒グラフ（縦長パネル）
    $ax{B}->barh(pdl(1..5), pdl(4.2, 3.1, 5.0, 2.8, 3.7),
                 color=>'teal', alpha=>0.8);
    $ax{B}->title('B'); $ax{B}->tick_params(labelsize=>7);

    # C: 散布図
    my $cx = grandom(60) * 0.8;
    my $cy = grandom(60) * 0.8;
    $ax{C}->scatter($cx, $cy, s=>15, color=>'coral', alpha=>0.7);
    $ax{C}->title('C: Scatter'); $ax{C}->tick_params(labelsize=>7);

    # D: ヒートマップ
    my $z = sin(sequence(12)->slice(':,*1') * 0.6)
           + cos(sequence(12)->slice('*1,:') * 0.4);
    $ax{D}->heatmap($z, cmap=>'viridis');
    $ax{D}->title('D: Heatmap'); $ax{D}->tick_params(labelsize=>7);

    # E: ヒストグラム
    $ax{E}->hist(grandom(200), bins=>12, color=>'steelblue', alpha=>0.8);
    $ax{E}->title('E: Hist'); $ax{E}->tick_params(labelsize=>7);

    $fig->suptitle('subplot_mosaic: "AAB / CDB / CDE"', fontsize=>13);
    $fig->tight_layout;
    $fig->save('/tmp/gridspec_demo_mosaic.png');
    print "Saved: /tmp/gridspec_demo_mosaic.png\n";
}

print "\nDone. Open with: open /tmp/gridspec_demo_*.png\n";
