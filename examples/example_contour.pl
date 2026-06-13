#!/usr/bin/env perl
# example_contour.pl — PDL::Graphics::Cairo contour / contourf デモ
# 実行: perl -I./lib examples/example_contour.pl

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots subplot_mosaic ListedColormap);

my $PI = 3.14159265358979;

sub make_grid {
    my ($xv, $yv) = @_;
    my $x = $xv->slice(':,*1') * ones(1, $yv->nelem);
    my $y = ones($xv->nelem, 1) * $yv->slice('*1,:');
    return ($x, $y);
}

# グリッド生成ユーティリティ
# ============================================================
# Demo 1: contourf + contour overlay — sin(x)*cos(y)
#   科学論文スタイルの等高線図
# ============================================================
{
    my $n  = 120;
    my $xv = sequence($n) / ($n-1) * 2 * $PI;
    my $yv = sequence($n) / ($n-1) * 2 * $PI;
    my ($x, $y) = make_grid($xv, $yv);
    my $z = sin($x) * cos($y);

    my ($fig, $ax) = subplots(1, 1, width=>600, height=>520);

    # 塗りつぶし等高線
    $ax->contourf($xv, $yv, $z,
        levels => 16,
        cmap   => 'RdBu',
        vmin   => -1, vmax => 1,
    );

    # 等高線（黒）
    $ax->contour($xv, $yv, $z,
        levels     => 12,
        colors     => 'black',
        linewidths => 0.6,
        alpha      => 0.6,
    );
    $ax->set_aspect('equal');
    $ax->xlabel('X'); $ax->ylabel('Y');
    $ax->title('sin(x)·cos(y): contourf + contour overlay');
    $ax->tick_params(direction=>'in', top=>1, right=>1);
    $fig->tight_layout;
    $fig->save('/tmp/contour_demo_sincos.png');
    print "Saved: /tmp/contour_demo_sincos.png\n";
}

# ============================================================
# Demo 2: 4パネル — 異なる関数の等高線
# ============================================================
{
    my $n  = 60;
    my $xv = sequence($n) / ($n-1) * 4 - 2;
    my $yv = sequence($n) / ($n-1) * 4 - 2;
    my ($x, $y) = make_grid($xv, $yv);

    my ($fig, %ax) = subplot_mosaic(
        "AB\nCD",
        width  => 800,
        height => 700,
        hspace => 0.45,
        wspace => 0.35,
        top    => 0.88,
    );

    # A: ガウス関数
    my $zA = exp(-($x**2 + $y**2));
    $ax{A}->contourf($xv, $yv, $zA, levels=>10, cmap=>'viridis');
    $ax{A}->contour( $xv, $yv, $zA, levels=>8,  colors=>'white',
                     linewidths=>0.8, alpha=>0.7);
    $ax{A}->set_aspect('equal');
    $ax{A}->title('Gaussian: exp(-(x²+y²))');
    $ax{A}->tick_params(labelsize=>7, direction=>'in');

    # B: 鞍点関数
    my $zB = $x**2 - $y**2;
    my @blues  = map { [0, $_, 1-$_*0.5] } map { $_/9 } 0..4;
    my @reds   = map { [1-$_*0.5, $_, 0] } map { $_/9 } 5..9;
    my $cmap_div = ListedColormap([
        '#053061','#2166ac','#4393c3','#92c5de','#d1e5f0',
        '#fddbc7','#f4a582','#d6604d','#b2182b','#67001f',
    ]);
    $ax{B}->contourf($xv, $yv, $zB, levels=>10, cmap=>$cmap_div,
                     vmin=>-4, vmax=>4);
    $ax{B}->contour( $xv, $yv, $zB,
        levels     => [map { -3+$_*0.75 } 0..8],
        colors     => 'black',
        linewidths => 0.5,
    );
    $ax{B}->contour($xv, $yv, $zB,
        levels => [0], colors=>'black', linewidths=>2.0);
    $ax{B}->set_aspect('equal');
    $ax{B}->title('Saddle: x²−y²  (zero contour bold)');
    $ax{B}->tick_params(labelsize=>7, direction=>'in');

    # C: ロゼット関数
    my $r  = sqrt($x**2 + $y**2) + 1e-10;
    my $zC = sin(3 * atan2($y, $x)) * exp(-$r * 0.5);
    $ax{C}->contourf($xv, $yv, $zC, levels=>12, cmap=>'plasma',
                     vmin=>-0.8, vmax=>0.8);
    $ax{C}->contour( $xv, $yv, $zC, levels=>8,
                     colors=>'white', linewidths=>0.6, alpha=>0.5);
    $ax{C}->set_aspect('equal');
    $ax{C}->title('Rosette: sin(3θ)·exp(−r/2)');
    $ax{C}->tick_params(labelsize=>7, direction=>'in');

    # D: 複数周波数の重ね合わせ
    my $zD = sin(2*$PI*$x/2) + 0.5*sin(2*$PI*$y/1.5)
           + 0.3*sin(2*$PI*($x+$y)/1.2);
    $ax{D}->contourf($xv, $yv, $zD, levels=>14, cmap=>'coolwarm',
                     vmin=>-1.8, vmax=>1.8);
    # 負の等高線を破線に
    my @lvls = map { -1.5 + $_*0.3 } 0..9;
    $ax{D}->contour($xv, $yv, $zD,
        levels     => \@lvls,
        colors     => [map { $_ < 0 ? 'navy' : 'darkred' } @lvls],
        linewidths => 0.8,
        linestyles => [map { $_ < 0 ? 'dashed' : 'solid' } @lvls],
    );
    $ax{D}->set_aspect('equal');
    $ax{D}->title('Wave superposition (neg=dashed)');
    $ax{D}->tick_params(labelsize=>7, direction=>'in');

    $fig->suptitle('Contour Gallery', fontsize=>14);
    $fig->tight_layout;
    $fig->save('/tmp/contour_demo_gallery.png');
    print "Saved: /tmp/contour_demo_gallery.png\n";
}

# ============================================================
# Demo 3: 地形図スタイル
# ============================================================
{
    my $n  = 100;
    my $xv = sequence($n) / ($n-1) * 10;
    my $yv = sequence($n) / ($n-1) * 10;
    my ($x, $y) = make_grid($xv, $yv);

    # 複数の山と谷
    my $z = 2.0 * exp(-(($x-3)**2 + ($y-3)**2)/2)
          + 1.5 * exp(-(($x-7)**2 + ($y-7)**2)/1.5)
          + 0.8 * exp(-(($x-2)**2 + ($y-7)**2)/3)
          - 0.5 * exp(-(($x-6)**2 + ($y-2)**2)/2)
          + 0;  # no noise

    # 地形カラーマップ（深緑→緑→黄→茶→白）
    my $topo_cmap = ListedColormap([
        '#1a3320','#2d5a27','#4a7c3f','#6da54e','#a8c97a',
        '#d4e6a0','#e8d89a','#c9a86c','#a07840','#7a5428',
        '#f0f0f0','#ffffff',
    ], name=>'topo');

    my ($fig, $ax) = subplots(1, 1, width=>650, height=>560);

    $ax->contourf($xv, $yv, $z,
        levels => 20,
        cmap   => $topo_cmap,
        vmin   => -0.5, vmax => 2.2,
    );

    # 主等高線（太）
    my @major_lvls = map { $_*0.5 } 0..4;
    $ax->contour($xv, $yv, $z,
        levels     => \@major_lvls,
        colors     => '#4a3000',
        linewidths => 1.2,
        alpha      => 0.8,
    );

    # 補助等高線（細）
    my @minor_lvls = map { $_*0.25 } 1..7;
    $ax->contour($xv, $yv, $z,
        levels     => \@minor_lvls,
        colors     => '#4a3000',
        linewidths => 0.3,
        alpha      => 0.35,
    );

    $ax->set_aspect('equal');
    $ax->xlabel('Easting (km)');
    $ax->ylabel('Northing (km)');
    $ax->title('Topographic Map Style');
    $ax->tick_params(direction=>'in', top=>1, right=>1, labelsize=>8);
    $fig->tight_layout;
    $fig->save('/tmp/contour_demo_topo.png');
    print "Saved: /tmp/contour_demo_topo.png\n";
}

print "\nDone. Open with: open /tmp/contour_demo_*.png\n";
