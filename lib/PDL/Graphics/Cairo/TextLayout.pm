package PDL::Graphics::Cairo::TextLayout;

# =============================================================
# 複数行テキストのレイアウト計算 (backend 非依存・PDL 非依存)
#
# P:G:C の backend text() は「単一行・回転可」までしか面倒を見ない。
# "a\nb\nc" のような複数行ラベルを、
#   * 行分割
#   * 水平そろえ (halign: left/right/center) — 各行に委譲
#   * 行送り (line-spacing)
#   * ブロック全体の垂直そろえ (valign: top/middle/bottom)
#   * 回転 (angle 正=反時計回り、backend の rotate(-angle*pi/180) と同符号)
# として、行ごとの単一行 draw op に展開するのがこのモジュールの役目。
#
# ここには cairo も PDL も Moo も出てこない。純粋な座標計算だけなので
# headless (verify_text_ml.pl) で Cocoa/Xlib 非依存にテストできる。
# =============================================================

use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(ml_layout ml_max_width estimate_max_line_px);

use constant PI => 3.14159265358979;

# ml_layout($x, $y, $str, %opt) → 各行の draw op のリスト
#   返り値: ( [$sx, $sy, $line, 'left', $valign, $angle], ... )
#
# 重要: 返る op の水平そろえは常に 'left'(左アンカー)。halign(right/center)は
# ここで text 幅を使って明示的な左アンカー座標に「解決」する。これは
# backend の align=>'right'/'center' 実装に依存しないための設計 ——
# Xlib/giza-server backend は align を honor せず常に左アンカーで描くため、
# 委譲方式だと Cocoa と挙動が食い違う(2026-07-19 Ubuntu で判明)。左アンカー
# 描画と text_width はどの backend も持つ最も原始的な操作なので、これで
# プラットフォーム非依存になる。
#
# %opt:
#   align         : 'left' | 'right' | 'center'   (default 'left')  ← halign
#   valign        : 'top'  | 'middle' | 'bottom'  (default 'bottom')
#   angle         : 度。正=反時計回り                 (default 0)
#   size          : フォントサイズ(px相当)。行高の算出に使う (default 11)
#   line_spacing  : 行送り倍率                       (default 1.2)
#   widths        : [w0,w1,...] 各行の実測幅(px)。省略時は 0 = 左アンカー相当。
#                   right/center を正しく解決するには呼び出し側が渡すこと。
#
# 設計:
#   * 水平: ローカル(回転前)の読み方向を +x とし、halign オフセット
#       left=0, right=-w_i, center=-w_i/2 を各行の左アンカーに適用。
#   * 垂直: 行高 LH=size*line_spacing、行数 N。ブロック全高 N*LH を valign に
#     応じて配置(top=上端が$y, bottom=下端が$y, middle=中心が$y)。各行は
#     valign='middle' で中心合わせ。
#   * 回転: ローカル(dx,dy)→screen を
#       sx = x + dx*cos(th) - dy*sin(th)
#       sy = y + dx*sin(th) + dy*cos(th)   (th = -angle*PI/180)
#     で写す。angle=0 縦積み、angle=90 横並び。
#   * 単一行(\n 無し)は valign を元のまま保持(後方互換)。水平は widths[0] で
#     解決するが、align='left' 指定なら幅不要でそのまま。
sub ml_layout {
    my ($x, $y, $str, %o) = @_;
    my $align  = $o{align}        // 'left';
    my $valign = $o{valign}       // 'bottom';
    my $angle  = $o{angle}        // 0;
    my $size   = $o{size}         // 11;
    my $lsp    = $o{line_spacing} // 1.2;
    my $widths = $o{widths};

    my @lines = split /\n/, (defined $str ? $str : ''), -1;

    my $th = -$angle * PI / 180;
    my ($s, $c) = (sin($th), cos($th));

    # halign → ローカル +x オフセット(左アンカー基準)
    my $hoff = sub {
        my $w = shift // 0;
        return 0      if $align eq 'left';
        return -$w    if $align eq 'right';
        return -$w/2;             # center
    };

    # 単一行: valign を保持したまま、水平だけ解決(後方互換)。
    if (@lines <= 1) {
        my $w  = $widths ? ($widths->[0] // 0) : 0;
        my $dx = $hoff->($w);
        my $sx = $x + $dx * $c;
        my $sy = $y + $dx * $s;
        return ([$sx, $sy, $str, 'left', $valign, $angle]);
    }

    my $LH = $size * $lsp;
    my $N  = scalar @lines;
    my $top = ($valign eq 'top')    ?  0
            : ($valign eq 'bottom') ? -$N * $LH
            :                         -$N * $LH / 2;   # middle / center

    my @ops;
    for my $i (0 .. $#lines) {
        my $w  = $widths ? ($widths->[$i] // 0) : 0;
        my $dx = $hoff->($w);
        my $dy = $top + $i * $LH + $LH / 2;   # 行 i の中心(ローカル下向き正)
        my $sx = $x + $dx * $c - $dy * $s;
        my $sy = $y + $dx * $s + $dy * $c;
        push @ops, [$sx, $sy, $lines[$i], 'left', 'middle', $angle];
    }
    return @ops;
}

# ml_max_width($str, $width_cb) → 最長行の幅
#   $width_cb->($line) が1行の幅(px)を返すコールバック。backend の
#   text_width を渡す。マージン確保 (tight_layout / ylabel 配置) で
#   複数行ラベルの最長行が切れないようにするために使う。
sub ml_max_width {
    my ($str, $width_cb) = @_;
    my $max = 0;
    for my $ln (split /\n/, (defined $str ? $str : ''), -1) {
        my $w = eval { $width_cb->($ln) } // 0;
        $max = $w if $w > $max;
    }
    return $max;
}

# estimate_max_line_px($str, $font_px, $char_ratio) → 最長行の推定幅(px)
#   backend(cairo)が使えない場面 — 特に tight_layout はレイアウトを描画前に
#   決めるため text_width を実測できない — で、マージン確保用にラベル占有幅を
#   見積もる。最長行の文字数 × フォント高 × 平均字幅比 で近似する。
#   実測ではないので、切れ防止のため気持ち広め(比 0.62)に見積もる。
#   ml_max_width と違い width コールバックを要らない(純粋に文字数ベース)。
sub estimate_max_line_px {
    my ($str, $font_px, $char_ratio) = @_;
    $font_px    //= 10;
    $char_ratio //= 0.62;
    my $maxch = 0;
    for my $ln (split /\n/, (defined $str ? $str : ''), -1) {
        my $n = length $ln;
        $maxch = $n if $n > $maxch;
    }
    return $maxch * $font_px * $char_ratio;
}

1;
