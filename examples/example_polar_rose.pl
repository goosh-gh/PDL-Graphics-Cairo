#!/usr/bin/env perl
# example_polar_rose.pl — PDL::Graphics::Cairo Wind Rose (風配図) デモ
#
# example_polar_tuning.pl がニューロンの方向選択性・位相分布を
# 扱うのに対し、本ファイルは気象データの風配図という、コンパス系
# 極座標(set_theta_zero_location/set_theta_direction)のもっとも
# 典型的な応用例に特化する。複数の風速ビンを積み上げて表示する
# stacked wind rose も扱う。
#
# 実行: perl -I./lib examples/example_polar_rose.pl

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

my $PI = 3.14159265358979;

# ============================================================
# Demo 1: 単純な風配図 — 16方位の頻度
#   北=0度、時計回りという気象データの標準的な方位角表現。
# ============================================================
{
    my @dir_labels = qw(N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW);
    my $n = scalar @dir_labels;
    my $theta = sequence($n) / $n * 2 * $PI;

    # 西寄りの風がやや多い、という模擬データ
    my $freq = pdl(
        4, 3, 5, 6, 8, 10, 12, 15,
        18, 22, 25, 20, 14, 9, 6, 5,
    );

    my $fig = figure(width=>600, height=>600);
    my $ax  = $fig->add_subplot(1,1,1, projection=>'polar');
    $ax->set_theta_zero_location('N');
    $ax->set_theta_direction(-1);

    $ax->bar($theta, $freq, color=>'steelblue', alpha=>0.8);
    $ax->set_rmax(28);
    $ax->set_thetagrids([0,90,180,270]);   # N/E/S/W のみ表示
    $ax->set_title('Wind Rose — Direction Frequency (%)');
    $fig->tight_layout();
    $fig->save('/tmp/polar_rose_demo_simple.png');
    print "Saved: /tmp/polar_rose_demo_simple.png\n";
}

# ============================================================
# Demo 2: 積み上げ風配図 — 風速ビンごとに色分けして重ね描き
#   各方位について「弱風」「中風」「強風」の内訳を積み上げ表示する、
#   気象学で標準的な stacked wind rose 表現。
#   PDL::Graphics::Cairo::PolarAxes には積み上げbar専用APIは無いため、
#   bar(bottom=>...)を使って手動で積み上げる。
# ============================================================
{
    my $n = 12;   # 30度刻み12方位
    my $theta = sequence($n) / $n * 2 * $PI;

    # 風速ビン別の頻度(%) — 行=ビン、列=方位
    my %speed_bins = (
        '0-3 m/s'  => pdl(3,2,2,3,4,5,6,7,8,6,4,3),
        '3-6 m/s'  => pdl(5,4,3,4,6,8,9,11,12,10,7,5),
        '6-10 m/s' => pdl(2,1,1,2,3,4,5,6,7,5,3,2),
    );
    my @bin_order = ('0-3 m/s', '3-6 m/s', '6-10 m/s');
    my @colors    = ('#c6dbef', '#6baed6', '#08519c');   # 薄→濃の青系

    my $fig = figure(width=>650, height=>650);
    my $ax  = $fig->add_subplot(1,1,1, projection=>'polar');
    $ax->set_theta_zero_location('N');
    $ax->set_theta_direction(-1);

    my $cumulative = zeroes($n);   # 積み上げの土台(初期値0)
    for my $i (0 .. $#bin_order) {
        my $bin_name = $bin_order[$i];
        my $vals     = $speed_bins{$bin_name};
        $ax->bar($theta, $vals,
            bottom => $cumulative,
            color  => $colors[$i],
            alpha  => 0.9,
            label  => $bin_name,
        );
        $cumulative = $cumulative + $vals;
    }

    $ax->set_rmax($cumulative->max * 1.15);
    $ax->set_title('Stacked Wind Rose by Speed Bin');
    $ax->legend();
    $fig->tight_layout();
    $fig->save('/tmp/polar_rose_demo_stacked.png');
    print "Saved: /tmp/polar_rose_demo_stacked.png\n";
}

# ============================================================
# Demo 3: 数学系極座標との対比 — 同じデータを標準数学座標
#   (東=0度、反時計回り、theta_direction=>1がデフォルト)で描き、
#   コンパス座標との見た目の違いを並べて確認する。
# ============================================================
{
    my $n = 16;
    my $theta = sequence($n) / $n * 2 * $PI;
    my $freq  = pdl(4,3,5,6,8,10,12,15,18,22,25,20,14,9,6,5);

    # PolarAxesは現状、通常のAxesと混在したグリッド配置(subplots)を
    # サポートしていないため、比較用に2つの独立したFigureを作る。
    # 左: 通常の数学座標 (東=0度、反時計回り)
    my $fig_math = figure(width=>480, height=>480);
    my $ax_math = $fig_math->add_subplot(1,1,1, projection=>'polar');
    $ax_math->bar($theta, $freq, color=>'darkorange', alpha=>0.8);
    $ax_math->set_rmax(28);
    $ax_math->set_title('Mathematical convention (E=0°, CCW)');
    $fig_math->tight_layout();
    $fig_math->save('/tmp/polar_rose_demo_compare_math.png');

    # 右: コンパス座標 (北=0度、時計回り)
    my $fig_compass = figure(width=>480, height=>480);
    my $ax_compass = $fig_compass->add_subplot(1,1,1, projection=>'polar');
    $ax_compass->set_theta_zero_location('N');
    $ax_compass->set_theta_direction(-1);
    $ax_compass->bar($theta, $freq, color=>'steelblue', alpha=>0.8);
    $ax_compass->set_rmax(28);
    $ax_compass->set_title('Compass convention (N=0°, CW)');
    $fig_compass->tight_layout();
    $fig_compass->save('/tmp/polar_rose_demo_compare_compass.png');

    print "Saved: /tmp/polar_rose_demo_compare_math.png\n";
    print "Saved: /tmp/polar_rose_demo_compare_compass.png\n";
    print "  (同じ周波数データを2つの角度規約で描いた比較用)\n";
}

print "\nDone. Open with: open /tmp/polar_rose_demo_*.png\n";
