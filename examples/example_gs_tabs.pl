#!/usr/bin/env perl
# example_gs_tabs.pl — タブ順序の確認用（特に Xlib バックエンド / Ubuntu）
#
# giza_server はクライアントの PID(SO_PEERCRED) ごとに窓をタブ化する。
# 1本のプロセスから複数の図を show すると、同じ PID なので 1 窓に
# タブとしてまとまる。
#
# このスクリプトは「タブ順序バグ」の回帰確認用:
#   _open_window は空きスロットを再利用するため、中間タブを閉じてから
#   新しいタブを開くと、修正前は新タブが「閉じた穴」の位置(中間)に挿さって
#   作成順が崩れた。tab_seq ソート修正後は、新タブは必ず末尾に付く。
#
# 中間タブを閉じる操作だけは GUI(タブの × クリック)なので半自動。
#
# 使い方:
#   perl -Ilib examples/example_gs_tabs.pl
# giza_server が PATH 上に無い場合:
#   GIZA_SERVER=/path/to/giza_server perl -Ilib examples/example_gs_tabs.pl
#
# 検証ポイント(Ubuntu/Xlib):
#   修正後 → 最終的なタブ順は左から  [Tab 1] [Tab 3] [Tab 4]
#   修正前 → Tab 4 が Tab 1 と Tab 3 の間(閉じた Tab 2 の穴)に出る

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure);

my $x = pdl(1..50) / 10.0;

# 各タブを内容でも見分けられるよう、別々の曲線を描く
sub make_tab {
    my ($n, $y) = @_;
    my $fig = figure(width => 480, height => 320);
    my ($ax) = $fig->subplots(1, 1);
    $ax->line($x, $y);
    $ax->set_title("Tab $n");
    $fig->tight_layout;
    # title => が GSP_MSG_TITLE となりタブのラベルになる
    $fig->show(backend => 'gs', title => "Tab $n");
}

print "=== タブ順序の回帰確認 (Xlib) ===\n\n";

print "[1/3] Tab 1〜3 を開きます（同一プロセス＝1窓に 3 タブ）...\n";
make_tab(1, $x**2);            # 上に凸の放物線
make_tab(2, sin($x));         # サイン波
make_tab(3, sqrt($x));        # 平方根
print "    → 1 つの窓にタブが 3 枚並んでいるはずです: [Tab 1][Tab 2][Tab 3]\n\n";

print "[2/3] 窓の中の *中間* タブ (Tab 2) を、タブの × ボックスで閉じてください。\n";
print "      閉じたら Enter を押してください... ";
<STDIN>;

print "\n[3/3] Tab 4 を開きます（同一プロセスなので同じ窓に合流）...\n";
make_tab(4, $x * cos($x));    # 見分け用に別の曲線
print "\n";

print "=== 確認 ===\n";
print "  修正後  : タブ順は左から  [Tab 1] [Tab 3] [Tab 4]  （Tab 4 は末尾）\n";
print "  修正前  : [Tab 1] [Tab 4] [Tab 3]  のように Tab 4 が穴に挿さって中間に出る\n\n";
print "確認できたら Enter で終了（窓はサーバ側に残ります）... ";
<STDIN>;
print "終了します。窓は giza_server が保持しています（Cmd/Alt+閉じる で消せます）。\n";
