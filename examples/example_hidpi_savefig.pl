#!/usr/bin/env perl
# example_hidpi_savefig.pl
#   -- PDL::Graphics::Cairo savefig(dpi=>...) 解像度デモ
#
# 同一のプロットを複数の解像度で書き出し、ファイルサイズと
# 画像サイズの違いを確認する。論文/ポスター用の高解像度出力が
# 必要な場面（印刷用300dpi等）を想定したデモ。
#
# 実行: perl -I./lib examples/example_hidpi_savefig.pl

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(subplots);

# ============================================================
# Demo 1: 同じ図を96dpi(画面表示用)/150dpi/300dpi(印刷用)で出力
#   し、画像サイズ・ファイルサイズの違いを比較する。
# ============================================================
{
    my $x = sequence(200) / 20;
    my $y = sin($x) * exp(-$x/15);

    my ($fig, $ax) = subplots(width=>500, height=>350);
    $ax->plot($x, $y, color=>'steelblue', lw=>2);
    $ax->set_title('Damped oscillation: sin(x)·exp(-x/15)');
    $ax->set_xlabel('Time (s)');
    $ax->set_ylabel('Amplitude');
    $fig->tight_layout();

    my @configs = (
        { dpi => 96,  label => 'screen (96dpi, default)' },
        { dpi => 150, label => 'presentation (150dpi)'   },
        { dpi => 300, label => 'print/publication (300dpi)' },
    );

    for my $cfg (@configs) {
        my $dpi = $cfg->{dpi};
        my $outfile = "/tmp/hidpi_demo_${dpi}dpi.png";
        $fig->savefig($outfile, dpi => $dpi);
        my $size_kb = sprintf('%.1f', (-s $outfile) / 1024);
        print "Saved: $outfile  ($cfg->{label}, ${size_kb} KB)\n";
    }
}

# ============================================================
# Demo 2: save() でも同様にdpi指定が効くことを確認
#   (savefig は save の別名として動作する)
# ============================================================
{
    my ($fig, $ax) = subplots(width=>400, height=>300);
    my $x = sequence(50) / 5;
    $ax->scatter($x, sin($x), color=>'crimson', s=>10);
    $ax->set_title('save(dpi=>) also supports resolution scaling');
    $fig->tight_layout();

    $fig->save('/tmp/hidpi_demo_save_default.png');
    $fig->save('/tmp/hidpi_demo_save_2x.png', dpi=>192);   # 96dpiの2倍

    my $sz_default = -s '/tmp/hidpi_demo_save_default.png';
    my $sz_2x       = -s '/tmp/hidpi_demo_save_2x.png';
    printf "default: %d bytes,  dpi=>192 (2x): %d bytes  (ratio: %.2fx)\n",
        $sz_default, $sz_2x, $sz_2x / $sz_default;
}

# ============================================================
# Demo 3: 複数パネルの図でも一括して高解像度出力できることを確認
#   (論文Figure等、複数パネルをまとめて1枚の高解像度画像にする
#   典型的なワークフロー)
# ============================================================
{
    my ($fig, @ax) = subplots(1, 3, width=>900, height=>300);
    my $x = sequence(100) / 10;
    $ax[0]->plot($x, sin($x), color=>'steelblue');
    $ax[0]->set_title('Panel A');
    $ax[1]->plot($x, cos($x), color=>'darkorange');
    $ax[1]->set_title('Panel B');
    $ax[2]->plot($x, sin($x)*cos($x), color=>'darkgreen');
    $ax[2]->set_title('Panel C');
    $fig->tight_layout();

    $fig->savefig('/tmp/hidpi_demo_multipanel_300dpi.png', dpi=>300);
    my $size_kb = sprintf('%.1f', (-s '/tmp/hidpi_demo_multipanel_300dpi.png') / 1024);
    print "Saved: /tmp/hidpi_demo_multipanel_300dpi.png (300dpi, ${size_kb} KB)\n";
}

print "\nDone. Open with: open /tmp/hidpi_demo_*.png\n";
print "Tip: 300dpiのPNGをプレビュー等で開き、ピクセル等倍にズームすると\n";
print "     文字や線の輪郭が96dpi版より滑らかに見えることを確認できます。\n";
