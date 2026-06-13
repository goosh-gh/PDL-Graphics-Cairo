#!/usr/bin/env perl
# example_colormap.pl — PDL::Graphics::Cairo ListedColormap / Normalize デモ
# 実行: perl -I./lib examples/example_colormap.pl

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots
                             ListedColormap Normalize LogNorm
                             BoundaryNorm TwoSlopeNorm);

my $PI = 3.14159265358979;

# ============================================================
# Demo 1: ListedColormap — カテゴリカルデータの可視化
# 各クラスを対応する色で個別にplot
# ============================================================
{
    my $n_per_class = 80;
    my @centers = ([0,0], [3,1], [1,4], [-2,3], [2,-2]);
    my @class_colors = ('steelblue', 'tomato', 'seagreen', 'darkorange', 'purple');
    my @class_names  = ('Class 0',  'Class 1', 'Class 2',  'Class 3',   'Class 4');

    my ($fig, $ax) = subplots(1, 1, width=>600, height=>500);

    for my $cls (0..4) {
        my $cx = $centers[$cls][0];
        my $cy = $centers[$cls][1];
        my $x  = pdl(map { $cx + grandom(1)->at(0) * 0.8 } 1..$n_per_class);
        my $y  = pdl(map { $cy + grandom(1)->at(0) * 0.8 } 1..$n_per_class);
        $ax->scatter($x, $y,
            s      => 20,
            color  => $class_colors[$cls],
            alpha  => 0.8,
            label  => $class_names[$cls],
        );
    }

    $ax->legend;
    $ax->xlabel('Feature 1');
    $ax->ylabel('Feature 2');
    $ax->title('ListedColormap colors: 5-class classification');
    $fig->tight_layout;
    $fig->save('/tmp/colormap_demo_listed.png');
    print "Saved: /tmp/colormap_demo_listed.png\n";
}

# ============================================================
# Demo 2: TwoSlopeNorm — 発散カラーマップ（異常検知）
# ============================================================
{
    my $n  = 200;
    my $t  = sequence($n) / ($n / (2 * $PI * 3));
    my $sig = sin($t) * 5 + grandom($n) * 2;
    $sig->slice("50:60")   += 12;
    $sig->slice("140:148") -= 10;

    my $norm = TwoSlopeNorm(vmin=>-15, vcenter=>0, vmax=>15);
    my @cnorm = map { $norm->call($sig->at($_)) } 0..$n-1;

    my ($fig, @ax) = subplots(2, 1, width=>700, height=>500);

    $ax[0]->line(sequence($n), $sig, color=>'gray', lw=>1.5);
    $ax[0]->axhline(0,   color=>'black', lw=>1,   linestyle=>'dashed');
    $ax[0]->axhline(10,  color=>'red',   lw=>0.8, linestyle=>'dotted');
    $ax[0]->axhline(-10, color=>'blue',  lw=>0.8, linestyle=>'dotted');
    $ax[0]->ylabel('Deviation');
    $ax[0]->title('Signal with anomalies (±10 threshold)');
    $ax[0]->grid(1);

    $ax[1]->scatter(sequence($n), $sig,
        c    => pdl(@cnorm),
        cmap => 'RdBu',
        s    => 15,
    );
    $ax[1]->axhline(0, color=>'black', lw=>0.8);
    $ax[1]->xlabel('Time step');
    $ax[1]->ylabel('Deviation');
    $ax[1]->title('Colored by TwoSlopeNorm (blue=negative, red=positive)');

    $fig->suptitle('TwoSlopeNorm: Diverging Colormap for Anomaly Detection',
                   fontsize=>12);
    $fig->tight_layout;
    $fig->save('/tmp/colormap_demo_twoslope.png');
    print "Saved: /tmp/colormap_demo_twoslope.png\n";
}

# ============================================================
# Demo 3: LogNorm — 対数スケール正規化
# ============================================================
{
    my $x = sequence(50) + 1;
    my $y = sequence(50) + 1;
    my $z = ($x->slice(':,*1') * $y->slice('*1,:'));

    my $norm  = LogNorm(vmin=>1, vmax=>2500);
    my @cnorm = map { $norm->call($z->at($_ % 50, int($_ / 50))) }
                0..(50*50-1);
    my $z_norm = pdl(@cnorm)->reshape(50, 50);

    my ($fig, @ax) = subplots(1, 2, width=>900, height=>420);

    $ax[0]->imshow($z, cmap=>'viridis', origin=>'lower');
    $ax[0]->title('Linear scale (low values invisible)');
    $ax[0]->xlabel('j'); $ax[0]->ylabel('i');

    $ax[1]->imshow($z_norm, cmap=>'viridis', origin=>'lower');
    $ax[1]->title('LogNorm applied (vmin=1, vmax=2500)');
    $ax[1]->xlabel('j'); $ax[1]->ylabel('i');

    $fig->suptitle('LogNorm: Visualizing z = i × j', fontsize=>13);
    $fig->tight_layout;
    $fig->save('/tmp/colormap_demo_lognorm.png');
    print "Saved: /tmp/colormap_demo_lognorm.png\n";
}

# ============================================================
# Demo 4: BoundaryNorm + ListedColormap — 離散ゾーン
# ============================================================
{
    my $n = 300;
    my $x = random($n) * 10;
    my $y = random($n) * 10;
    my $v = $x + $y;  # 0..20

    my $norm = BoundaryNorm(boundaries=>[0, 3, 7, 12, 17, 20]);
    my @cnorm = map { $norm->call($v->at($_)) } 0..$n-1;

    # 5境界ゾーンに対応する5色
    my $cmap = ListedColormap([
        '#2166ac',  # 青 (0-3: 低)
        '#74add1',  # 薄青 (3-7: 中低)
        '#fee090',  # 黄 (7-12: 中)
        '#f46d43',  # オレンジ (12-17: 高)
        '#a50026',  # 赤 (17-20: 非常に高)
    ]);

    my ($fig, $ax) = subplots(1, 1, width=>600, height=>500);
    $ax->scatter($x, $y,
        c    => pdl(@cnorm),
        cmap => $cmap,
        s    => 30,
        alpha => 0.85,
    );
    $ax->xlabel('X'); $ax->ylabel('Y');
    $ax->title("BoundaryNorm + ListedColormap\n(zones: 0-3, 3-7, 7-12, 12-17, 17-20)");
    $fig->tight_layout;
    $fig->save('/tmp/colormap_demo_boundary.png');
    print "Saved: /tmp/colormap_demo_boundary.png\n";
}

print "\nDone. Open with: open /tmp/colormap_demo_*.png\n";
