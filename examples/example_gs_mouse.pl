#!/usr/bin/env perl
# giza-server14 マウスイベントのデモ
# zoom/pan はビューア側で完結（自動）。ここでは pick / cursor の
# コールバックでデータ座標を取り出す例を示す。
use strict; use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);
use PDL::Graphics::Cairo::Driver::GS;

my $x = sequence(50) / 5;          # 0..10
my $y = sin($x);

# 画像内分率 (fx,fy) → データ座標への変換は呼び出し側の責務。
# ここでは axes の描画範囲を固定して逆変換する簡単な例。
my ($XMIN, $XMAX) = (0, 10);
my ($YMIN, $YMAX) = (-1.2, 1.2);

# 図のうちプロット領域が画像のどこを占めるかはマージン依存。
# 厳密には Figure 側がマージン情報を持つが、ここでは概算で示す。
my $frac_to_data = sub {
    my ($fx, $fy) = @_;
    my $dx = $XMIN + $fx * ($XMAX - $XMIN);
    my $dy = $YMAX - $fy * ($YMAX - $YMIN);   # fy は上→下、データは下→上
    return ($dx, $dy);
};

my $render = sub {
    my ($state, $w, $h) = @_;
    my ($fig, $ax) = subplots(1, 1, width => $w, height => $h);
    $ax->line($x, $y, color => 'steelblue', lw => 2);
    $ax->set_xlim($XMIN, $XMAX);
    $ax->set_ylim($YMIN, $YMAX);
    $ax->set_title("click a point (pick), move mouse (cursor)");
    return $fig;
};

my $drv = PDL::Graphics::Cairo::Driver::GS->new(width => 800, height => 500);

$drv->show_interactive(
    render    => $render,
    on_cursor => sub {
        my ($fx, $fy) = @_;
        my ($dx, $dy) = $frac_to_data->($fx, $fy);
        printf "\rcursor: x=%6.3f y=%6.3f   ", $dx, $dy;
    },
    on_pick   => sub {
        my ($fx, $fy, $btn) = @_;
        my ($dx, $dy) = $frac_to_data->($fx, $fy);
        # 最近傍データ点を探す
        my $i = (($x - $dx)**2 + ($y - $dy)**2)->minimum_ind;
        printf "\nPICK btn=%d → nearest point #%d: (%.3f, %.3f)\n",
            $btn, $i, $x->at($i), $y->at($i);
    },
    on_zoom   => sub {
        my ($zoom, $px, $py) = @_;
        printf "\nzoom=%.2f pan=(%.2f,%.2f)\n", $zoom, $px, $py;
    },
);
