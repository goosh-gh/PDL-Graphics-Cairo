#!/usr/bin/env perl
# example_gs.pl — PDL::Graphics::Cairo + giza_server バックエンドのデモ
#
# giza_server 経由でウィンドウ表示し、File メニューから
# PDF/SVG/PNG で保存できる（publication quality 出力）。
#
# 使い方:
#   perl examples/example_gs.pl
#
# giza_server が PATH 上になければ:
#   GIZA_SERVER=/path/to/giza_server perl examples/example_gs.pl

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::Driver::GS;

my $x  = pdl(1..50) / 10.0;
my $y1 = $x**2;
my $y2 = $x**2 * 0.5 + $x;

my $drv = PDL::Graphics::Cairo::Driver::GS->new(
    width  => 500,
    height => 350,
    title  => 'GS backend demo',
);

print "ウィンドウを開いています...\n";
print "File メニューから PDF/SVG/PNG で保存できます。\n";
print "ウィンドウを閉じると終了します。\n\n";

$drv->show_interactive(
    render => sub {
        my ($state, $w, $h) = @_;        # $w/$h = 現在の窓キャンバスサイズ(px)
        my $fig = figure(width=>$w, height=>$h);   # ← リサイズに追従して再レイアウト
        my $ax  = $fig->axes();
        $ax->line($x, $y1, color=>'blue', lw=>1.5, label=>'x^2');
        $ax->line($x, $y2, color=>'red',  lw=>1.5, label=>'0.5x^2+x');
        $ax->set_xlabel('x');
        $ax->set_ylabel('y');
        $ax->set_title('GS backend — PDF/SVG save demo');
        $ax->legend();
        $fig->tight_layout();
        return $fig;
    },
);

print "終了しました。\n";
