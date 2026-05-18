#!/usr/bin/env perl
# =============================================================
# example_save.pl  —  PDL::Graphics::Cairo ファイル保存デモ
#
# 実行方法（PDL-Graphics-Cairo/ ルートから）:
#   perl -I./lib examples/example_save.pl
#   perl -I./lib examples/example_save.pl ~/Desktop   # 出力先を指定
#
# 出力ファイル:
#   plot.png   PNG  形式（ラスタ、Retina 対応）
#   plot.pdf   PDF  形式（ベクタ、印刷品質）
#   plot.svg   SVG  形式（ベクタ、Web 埋め込み）
# =============================================================

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure);

my $OUT = $ARGV[0] // '.';
die "出力先ディレクトリが存在しません: $OUT\n" unless -d $OUT;

my $PI = 3.14159265358979;

# --- 共通のプロットを組み立てる ---
sub make_figure {
    my $x  = sequence(300) / 15;
    my $y1 = sin($x);
    my $y2 = cos($x);

    my $fig = figure(width => 800, height => 500);
    my $ax  = $fig->axes();

    $ax->title("PDL::Graphics::Cairo  —  File Output Demo");
    $ax->xlabel("x");
    $ax->ylabel("y");
    $ax->set_grid(1);

    $ax->line($x, $y1, color=>'blue',   lw=>2.0, label=>'sin(x)');
    $ax->line($x, $y2, color=>'orange', lw=>2.0, label=>'cos(x)', ls=>'dashed');
    $ax->fill_between($x, $y1, $y2,
        color=>'purple', alpha=>0.08, label=>'sin-cos band');
    $ax->axhline(0, color=>'gray', lw=>0.8, ls=>'dotted');
    $ax->legend(loc=>'upper right');

    return $fig;
}

# =============================================================
# PNG 保存
# =============================================================
{
    my $file = "$OUT/plot.png";
    make_figure()->save($file);
    my $kb = int((-s $file) / 1024) || 1;
    printf "PNG: %-40s  (%d KB)\n", $file, $kb;
}

# =============================================================
# PDF 保存
# =============================================================
{
    my $file = "$OUT/plot.pdf";
    make_figure()->save($file);
    my $kb = int((-s $file) / 1024) || 1;
    printf "PDF: %-40s  (%d KB)\n", $file, $kb;
}

# =============================================================
# SVG 保存
# =============================================================
{
    my $file = "$OUT/plot.svg";
    make_figure()->save($file);
    my $kb = int((-s $file) / 1024) || 1;
    printf "SVG: %-40s  (%d KB)\n", $file, $kb;
}

print "\nDone. Open the files to compare formats.\n";
