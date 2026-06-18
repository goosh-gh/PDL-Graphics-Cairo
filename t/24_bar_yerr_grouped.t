use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

# ------------------------------------------------------------------
# yerr (対称) がキューに正しく保存されること
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->bar(pdl(1,2,3), pdl(10,20,15), yerr=>2);
    my $cmd = $ax->_queue->[-1];
    is $cmd->{type}, 'bar', 'bar queued';
    ok defined($cmd->{yerr_lo}), 'yerr_lo is defined for symmetric yerr';
    ok defined($cmd->{yerr_hi}), 'yerr_hi is defined for symmetric yerr';
    is $cmd->{yerr_lo}->at(0), 2, 'symmetric yerr: yerr_lo = 2';
    is $cmd->{yerr_hi}->at(0), 2, 'symmetric yerr: yerr_hi = 2';
}

# ------------------------------------------------------------------
# yerr (配列、各バー個別の値) がキューに正しく保存されること
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->bar(pdl(1,2,3), pdl(10,20,15), yerr=>[1,2,3]);
    my $cmd = $ax->_queue->[-1];
    is $cmd->{yerr_lo}->at(1), 2, 'per-bar yerr: yerr_lo[1] = 2';
    is $cmd->{yerr_hi}->at(2), 3, 'per-bar yerr: yerr_hi[2] = 3';
}

# ------------------------------------------------------------------
# yerr_low / yerr_high (非対称) がキューに正しく保存されること
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->bar(pdl(1,2,3), pdl(10,20,15), yerr_low=>[1,2,3], yerr_high=>[4,5,6]);
    my $cmd = $ax->_queue->[-1];
    is $cmd->{yerr_lo}->at(0), 1, 'asymmetric: yerr_lo[0] = 1';
    is $cmd->{yerr_hi}->at(0), 4, 'asymmetric: yerr_hi[0] = 4';
    is $cmd->{yerr_lo}->at(2), 3, 'asymmetric: yerr_lo[2] = 3';
    is $cmd->{yerr_hi}->at(2), 6, 'asymmetric: yerr_hi[2] = 6';
}

# ------------------------------------------------------------------
# yerr未指定時は従来通りyerr_lo/yerr_hiがundefであること(後方互換性)
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->bar(pdl(1,2,3), pdl(10,20,15));
    my $cmd = $ax->_queue->[-1];
    ok !defined($cmd->{yerr_lo}), 'no yerr: yerr_lo is undef';
    ok !defined($cmd->{yerr_hi}), 'no yerr: yerr_hi is undef';
}

# ------------------------------------------------------------------
# yerrありでもPNG描画がクラッシュしないこと(対称・非対称・配列の3パターン)
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->bar(pdl(1,2,3), pdl(10,20,15), yerr=>2, color=>'steelblue');
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'bar with symmetric yerr renders without crashing' or diag "error: $@";
}

{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->bar(pdl(1,2,3), pdl(10,20,15), yerr=>[1,2,3], color=>'tomato');
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'bar with per-bar yerr array renders without crashing' or diag "error: $@";
}

{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->bar(pdl(1,2,3), pdl(10,20,15), yerr_low=>[1,2,3], yerr_high=>[4,5,6]);
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'bar with asymmetric yerr_low/yerr_high renders without crashing' or diag "error: $@";
}

# ------------------------------------------------------------------
# グループ化棒グラフ: bar()を複数回呼んでxをずらす(matplotlib流)。
# 専用APIは新設せず、既存bar()のwidth/x調整だけで実現できることを
# 確認する回帰テスト。色は_next_color()により自動的に系列ごとに
# 変わることも確認する。
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    my $categories = pdl(0,1,2);    # グループ位置(中心)
    my $bw = 0.35;                  # 1系列分の幅

    $ax->bar($categories - $bw/2, pdl(10,15,12), width=>$bw, label=>'condition A');
    $ax->bar($categories + $bw/2, pdl(12,18,9),  width=>$bw, label=>'condition B');

    is scalar(@{ $ax->_queue }), 2, 'two bar() calls queue two bar commands';

    my $color_a = $ax->_queue->[0]{color};
    my $color_b = $ax->_queue->[1]{color};
    isnt join(',', @$color_a), join(',', @$color_b),
        'grouped bar(): consecutive bar() calls get different auto colors';

    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'grouped bar chart (two bar() calls with shifted x) renders without crashing'
        or diag "error: $@";
}

# ------------------------------------------------------------------
# グループ化 + yerr の組み合わせでもクラッシュしないこと
# (ERP解析で条件A/B各々の平均±SDを並べて表示する想定)
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    my $categories = pdl(0,1,2);
    my $bw = 0.35;

    $ax->bar($categories - $bw/2, pdl(10,15,12), width=>$bw,
        yerr=>[1,1.5,1.2], label=>'condition A', color=>'steelblue');
    $ax->bar($categories + $bw/2, pdl(12,18,9), width=>$bw,
        yerr=>[1.1,2,0.9], label=>'condition B', color=>'tomato');

    $ax->legend if $ax->can('legend');
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'grouped bar chart with yerr on both series renders without crashing'
        or diag "error: $@";
}

done_testing;
