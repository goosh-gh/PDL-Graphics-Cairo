#!/usr/bin/env perl
# =============================================================
# example_stats.pl  —  PDL::Graphics::Cairo + PDL::Stats デモ
#
# 実行方法（PDL-Graphics-Cairo/ ルートから）:
#   perl -I./lib examples/example_stats.pl
#
# 必要モジュール:
#   PDL::Stats  (cpan PDL::Stats  または  apt install libpdl-stats-perl)
#
# インタラクティブ表示（gnuplot 経由）:
#   Aquaterm / X11 / wxt を自動検出して表示します
#   ターミナルを明示指定: $fig->show(terminal => 'aqua')
#
# 動作:
#   gnuplot を使ってインタラクティブウィンドウに表示します
#   (Aquaterm / X11 / wxt を自動検出)
# =============================================================

use strict;
use warnings;
use PDL;
use PDL::Stats::Basic;
use PDL::Graphics::Cairo qw(figure subplots);

# 再現性のための乱数シード（PDL は srand を使う）
srand(42);

# =============================================================
# 共通テストデータ
# 4グループ × 各20サンプル（正規分布）
# =============================================================
my @GROUP_NAMES = qw(Control Drug-A Drug-B Drug-C);
my @GROUP_MEANS = (2.0,  3.5,  1.5,  4.2);
my @GROUP_STDS  = (0.4,  0.6,  0.3,  0.8);

my @groups = map {
    my ($mu, $sigma) = ($GROUP_MEANS[$_], $GROUP_STDS[$_]);
    $mu + grandom(20) * $sigma
} 0..3;

# =============================================================
# stats_01: エラーバー比較（SEM / SD / 95%CI）
# =============================================================
{
    my $fig = figure(width=>800, height=>520);
    my $ax  = $fig->axes();

    $ax->title("Error bar comparison: SEM / SD / 95% CI");
    $ax->xlabel("Group");
    $ax->ylabel("Value");
    $ax->set_grid(1);

    # SEM（平均の標準誤差）
    $ax->errorbar_stats(\@groups,
        type    => 'sem',
        color   => 'steelblue',
        capsize => 6,
        marker  => 'o',
        markersize => 6,
        label   => 'Mean \x{00B1} SEM',
    );

    # SD（標準偏差）— x をずらして重ねる
    $ax->errorbar_stats(\@groups,
        type    => 'sd',
        color   => 'coral',
        capsize => 6,
        marker  => 's',
        markersize => 6,
        x       => pdl(0.15, 1.15, 2.15, 3.15),
        label   => 'Mean \x{00B1} SD',
    );

    # 95% CI
    $ax->errorbar_stats(\@groups,
        type    => 'ci95',
        color   => 'seagreen',
        capsize => 6,
        marker  => '^',
        markersize => 6,
        x       => pdl(0.30, 1.30, 2.30, 3.30),
        label   => 'Mean \x{00B1} 95% CI',
    );

    $ax->xticks([0.15, 1.15, 2.15, 3.15], \@GROUP_NAMES);
    $ax->legend(loc => 'upper left');
    $ax->ylim(0, 6.5);

    $fig->show();
    print "stats_01: errorbar\n";
}

# =============================================================
# stats_02: 箱ひげ図
# =============================================================
{
    my $fig = figure(width=>800, height=>520);
    my $ax  = $fig->axes();

    $ax->title("Boxplot (Tukey method)");
    $ax->xlabel("Group");
    $ax->ylabel("Value");
    $ax->set_grid(1);

    $ax->boxplot(\@groups,
        showmeans  => 1,
        showfliers => 1,
        showcaps   => 1,
        width      => 0.55,
    );

    $ax->xticks([0,1,2,3], \@GROUP_NAMES);
    $ax->ylim(0, 6.5);

    # 参考線（コントロール群の中央値）
    my $ctrl_med = $groups[0]->median;
    $ax->axhline($ctrl_med,
        color => 'gray', lw => 1.0, ls => 'dashed');
    $ax->text(3.6, $ctrl_med + 0.08,
        "ctrl median", color=>'gray', fontsize=>9);

    $fig->show();
    print "stats_02: boxplot\n";
}

# =============================================================
# stats_03: バイオリンプロット
# =============================================================
{
    my $fig = figure(width=>800, height=>520);
    my $ax  = $fig->axes();

    $ax->title("Violin plot (Gaussian KDE)");
    $ax->xlabel("Group");
    $ax->ylabel("Value");
    $ax->set_grid(1);

    $ax->violinplot(\@groups,
        showmedians => 1,
        showmeans   => 1,
        showbox     => 1,
        width       => 0.7,
        points      => 150,
    );

    $ax->xticks([0,1,2,3], \@GROUP_NAMES);
    $ax->ylim(0, 6.5);

    $fig->show();
    print "stats_03: violin\n";
}

# =============================================================
# stats_04: 3種を横並び比較
# =============================================================
{
    my ($fig, $ax1, $ax2, $ax3) = subplots(1, 3, width=>1350, height=>500);
    $fig->set_suptitle(
        "PDL::Graphics::Cairo + PDL::Stats  —  Statistical Plots");

    for my $ax ($ax1, $ax2, $ax3) {
        $ax->set_grid(1);
        $ax->ylim(0, 6.5);
        $ax->xticks([0,1,2,3], \@GROUP_NAMES);
        $ax->ylabel("Value");
    }

    # errorbar_stats
    $ax1->title("errorbar_stats (SEM)");
    $ax1->errorbar_stats(\@groups,
        type => 'sem', color => 'steelblue',
        capsize => 6, marker => 'o', markersize => 7);

    # boxplot
    $ax2->title("boxplot");
    $ax2->boxplot(\@groups, showmeans=>1, width=>0.55);

    # violinplot
    $ax3->title("violinplot");
    $ax3->violinplot(\@groups, showmedians=>1, showbox=>1, width=>0.7);

    $fig->show();
    print "stats_04: combined\n";
}

# =============================================================
# stats_05: 実験データ想定の総合デモ
#   - 2グループ × 2条件（pre/post）
#   - 上段: 箱ひげ図、下段: バイオリン + エラーバー重ね
# =============================================================
{
    # 実験データ: 2グループ（患者/健常）× 測定2回（pre/post）
    my $pre_pat  = 65 + grandom(15) * 8;   # 患者 pre
    my $post_pat = 58 + grandom(15) * 9;   # 患者 post（改善）
    my $pre_ctrl = 62 + grandom(15) * 7;   # 健常 pre
    my $post_ctrl= 63 + grandom(15) * 7;   # 健常 post（変化なし）

    my ($fig, @axes) = subplots(2, 2, width=>1100, height=>900);
    my ($ax1, $ax2) = @{ $axes[0] };
    my ($ax3, $ax4) = @{ $axes[1] };
    $fig->set_suptitle("Clinical Study: Patient vs Control (Pre/Post)");

    # --- [1,1] 患者群 boxplot ---
    $ax1->title("Patient group");
    $ax1->boxplot([$pre_pat, $post_pat],
        showmeans => 1, width => 0.5);
    $ax1->xticks([0,1], [qw(Pre Post)]);
    $ax1->ylabel("Score");
    $ax1->set_grid(1);
    # 対応線（paired）
    for my $i (0..$pre_pat->nelem-1) {
        $ax1->line(pdl(0,1),
            pdl($pre_pat->at($i), $post_pat->at($i)),
            color=>'gray', lw=>0.5, alpha=>0.4);
    }

    # --- [1,2] 健常群 boxplot ---
    $ax2->title("Control group");
    $ax2->boxplot([$pre_ctrl, $post_ctrl],
        showmeans => 1, width => 0.5);
    $ax2->xticks([0,1], [qw(Pre Post)]);
    $ax2->ylabel("Score");
    $ax2->set_grid(1);
    for my $i (0..$pre_ctrl->nelem-1) {
        $ax2->line(pdl(0,1),
            pdl($pre_ctrl->at($i), $post_ctrl->at($i)),
            color=>'gray', lw=>0.5, alpha=>0.4);
    }

    # --- [2,1] violinplot 比較 ---
    $ax3->title("Pre-treatment comparison");
    $ax3->violinplot([$pre_pat, $pre_ctrl],
        showmedians=>1, showbox=>1, width=>0.6);
    $ax3->xticks([0,1], [qw(Patient Control)]);
    $ax3->ylabel("Pre score");
    $ax3->set_grid(1);

    # --- [2,2] errorbar_stats 比較（SEM）---
    $ax4->title("Mean \x{00B1} SEM: Pre vs Post");
    $ax4->errorbar_stats([$pre_pat, $post_pat],
        type=>'sem', color=>'coral',
        marker=>'o', markersize=>7, capsize=>6,
        label=>'Patient');
    $ax4->errorbar_stats([$pre_ctrl, $post_ctrl],
        type=>'sem', color=>'steelblue',
        marker=>'s', markersize=>7, capsize=>6,
        x=>pdl(0.15,1.15), label=>'Control');
    $ax4->xticks([0.075, 1.075], [qw(Pre Post)]);
    $ax4->legend(loc=>'upper right');
    $ax4->ylabel("Score");
    $ax4->set_grid(1);

    $fig->show();
    print "stats_05: realworld\n";
}


# =============================================================
# stats_06: Q-Q プロット
# =============================================================
{
    my $fig = figure(width=>800, height=>500);
    my $ax  = $fig->axes();

    $ax->title("Q-Q plot: Normal vs Skewed data");
    $ax->set_grid(1);

    my $normal = grandom(200);
    my $skewed = grandom(200)**2;

    $ax->qqplot($normal,
        color      => 'steelblue',
        label      => 'Normal data',
        line_color => 'steelblue',
    );
    $ax->qqplot($skewed,
        color      => 'coral',
        marker     => 's',
        label      => 'Skewed data',
        line_color => 'coral',
        line_label => 'normal ref',
    );
    $ax->legend(loc => 'upper left');

    $fig->show();
    print "stats_06: qqplot\n";
}

# =============================================================
# stats_07: ヒストグラム + KDE オーバーレイ
# =============================================================
{
    my ($fig, $ax1, $ax2) = subplots(1, 2, width=>1100, height=>480);
    $fig->set_suptitle("Histogram + KDE overlay");

    # 正規分布
    my $d1 = grandom(400) * 1.5 + 3;
    $ax1->title("Single distribution");
    $ax1->set_grid(1);
    $ax1->hist_kde($d1,
        bins      => 25,
        color     => 'steelblue',
        kde_color => 'red',
        label     => 'data',
        kde_label => 'KDE',
    );
    $ax1->legend(loc => 'upper right');
    $ax1->xlabel("Value"); $ax1->ylabel("Density");

    # 混合分布
    my $d2 = pdl(list(grandom(200) + 0),
                 list(grandom(200) + 4));
    $ax2->title("Bimodal distribution");
    $ax2->set_grid(1);
    $ax2->hist_kde($d2,
        bins      => 30,
        color     => 'coral',
        kde_color => 'darkred',
        label     => 'bimodal',
        kde_label => 'KDE',
    );
    $ax2->legend(loc => 'upper right');
    $ax2->xlabel("Value"); $ax2->ylabel("Density");

    $fig->show();
    print "stats_07: hist_kde\n";
}

print "\nAll stats demos complete.\n";

