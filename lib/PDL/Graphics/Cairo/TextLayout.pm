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
#   返り値: ( [$sx, $sy, $line, $align, $valign, $angle], ... )
#
# %opt:
#   align         : 'left' | 'right' | 'center'   (default 'left')  ← halign
#   valign        : 'top'  | 'middle' | 'bottom'  (default 'bottom')
#   angle         : 度。正=反時計回り                 (default 0)
#   size          : フォントサイズ(px相当)。行高の算出に使う (default 11)
#   line_spacing  : 行送り倍率                       (default 1.2)
#
# 設計上の要点:
#   * 水平そろえは各行の $align として backend に委譲する。右寄せなら各行の
#     右端が $x に、center なら各行が $x を中心に揃う。行ごとに幅が違っても
#     正しく揃うので、ここで幅を測る必要は無い。
#   * 垂直方向: 行高 LH = size * line_spacing、行数 N。ブロック全高 N*LH を
#     valign に応じて配置し、各行は valign='middle' で中心を合わせる。
#       top    : ブロック上端がアンカー $y
#       bottom : ブロック下端がアンカー $y
#       middle : ブロック中心がアンカー $y
#   * 回転: ローカル(回転前)座標での縦オフセット(下向き正) $dy を、
#     screen 座標へ  screen_x = $x - $dy*sin(th) ,  screen_y = $y + $dy*cos(th)
#     (th = -angle*PI/180) で写す。angle=0 で縦積み、angle=90 で横並び。
#   * 単一行 (\n 無し) は元の valign のまま素通し = 既存描画のピクセル一致。
sub ml_layout {
    my ($x, $y, $str, %o) = @_;
    my $align  = $o{align}        // 'left';
    my $valign = $o{valign}       // 'bottom';
    my $angle  = $o{angle}        // 0;
    my $size   = $o{size}         // 11;
    my $lsp    = $o{line_spacing} // 1.2;

    my @lines = split /\n/, (defined $str ? $str : ''), -1;

    # 単一行: 後方互換のため valign をそのまま返す。
    return ([$x, $y, $str, $align, $valign, $angle]) if @lines <= 1;

    my $LH = $size * $lsp;
    my $N  = scalar @lines;

    my $top = ($valign eq 'top')    ?  0
            : ($valign eq 'bottom') ? -$N * $LH
            :                         -$N * $LH / 2;   # middle / center

    my $th = -$angle * PI / 180;
    my ($s, $c) = (sin($th), cos($th));

    my @ops;
    for my $i (0 .. $#lines) {
        my $dy = $top + $i * $LH + $LH / 2;   # 行 i の中心(ローカル下向き正)
        my $sx = $x - $dy * $s;
        my $sy = $y + $dy * $c;
        push @ops, [$sx, $sy, $lines[$i], $align, 'middle', $angle];
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
