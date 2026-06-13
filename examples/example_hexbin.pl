#!/usr/bin/env perl
# example_hexbin.pl — PDL::Graphics::Cairo hexbin デモ
# 実行: perl -I./lib examples/example_hexbin.pl
# 出力: /tmp/hexbin_demo_*.png

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots ListedColormap);

my $PI = 3.14159265358979;

# ============================================================
# Demo 1: 基本的な2Dガウス密度
# ============================================================
{
    my $n = 2000;

    # 2つのガウスクラスター
    my $x1 = grandom($n) * 1.0 + 2;
    my $y1 = grandom($n) * 1.5 + 2;
    my $x2 = grandom(int($n/2)) * 0.8 - 1;
    my $y2 = grandom(int($n/2)) * 0.8 + 4;

    my $x = $x1->append($x2);
    my $y = $y1->append($y2);

    my ($fig, $ax) = subplots(1, 1, width=>600, height=>500);
    $ax->hexbin($x, $y,
        gridsize => 25,
        cmap     => 'viridis',
        mincnt   => 1,
    );
    $ax->xlabel('X');
    $ax->ylabel('Y');
    $ax->title('Hexbin: Two Gaussian clusters (n=3000)');
    $fig->tight_layout;
    $fig->save('/tmp/hexbin_demo_gaussian.png');
    print "Saved: /tmp/hexbin_demo_gaussian.png\n";
}

# ============================================================
# Demo 2: 相関データ + hexbin vs scatter 比較
# ============================================================
{
    my $n = 5000;
    my $x = grandom($n);
    my $y = $x * 0.8 + grandom($n) * 0.6;

    my ($fig, @ax) = subplots(1, 2, width=>900, height=>420);

    # 左: scatter（点が多すぎて重なる）
    $ax[0]->scatter($x, $y, s=>2, alpha=>0.2, color=>'steelblue');
    $ax[0]->xlabel('X'); $ax[0]->ylabel('Y');
    $ax[0]->title('Scatter (n=5000, overplotted)');

    # 右: hexbin（密度が明確）
    $ax[1]->hexbin($x, $y,
        gridsize => 30,
        cmap     => 'plasma',
        mincnt   => 1,
    );
    $ax[1]->xlabel('X'); $ax[1]->ylabel('Y');
    $ax[1]->title('Hexbin (density visible)');

    $fig->suptitle('Scatter vs Hexbin: Correlated Data (n=5000)', fontsize=>13);
    $fig->tight_layout;
    $fig->save('/tmp/hexbin_demo_comparison.png');
    print "Saved: /tmp/hexbin_demo_comparison.png\n";
}

# ============================================================
# Demo 3: カスタムカラーマップ + mincnt でスパース除去
# ============================================================
{
    my $n = 1500;

    # リング状分布
    my $theta = random($n) * 2 * $PI;
    my $r     = random($n) * 0.5 + 1.5;
    my $x     = $r * cos($theta) + grandom($n) * 0.2;
    my $y     = $r * sin($theta) + grandom($n) * 0.2;

    # 中心クラスター追加
    $x = $x->append(grandom(300) * 0.4);
    $y = $y->append(grandom(300) * 0.4);

    # カスタムカラーマップ: 黒→深紫→赤→オレンジ→白
    my $cmap = ListedColormap([
        '#000000', '#1a0033', '#330066', '#660033',
        '#990000', '#cc3300', '#ff6600', '#ff9900',
        '#ffcc00', '#ffffff',
    ], name=>'fire');

    my ($fig, $ax) = subplots(1, 1, width=>600, height=>540);
    $ax->hexbin($x, $y,
        gridsize => 20,
        cmap     => $cmap,
        mincnt   => 2,    # 2点未満のビンは非表示
        alpha    => 0.9,
    );
    $ax->set_aspect('equal');
    $ax->xlabel('X'); $ax->ylabel('Y');
    $ax->title("Ring + Center cluster\n(custom 'fire' cmap, mincnt=2)");
    $fig->tight_layout;
    $fig->save('/tmp/hexbin_demo_ring.png');
    print "Saved: /tmp/hexbin_demo_ring.png\n";
}

# ============================================================
# Demo 4: 大規模データ（n=20000）パフォーマンステスト
# ============================================================
{
    my $n = 20000;

    # 複数のガウスブレンド
    my @xs = map { grandom(int($n/4)) * 1.2 + $_ } (-3, 0, 3, 0);
    my @ys = map { grandom(int($n/4)) * 1.2 + $_ } (0, 3, 0, -3);
    my $x = $xs[0]->append($xs[1])->append($xs[2])->append($xs[3]);
    my $y = $ys[0]->append($ys[1])->append($ys[2])->append($ys[3]);

    my ($fig, $ax) = subplots(1, 1, width=>600, height=>520);

    my $t0 = time();
    $ax->hexbin($x, $y,
        gridsize => 35,
        cmap     => 'inferno',
        mincnt   => 3,
    );
    $ax->xlabel('X'); $ax->ylabel('Y');
    $ax->title("4-cluster mixture (n=20000, gridsize=35)");
    $fig->tight_layout;
    $fig->save('/tmp/hexbin_demo_large.png');
    my $dt = time() - $t0;
    print "Saved: /tmp/hexbin_demo_large.png (${dt}s)\n";
}

print "\nDone. Open with: open /tmp/hexbin_demo_*.png\n";
