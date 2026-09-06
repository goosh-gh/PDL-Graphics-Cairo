package PDL::Graphics::Cairo::Interactive::Scrub;

# =============================================================
# Interactive::Scrub — 純粋な数値ヘルパ（Cairo 非依存）
#
# GridScrub の対話ループから切り出した「マウス直近データ点の探索」
# と潜時クランプだけを担当する。giza-server もソケットも Figure も
# 触らないので、合成 piddle でヘッドレス検証できる（t/40_scrub.t）。
#
# 座標系: すべてデータ座標。距離は軸レンジで正規化してから比較する
# （x と y のスケール差で近さの判定が歪むのを防ぐ）。
# =============================================================

use strict;
use warnings;
use PDL::Lite;
use Exporter 'import';
our @EXPORT_OK = qw(nearest_on_line nearest_on_lines clamp);

# clamp($v, $lo, $hi) — $lo <= $hi を仮定
sub clamp {
    my ($v, $lo, $hi) = @_;
    return $lo if $v < $lo;
    return $hi if $v > $hi;
    return $v;
}

# nearest_on_line($x, $y, $xq, $yq, $xr, $yr)
#   $x,$y   … 1本のラインの標本（piddle または arrayref）
#   $xq,$yq … カーソルのデータ座標（$yq は undef 可 = x だけで最近傍）
#   $xr,$yr … 正規化用の軸レンジ（xmax-xmin など、0/undef は 1 に）
# 戻り値: ($idx, $x_at, $y_at, $dist2)   $dist2 は正規化二乗距離
#   標本が無ければ空リスト。
sub nearest_on_line {
    my ($x, $y, $xq, $yq, $xr, $yr) = @_;
    $x = PDL->topdl($x); $y = PDL->topdl($y);
    my $n = $x->nelem;
    return () if $n == 0;
    $xr = 1 if !defined $xr || $xr == 0;
    $yr = 1 if !defined $yr || $yr == 0;

    my $dx = ($x - $xq) / $xr;
    my $d2;
    if (defined $yq) {
        my $dy = ($y - $yq) / $yr;
        $d2 = $dx * $dx + $dy * $dy;
    } else {
        $d2 = $dx * $dx;                 # x だけスナップ（スクラバ的）
    }
    my $i = $d2->minimum_ind->sclr;
    return ($i, $x->at($i), $y->at($i), $d2->at($i));
}

# nearest_on_lines(\@lines, $xq, $yq, $xr, $yr)
#   @lines … [{ x => piddle, y => piddle }, ...]（Axes の _queue の line 要素）
# 全ラインを横断して最も近い1点を返す:
#   ($line_idx, $pt_idx, $x_at, $y_at)   何も無ければ空リスト。
sub nearest_on_lines {
    my ($lines, $xq, $yq, $xr, $yr) = @_;
    my ($best_li, $best_i, $best_x, $best_y, $best_d2);
    my $li = 0;
    for my $ln (@$lines) {
        my ($i, $xa, $ya, $d2) =
            nearest_on_line($ln->{x}, $ln->{y}, $xq, $yq, $xr, $yr);
        if (defined $i && (!defined $best_d2 || $d2 < $best_d2)) {
            ($best_li, $best_i, $best_x, $best_y, $best_d2) =
                ($li, $i, $xa, $ya, $d2);
        }
        $li++;
    }
    return () unless defined $best_i;
    return ($best_li, $best_i, $best_x, $best_y);
}

1;
