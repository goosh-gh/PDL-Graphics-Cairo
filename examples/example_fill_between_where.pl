#!/usr/bin/env perl
# example_fill_between_where.pl
#   -- PDL::Graphics::Cairo fill_between(where=>...) デモ
#
# matplotlib の ax.fill_between(x, y1, y2, where=...) に相当する
# 条件付き塗りつぶし。2系列の交差区間や、統計的に有意な区間だけを
# 強調表示する用途で使う。
#
# 実行: perl -I./lib examples/example_fill_between_where.pl

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

# ============================================================
# Demo 1: 2系列の大小関係で塗り分け (sin vs cos の交差区間)
#   matplotlibの定番デモ: where=>(y1>y2) で片方が上回る区間だけ
#   色付けする。
# ============================================================
{
    my $x  = sequence(300) / 30;          # 0 ~ 10
    my $y1 = sin($x);
    my $y2 = cos($x);

    my ($fig, $ax) = subplots(width=>700, height=>420);
    $ax->plot($x, $y1, color=>'steelblue', lw=>2, label=>'sin(x)');
    $ax->plot($x, $y2, color=>'darkorange', lw=>2, label=>'cos(x)');

    # sin(x) > cos(x) の区間を青で、逆を橙で塗り分ける
    $ax->fill_between($x, $y1, $y2,
        where => ($y1 > $y2),
        color => 'steelblue',
        alpha => 0.25,
        label => 'sin(x) > cos(x)',
    );
    $ax->fill_between($x, $y1, $y2,
        where => ($y1 <= $y2),
        color => 'darkorange',
        alpha => 0.25,
        label => 'cos(x) ≥ sin(x)',
    );

    $ax->set_title('fill_between(where=>): sin(x) vs cos(x)');
    $ax->set_xlabel('x'); $ax->set_ylabel('y');
    $ax->legend();
    $fig->tight_layout();
    $fig->save('/tmp/fbw_demo_1_sincos.png');
    print "Saved: /tmp/fbw_demo_1_sincos.png\n";
}

# ============================================================
# Demo 2: 神経科学的な使用例 — ERP波形の有意差区間を強調表示
#   2条件(target/standard)のERP波形を重ねて描き、片方の振幅が
#   閾値以上だった区間だけをハイライトする。論文Figureで頻出する
#   「統計的に有意な時間窓を網掛けする」表現に相当。
# ============================================================
{
    my $t = sequence(500) / 500 * 2 - 0.5;   # -0.5s ~ 1.5s
    my $erp_target   = exp(-(($t-0.3)**2)/0.02) * 8 - exp(-(($t-0.1)**2)/0.005)*3;
    my $erp_standard = exp(-(($t-0.3)**2)/0.04) * 2 - exp(-(($t-0.1)**2)/0.005)*3;
    my $diff_wave    = $erp_target - $erp_standard;

    # 差分波形がしきい値(2.0 uV)を超える区間だけを「有意差区間」と
    # みなして網掛けする（実データでは統計検定の結果を使う）。
    my $sig_mask = ($diff_wave > 2.0);

    my ($fig, $ax) = subplots(width=>700, height=>450);
    $ax->plot($t, $erp_target,   color=>'crimson',   lw=>2, label=>'Target');
    $ax->plot($t, $erp_standard, color=>'steelblue', lw=>2, label=>'Standard');
    $ax->axvline(0, color=>'gray', ls=>'dashed', lw=>1, alpha=>0.6);

    $ax->fill_between($t, $erp_target, $erp_standard,
        where => $sig_mask,
        color => 'gold',
        alpha => 0.35,
        label => 'Significant difference (diff > 2µV)',
    );

    $ax->set_title('ERP waveforms with significant-difference window highlighted');
    $ax->set_xlabel('Time relative to stimulus onset (s)');
    $ax->set_ylabel('Amplitude (µV)');
    $ax->legend();
    $fig->tight_layout();
    $fig->save('/tmp/fbw_demo_2_erp_significance.png');
    print "Saved: /tmp/fbw_demo_2_erp_significance.png\n";
}

# ============================================================
# Demo 3: 単一系列のしきい値超え区間の塗り分け (異常検知的な用途)
#   y2を定数(しきい値ライン)にして、信号がそれを超える区間だけ
#   塗りつぶす。閾値検出・異常区間の可視化に使う典型パターン。
# ============================================================
{
    my $x = sequence(400) / 40;
    my $signal = sin($x) * 1.5 + sin($x*3.7) * 0.5;
    my $threshold = ones(400) * 1.0;   # しきい値の定数線(xと同じ長さ)
    my $mask = ($signal > 1.0);

    my ($fig, $ax) = subplots(width=>700, height=>420);
    $ax->plot($x, $signal, color=>'darkgreen', lw=>1.5, label=>'Signal');
    $ax->axhline(1.0, color=>'red', ls=>'dashed', lw=>1.2, label=>'Threshold');

    $ax->fill_between($x, $signal, $threshold,
        where => $mask,
        color => 'red',
        alpha => 0.3,
        label => 'Above threshold',
    );

    $ax->set_title('Threshold-crossing region highlight');
    $ax->set_xlabel('Time'); $ax->set_ylabel('Signal amplitude');
    $ax->legend();
    $fig->tight_layout();
    $fig->save('/tmp/fbw_demo_3_threshold.png');
    print "Saved: /tmp/fbw_demo_3_threshold.png\n";
}

print "\nDone. Open with: open /tmp/fbw_demo_*.png\n";
