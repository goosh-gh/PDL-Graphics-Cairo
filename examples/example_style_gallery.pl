#!/usr/bin/env perl
# example_style_gallery.pl — PDL::Graphics::Cairo style.use() ギャラリー
# 利用可能な全スタイルプリセットを1枚の画像で見比べられるようにする。
# matplotlibの style gallery (https://matplotlib.org/stable/gallery/
# style_sheets/style_sheets_reference.html) に相当する一覧表示。
# 実行: perl -I./lib examples/example_style_gallery.pl

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots style rcParams);

# 利用可能なスタイル一覧 (style.use() に渡せる名前)
my @styles = PDL::Graphics::Cairo::Style->available();
print "Available styles: ", join(', ', @styles), "\n\n";

my $x = sequence(60) / 6;

# ============================================================
# 各スタイルで同一のプロット内容を描き、1パネルずつ並べる。
# サブプロット数 = スタイル数。2列で折り返す。
# ============================================================
my $n_styles = scalar @styles;
my $ncols = 2;
my $nrows = int(($n_styles + $ncols - 1) / $ncols);

my ($fig, @rows) = subplots($nrows, $ncols, width=>1100, height=>320*$nrows);
$fig->suptitle('PDL::Graphics::Cairo Style Gallery', fontsize=>16);

my @flat_ax = map { @$_ } @rows;

for my $i (0 .. $#styles) {
    my $style_name = $styles[$i];
    my $ax = $flat_ax[$i];

    # このパネルだけそのスタイルを適用してプロットし、すぐ
    # defaultに戻す。(rcParamsはグローバルなので、パネルごとに
    # 切り替えて描いては戻す、という手順を踏む必要がある)
    style($style_name);

    $ax->plot($x, sin($x), label=>'sin(x)');
    $ax->plot($x, cos($x), label=>'cos(x)');
    $ax->scatter($x->slice('0:-1:5'), sin($x->slice('0:-1:5'))*0.8,
        s=>14, alpha=>0.7);
    $ax->set_title("'$style_name'");
    $ax->legend();

    style('default');   # 次のパネルに影響しないよう即座に戻す
}

$fig->tight_layout();
$fig->save('/tmp/style_gallery_overview.png');
print "Saved: /tmp/style_gallery_overview.png\n";

# ============================================================
# Demo 2: 単一プロットでスタイルの効果を1枚ずつ拡大表示
#   (Qiita記事等に「このスタイルはこう見える」と個別に貼りたい場合用)
# ============================================================
for my $style_name (@styles) {
    style($style_name);

    my ($fig2, $ax2) = subplots(width=>500, height=>380);
    my $x2 = sequence(80) / 8;
    $ax2->plot($x2, sin($x2), lw=>2, label=>'sin(x)');
    $ax2->plot($x2, sin($x2*1.5)*0.6, lw=>2, label=>'sin(1.5x)·0.6');
    $ax2->fill_between($x2, sin($x2)*0, sin($x2), alpha=>0.15);
    $ax2->set_title("style('$style_name')");
    $ax2->set_xlabel('x'); $ax2->set_ylabel('y');
    $ax2->legend();

    $fig2->tight_layout();
    my $outfile = "/tmp/style_single_${style_name}.png";
    $fig2->save($outfile);
    print "Saved: $outfile\n";

    style('default');
}

print "\nDone. Open with: open /tmp/style_gallery_overview.png\n";
print "Individual style demos: open /tmp/style_single_*.png\n";
