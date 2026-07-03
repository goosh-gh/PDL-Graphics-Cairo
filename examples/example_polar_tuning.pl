#!/usr/bin/env perl
# example_polar_tuning.pl — PDL::Graphics::Cairo 極座標プロット
# 神経科学での典型的な使用例: 方向選択性チューニングカーブ、
# 位相分布、Rose diagram(風配図/サッカード方向分布)。
# 実行: perl -I./lib examples/example_polar_tuning.pl

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

my $PI = 3.14159265358979;

# von Mises 分布: 円周上のチューニングカーブの標準的なモデル。
# matplotlib/numpyのscipy.stats.vonmisesに相当する自前実装。
sub von_mises_tuning {
    my ($theta, $pref, $kappa) = @_;
    my $raw = exp($kappa * cos($theta - $pref));
    return $raw / $raw->max;   # ピークを1に正規化
}

# ============================================================
# Demo 1: 複数細胞の方向選択性チューニングカーブ
#   視覚野/運動野ニューロンの典型的な記録結果を模した図。
#   各細胞は異なる選好方向(preferred direction)を持つ
#   von Mises 分布（円周上のガウシアン相当）で近似する。
# ============================================================
{
    my $n = 36;
    my $theta = sequence($n) / $n * 2 * $PI;

    my $fig = figure(width=>650, height=>650);
    my $ax  = $fig->add_subplot(1,1,1, projection=>'polar');

    my @cells = (
        { pref => 0,            kappa=>3,   color=>'steelblue',  label=>'Cell A (0°)'   },
        { pref => $PI/3,        kappa=>4,   color=>'darkorange', label=>'Cell B (60°)'  },
        { pref => 4*$PI/3,      kappa=>2,   color=>'darkgreen',  label=>'Cell C (240°)' },
    );

    for my $cell (@cells) {
        my $r = von_mises_tuning($theta, $cell->{pref}, $cell->{kappa});
        $ax->plot($theta, $r, color=>$cell->{color}, lw=>2, label=>$cell->{label});
        $ax->fill($theta, $r, color=>$cell->{color}, alpha=>0.15);
    }

    $ax->set_rmax(1.1);
    $ax->set_rticks([0.25, 0.5, 0.75, 1.0]);
    $ax->set_title('Direction Tuning Curves (3 cells)');
    $ax->legend();
    $fig->tight_layout();
    $fig->save('/tmp/polar_tuning_demo_cells.png');
    print "Saved: /tmp/polar_tuning_demo_cells.png\n";
}

# ============================================================
# Demo 2: コンパス系極座標 — サッカード方向分布(Rose diagram)
#   眼球運動研究で典型的な「サッカードがどの方向に多く生じたか」
#   をRose diagramで表現する。北(上)=0度、時計回りが標準的な
#   方位角の流儀に合わせる。
# ============================================================
{
    my $n_dir = 12;   # 30度刻み12方向
    my $theta = sequence($n_dir) / $n_dir * 2 * $PI;

    # 右方向(0度=東)にやや偏った合成カウントデータ
    # (von Mises分布から生成した模擬データ)
    my $counts = pdl(
        45, 38, 22, 15, 10, 8,
        12, 18, 28, 35, 42, 50,
    );

    my $fig = figure(width=>600, height=>600);
    my $ax  = $fig->add_subplot(1,1,1, projection=>'polar');

    # コンパス系設定: 北(上)=0度、時計回り
    $ax->set_theta_zero_location('N');
    $ax->set_theta_direction(-1);

    $ax->bar($theta, $counts,
        color => 'crimson',
        alpha => 0.75,
        label => 'Saccade count',
    );
    $ax->set_rmax(55);
    $ax->set_rticks([10, 20, 30, 40, 50]);
    $ax->set_title('Saccade Direction Distribution (Rose Diagram)');
    $fig->tight_layout();
    $fig->save('/tmp/polar_tuning_demo_rose.png');
    print "Saved: /tmp/polar_tuning_demo_rose.png\n";
}

# ============================================================
# Demo 3: 位相分布 — EEG/LFP位相同期解析
#   各イベント(スパイクやERPピーク等)が生じたときのオシレーション
#   位相をプロットする典型例。円周上の散布図 + 平均方向(矢印相当)
#   を重ねて視覚的に位相クラスタリングを示す。
# ============================================================
{
    # 模擬位相データ: 平均位相 π/4 付近にクラスタした100イベント分
    my $n_events = 150;
    my $mean_phase = $PI / 4;
    my $concentration = 2.5;   # von Mises の kappa相当（円形分布の集中度）

    # Box-Muller的な近似でvon Mises風の位相サンプルを生成
    # (簡易的に正規分布をラップして円周上に押し込む)
    srand(42);   # 再現性のため固定シード
    my @phases;
    for (1 .. $n_events) {
        my $u1 = rand(); my $u2 = rand();
        my $z = sqrt(-2*log($u1)) * cos(2*$PI*$u2);
        my $phase = $mean_phase + $z / sqrt($concentration);
        # -pi..pi に正規化
        $phase = $phase - 2*$PI*int(($phase+$PI)/(2*$PI));
        push @phases, $phase;
    }
    my $phase_pdl = pdl(@phases);
    my $r_pdl     = ones($n_events) * 0.85 + (random($n_events)-0.5)*0.1;

    my $fig = figure(width=>600, height=>600);
    my $ax  = $fig->add_subplot(1,1,1, projection=>'polar');

    $ax->scatter($phase_pdl, $r_pdl,
        color     => 'steelblue',
        s         => 10,
        alpha     => 0.5,
        fillstyle => 'none',
        label     => 'Event phase',
    );

    # 平均位相方向を太い線で重ねる(位相同期の代表値)
    my $mean_line_theta = pdl(0, $mean_phase);
    my $mean_line_r     = pdl(0, 1.0);
    $ax->plot($mean_line_theta, $mean_line_r,
        color => 'darkred', lw=>3, label=>'Mean phase');

    $ax->set_rmax(1.0);
    $ax->set_rticks([0.5, 1.0]);
    $ax->set_title('Phase Distribution at Event Onset (n=150)');
    $ax->legend();
    $fig->tight_layout();
    $fig->save('/tmp/polar_tuning_demo_phase.png');
    print "Saved: /tmp/polar_tuning_demo_phase.png\n";
}

# ============================================================
# Demo 4: 2x2グリッド — 複数電極/チャンネルのチューニング比較
#   論文Figureで典型的な「複数記録部位を並べて比較」のレイアウト。
# ============================================================
{
    my $n = 48;
    my $theta = sequence($n) / $n * 2 * $PI;

    my @channels = (
        { name=>'Ch1 (V1)',  pref=>0,        kappa=>5 },
        { name=>'Ch2 (V2)',  pref=>$PI/2,     kappa=>3 },
        { name=>'Ch3 (MT)',  pref=>$PI,       kappa=>2 },
        { name=>'Ch4 (V4)',  pref=>3*$PI/2,   kappa=>4 },
    );

    my $fig = figure(width=>900, height=>900);
    $fig->suptitle('Multi-Channel Direction Tuning Comparison', fontsize=>14);

    for my $i (0 .. 3) {
        my $ax = $fig->add_subplot(2, 2, $i+1, projection=>'polar');
        my $ch = $channels[$i];
        my $r  = von_mises_tuning($theta, $ch->{pref}, $ch->{kappa});
        $ax->plot($theta, $r, color=>'teal', lw=>2);
        $ax->fill($theta, $r, color=>'teal', alpha=>0.25);
        $ax->set_rmax(1.1);
        $ax->set_title($ch->{name});
    }

    $fig->tight_layout();
    $fig->save('/tmp/polar_tuning_demo_grid.png');
    print "Saved: /tmp/polar_tuning_demo_grid.png\n";
}

print "\nDone. Open with: open /tmp/polar_tuning_demo_*.png\n";
