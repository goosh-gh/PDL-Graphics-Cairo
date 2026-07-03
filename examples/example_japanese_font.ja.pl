#!/usr/bin/env perl
# =============================================================
# example_japanese_font.ja.pl
#   -- PDL::Graphics::Cairo 日本語フォント対応デモ
#
# Qiita等の技術記事に日本語ラベル入りの図を載せる際、デフォルトの
# Helvetica Neue では日本語グリフが描けず「豆腐」(□□□)になって
# しまう。rcParams('font.family' => ...) でCJK対応フォントに切り替
# えることでこれを回避する。
#
# macOS環境で確認済みのフォント名（MacPorts perl + Cairo + Pango
# 環境）:
#   'Hiragino Kaku Gothic ProN'  -- macOS標準の日本語ゴシック体
#   'Hiragino Mincho ProN'       -- macOS標準の日本語明朝体
#   'Noto Sans CJK JP'           -- Google Noto、Linux/クロスプラ
#                                    ットフォームでも入手しやすい
#   'IPAGothic' / 'IPAMincho'    -- IPAフォント、フリーで再配布可
#
# 実行: perl -I./lib examples/example_japanese_font.ja.pl
# =============================================================

use strict;
use warnings;
use utf8;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots style rcParams);

binmode(STDOUT, ':utf8');

# ============================================================
# Demo 1: デフォルトフォント(Helvetica Neue)で日本語タイトルを
#   試した場合 -- 環境によっては文字が表示されない/欠けることを
#   確認するための比較用。
# ============================================================
{
    my ($fig, $ax) = subplots(width=>500, height=>380);
    my $x = sequence(50) / 5;
    $ax->plot($x, sin($x), color=>'steelblue', lw=>2);
    $ax->set_title('デフォルトフォント (Helvetica Neue)');
    $ax->set_xlabel('時間 (秒)');
    $ax->set_ylabel('振幅');
    $fig->tight_layout();
    $fig->save('/tmp/jpfont_demo_1_default.png');
    print "Saved: /tmp/jpfont_demo_1_default.png\n";
    print "  (環境によっては日本語が表示されない可能性あり)\n";
}

# ============================================================
# Demo 2: rcParams('font.family') でヒラギノ角ゴに切り替えた場合
#   -- macOS環境ではこれが最も確実。
# ============================================================
{
    rcParams('font.family' => 'Hiragino Kaku Gothic ProN');

    my ($fig, $ax) = subplots(width=>500, height=>380);
    my $x = sequence(50) / 5;
    $ax->plot($x, sin($x), color=>'darkorange', lw=>2);
    $ax->set_title('ヒラギノ角ゴシック指定後');
    $ax->set_xlabel('時間 (秒)');
    $ax->set_ylabel('振幅 (正規化)');
    $fig->tight_layout();
    $fig->save('/tmp/jpfont_demo_2_hiragino.png');
    print "Saved: /tmp/jpfont_demo_2_hiragino.png\n";

    rcParams('font.family' => 'Helvetica Neue');   # 後続Demo用に戻す
}

# ============================================================
# Demo 3: EEG解析を想定した、日本語ラベル入りの実用的な図
#   -- チャンネル名・刺激条件名等、Qiita記事で実際に使う構成。
# ============================================================
{
    rcParams('font.family' => 'Hiragino Kaku Gothic ProN');

    my $t = sequence(500) / 500 * 2 - 0.5;   # -0.5s ~ 1.5s
    # 模擬ERP波形 (P300風の陽性成分)
    my $erp_target   = exp(-(($t-0.3)**2)/0.02) * 8 - exp(-(($t-0.1)**2)/0.005)*3;
    my $erp_standard = exp(-(($t-0.3)**2)/0.04) * 2 - exp(-(($t-0.1)**2)/0.005)*3;

    my ($fig, $ax) = subplots(width=>650, height=>450);
    $ax->plot($t, $erp_target,   color=>'crimson',    lw=>2, label=>'標的刺激');
    $ax->plot($t, $erp_standard, color=>'steelblue',  lw=>2, label=>'標準刺激');
    $ax->axvline(0, color=>'gray', ls=>'dashed', lw=>1, alpha=>0.6);
    $ax->set_title('事象関連電位 (ERP): Pz電極, オドボール課題');
    $ax->set_xlabel('刺激提示後の時間 (秒)');
    $ax->set_ylabel('電位 (μV)');
    $ax->legend();
    $ax->grid(1);
    $fig->tight_layout();
    $fig->save('/tmp/jpfont_demo_3_erp.png');
    print "Saved: /tmp/jpfont_demo_3_erp.png\n";

    rcParams('font.family' => 'Helvetica Neue');
}

# ============================================================
# Demo 4: style()との組み合わせ -- 日本語フォント + ggplotスタイル
#   をQiita記事で同時に使う典型パターン。
# ============================================================
{
    style('ggplot');
    rcParams('font.family' => 'Hiragino Kaku Gothic ProN');

    my ($fig, $ax) = subplots(width=>550, height=>400);
    my $categories = ['Fp1','F3','C3','P3','O1'];
    my $values     = pdl(12.3, 18.7, 25.1, 15.4, 9.8);
    $ax->bar(sequence(5), $values, color=>'#348ABD', alpha=>0.85);
    $ax->set_xticks(sequence(5));
    $ax->set_xticklabels($categories);
    $ax->set_title('チャンネル別パワー値 (ggplotスタイル)');
    $ax->set_ylabel('パワー (μV²)');
    $fig->tight_layout();
    $fig->save('/tmp/jpfont_demo_4_style_combo.png');
    print "Saved: /tmp/jpfont_demo_4_style_combo.png\n";

    style('default');
    rcParams('font.family' => 'Helvetica Neue');
}

print "\n完了。確認: open /tmp/jpfont_demo_*.png\n";
print "\n備考: フォント名は環境依存です。Linux/クロスプラットフォーム\n";
print "環境では 'Noto Sans CJK JP' や 'IPAGothic' が確実な選択肢です。\n";
print "利用可能なフォント名はシステムのフォントマネージャ\n";
print "(macOS: フォントブック / Linux: fc-list) で確認してください。\n";
