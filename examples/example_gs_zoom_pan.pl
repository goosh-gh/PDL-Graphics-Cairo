#!/usr/bin/env perl
# P:G:C09 段階B デモ — zoom/pan でデータ座標レベルの拡大縮小
#
# ピンチイン/アウト または Ctrl+スクロール で zoom
# zoom中に2本指ドラッグで pan
# ダブルクリックでリセット
#
# zoom_pan_redraw => 1 を指定すると:
#   - giza-server の zoom/pan 操作を検出して自動再描画
#   - render の $state に以下のキーが入る:
#       _zoom_xlim_lo/_zoom_xlim_hi  ... zoom後の x 表示範囲
#       _zoom_ylim_lo/_zoom_ylim_hi  ... zoom後の y 表示範囲
#       _zoom, _pan_x, _pan_y        ... zoom/pan の生の値
#   - render 側でこれを xlim/ylim に適用することで高解像度再描画
#   - zoom=1/pan=0にリセットされると _zoom_xlim* キーは消える

use strict; use warnings;
use PDL;
use PDL::Graphics::Cairo qw(subplots);
use PDL::Graphics::Cairo::Driver::GS;

# --- データ: 細かい構造を含む波形（zoom で見えてくる） ---
my $x = sequence(2000) / 200;          # 0..10、2000点
my $y = sin($x * 3) * exp(-$x/5)      # 減衰正弦
      + 0.15 * sin($x * 37)           # 高周波ノイズ（zoom で見える）
      + 0.05 * sin($x * 120);         # さらに高周波

# --- render コールバック ---
my $render = sub {
    my ($state, $w, $h) = @_;
    my ($fig, $ax) = subplots(1, 1, width => $w, height => $h);

    # zoom_pan_redraw が xlim/ylim を state に書いてくれる
    my $xlo = $state->{_zoom_xlim_lo} // 0;
    my $xhi = $state->{_zoom_xlim_hi} // 10;
    my $ylo = $state->{_zoom_ylim_lo} // -1.3;
    my $yhi = $state->{_zoom_ylim_hi} //  1.3;

    $ax->xlim($xlo, $xhi);
    $ax->ylim($ylo, $yhi);

    # 表示範囲内のデータだけ描画（高速化）
    my $margin = ($xhi - $xlo) * 0.05;
    my $mask   = ($x >= $xlo - $margin) & ($x <= $xhi + $margin);
    my $xv = $x->where($mask);
    my $yv = $y->where($mask);

    $ax->line($xv, $yv, color => 'steelblue', lw => 1.5);
    $ax->set_xlabel('x');
    $ax->set_ylabel('y');

    # zoom状態の表示
    if (defined $state->{_zoom} && $state->{_zoom} > 1.01) {
        my $zmsg = sprintf("zoom=%.1fx  x=[%.3f, %.3f]", $state->{_zoom}, $xlo, $xhi);
        $ax->text($xlo + ($xhi-$xlo)*0.02, $yhi - ($yhi-$ylo)*0.05,
            $zmsg, ha=>'left', va=>'top', fontsize=>10, color=>'darkgreen');
    } else {
        $ax->set_title('ピンチ/Ctrl+スクロールでzoom、2本指ドラッグでpan、ダブルクリックでリセット');
    }

    $fig->tight_layout;
    return $fig;
};

# --- インタラクティブ起動 ---
my $drv = PDL::Graphics::Cairo::Driver::GS->new(
    width  => 900,
    height => 500,
    title  => 'P:G:C09 zoom/pan',
);

print "ピンチイン/アウト または Ctrl+スクロールでzoom\n";
print "zoom中に2本指ドラッグでpan\n";
print "ダブルクリックでリセット\n";

$drv->show_interactive(
    render          => $render,
    zoom_pan_redraw => 1,
    cursor_overlay  => 1,
    on_zoom => sub {
        my ($zoom, $px, $py) = @_;
        printf "\rzoom=%.2f pan=(%.3f,%.3f)   ", $zoom, $px, $py;
    },
);
