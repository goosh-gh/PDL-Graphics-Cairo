use strict;
use warnings;

# ==================================================================
# t/32_tight_layout_gap.t
# ------------------------------------------------------------------
# tight_layout() の h_pad/w_pad が「宣言されているだけで cell 配置計算に
# 反映されていなかった」バグ (P:G:C11, 2026-06-19 修正) の自動回帰テスト。
#
# このバグは単一行/単一列では発覚せず、複数行×複数列で初めて
# 「上段パネルの下端と下段パネルの上端がギャップ0で隣接し、xlabel と
# 下段 title が重なる」形で出る。t/31 は valign バグをピクセル検証で
# 押さえたが、h_pad/w_pad 側は verify_5x5_grid_overlap.pl という目視用
# スクリプトしか無かったため、ここで幾何レベルの自動テストを入れる。
#
# 判定方針（ピクセルは読まない・高速）:
#   Axes の cell 矩形 (fig_x, fig_y, width, height) を読み、
#   隣接セル間のギャップを計算する。fig_y は上端・y は下方向に増加
#   (Axes::draw の $mt=fig_y+margin_top、set_position のコメントで確認)。
#     縦ギャップ = 下段セル.fig_y - (上段セル.fig_y + 上段セル.height)
#     横ギャップ = 右列セル.fig_x - (左列セル.fig_x + 左列セル.width)
#   (1) 標準的な使い方 tight_layout() だけでギャップが負にならない(=重ならない)
#   (2) h_pad/w_pad を大きくするとギャップが広がる(=実際に計算へ反映されている)
# ==================================================================

use Test::More;

BEGIN {
    eval { require PDL; PDL->import; 1 }
        or plan skip_all => "PDL not available";
    eval { require PDL::Graphics::Cairo;
           PDL::Graphics::Cairo->import(qw(subplots)); 1 }
        or plan skip_all => "PDL::Graphics::Cairo not available";
}

# 3x3 グリッドを組み、各パネルに内容・title・xlabel を与えてから
# tight_layout(%pad) を適用し、各セルの矩形を返す。
sub grid_geom {
    my (%pad) = @_;
    my ($fig) = subplots(3, 3, width => 900, height => 720);
    for my $r (0 .. 2) {
        for my $c (0 .. 2) {
            my $ax = $fig->ax($r, $c);
            $ax->line(sequence(10), sequence(10));
            $ax->set_title("r$r c$c");
            $ax->set_xlabel("x");
        }
    }
    $fig->tight_layout(%pad);

    my %g;
    for my $r (0 .. 2) {
        for my $c (0 .. 2) {
            my $ax = $fig->ax($r, $c);
            $g{"$r,$c"} = {
                x => $ax->fig_x, y => $ax->fig_y,
                w => $ax->width, h => $ax->height,
            };
        }
    }
    return \%g;
}

# 縦ギャップ: (0,0) と (1,0) の間 / 横ギャップ: (0,0) と (0,1) の間
sub vgap { my $g = shift; $g->{'1,0'}{y} - ($g->{'0,0'}{y} + $g->{'0,0'}{h}) }
sub hgap { my $g = shift; $g->{'0,1'}{x} - ($g->{'0,0'}{x} + $g->{'0,0'}{w}) }

# --- (1) 標準的な使い方: tight_layout() だけで重ならない ---
{
    my $g = grid_geom();                 # 引数なし = デフォルト h_pad/w_pad
    my ($vg, $hg) = (vgap($g), hgap($g));
    cmp_ok($vg, '>=', 0, sprintf("default tight_layout: rows do not overlap (vgap=%.1f)", $vg));
    cmp_ok($hg, '>=', 0, sprintf("default tight_layout: cols do not overlap (hgap=%.1f)", $hg));
}

# --- (2) h_pad/w_pad が実際に配置へ反映されている ---
# バグ(未反映)なら pad を変えてもギャップは同じ → cmp_ok '>' が落ちる。
{
    my $small = grid_geom(h_pad => 4,  w_pad => 4);
    my $large = grid_geom(h_pad => 40, w_pad => 40);

    my ($vs, $vl) = (vgap($small), vgap($large));
    my ($hs, $hl) = (hgap($small), hgap($large));

    cmp_ok($vs, '>=', 0, sprintf("small h_pad: rows still do not overlap (vgap=%.1f)", $vs));
    cmp_ok($hs, '>=', 0, sprintf("small w_pad: cols still do not overlap (hgap=%.1f)", $hs));
    cmp_ok($vl, '>', $vs, sprintf("larger h_pad widens the row gap (%.1f -> %.1f)", $vs, $vl));
    cmp_ok($hl, '>', $hs, sprintf("larger w_pad widens the col gap (%.1f -> %.1f)", $hs, $hl));
}

done_testing();
