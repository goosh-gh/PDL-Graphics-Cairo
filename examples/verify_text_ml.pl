#!/usr/bin/env perl
# examples/verify_text_ml.pl
#
# text() 複数行対応 (P:G:C14) の headless 検証。
# PDL::Graphics::Cairo::TextLayout のレイアウト計算だけを対象にするので、
# PDL も Moo も cairo も giza-server も要らない。Cocoa/Xlib 両プラットフォーム
# で同一に green になる(そもそも backend に触れない純幾何テスト)。
#
# 検証項目:
#   1. 単一行は 1 op・valign 保持(後方互換、既存描画とピクセル一致)
#   2. 複数行の行数展開と垂直センタリング(valign=middle)
#   3. valign top / bottom のブロック配置
#   4. halign(right/center/left) が各行に委譲される
#   5. line_spacing が行間に効く
#   6. 回転 angle=90 で行が横並び(縦オフセット→+x 方向)になる
#   7. ml_max_width が最長行の幅を返す
#   8. MockBackend 経由で _text_ml 相当が行数ぶん text() を呼ぶ
#
# Usage:  perl -Ilib examples/verify_text_ml.pl

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use PDL::Graphics::Cairo::TextLayout qw(ml_layout ml_max_width estimate_max_line_px);

my $N = 0;
my $FAIL = 0;
sub ok ($$) {
    my ($cond, $name) = @_;
    $N++;
    if ($cond) { print "ok $N - $name\n" }
    else       { print "not ok $N - $name\n"; $FAIL++ }
}
sub near ($$;$) {
    my ($a, $b, $eps) = @_;
    $eps //= 1e-6;
    return abs($a - $b) < $eps;
}

# ---------------------------------------------------------------
# 1. 単一行: 1 op、valign はそのまま(後方互換)
# ---------------------------------------------------------------
{
    my @ops = ml_layout(100, 50, "hello", align => 'right', valign => 'top', angle => 0);
    ok(@ops == 1, "single line -> exactly 1 op");
    ok($ops[0][2] eq 'hello', "single line: text passed through");
    ok($ops[0][0] == 100 && $ops[0][1] == 50, "single line: anchor unchanged");
    ok($ops[0][3] eq 'right', "single line: align passed through");
    ok($ops[0][4] eq 'top', "single line: valign preserved (not forced to middle)");
}

# 空文字も単一行扱い
{
    my @ops = ml_layout(0, 0, "", valign => 'bottom');
    ok(@ops == 1 && $ops[0][4] eq 'bottom', "empty string -> 1 op, valign preserved");
}

# ---------------------------------------------------------------
# 2. 複数行 + 垂直センタリング(middle)
#    size=10, lsp=1.2 -> LH=12, N=3, 中心は y に対称
# ---------------------------------------------------------------
{
    my @ops = ml_layout(100, 50, "a\nb\nc",
        align => 'right', valign => 'middle', size => 10, line_spacing => 1.2);
    ok(@ops == 3, "3 lines -> 3 ops");
    ok($ops[0][2] eq 'a' && $ops[1][2] eq 'b' && $ops[2][2] eq 'c',
        "lines split in order");
    ok(near($ops[0][1], 38) && near($ops[1][1], 50) && near($ops[2][1], 62),
        "middle: lines centred on anchor (38,50,62)");
    # 各行の中心は等間隔(LH=12)
    ok(near($ops[1][1] - $ops[0][1], 12) && near($ops[2][1] - $ops[1][1], 12),
        "middle: even line spacing = size*line_spacing = 12");
    # 全行 valign=middle(中心合わせ)、x は不変(角度0)
    ok((grep { $_->[4] eq 'middle' } @ops) == 3, "multi: each line drawn valign=middle");
    ok((grep { $_->[0] == 100 } @ops) == 3, "angle=0: x anchor unchanged for all lines");
}

# ---------------------------------------------------------------
# 3. valign top / bottom のブロック配置
#    LH=12, N=2 -> ブロック全高 24
# ---------------------------------------------------------------
{
    my @top = ml_layout(0, 100, "x\ny", valign => 'top', size => 10, line_spacing => 1.2);
    # top: ブロック上端が y=100。行中心は 106, 118。
    ok(near($top[0][1], 106) && near($top[1][1], 118),
        "valign=top: block top at anchor (centres 106,118)");

    my @bot = ml_layout(0, 100, "x\ny", valign => 'bottom', size => 10, line_spacing => 1.2);
    # bottom: ブロック下端が y=100。行中心は 82, 94。
    ok(near($bot[0][1], 82) && near($bot[1][1], 94),
        "valign=bottom: block bottom at anchor (centres 82,94)");

    # top と bottom はブロック全高(24)ぶんずれる
    ok(near($top[0][1] - $bot[0][1], 24), "top vs bottom differ by block height (24)");
}

# ---------------------------------------------------------------
# 4. halign が各行に委譲される
# ---------------------------------------------------------------
{
    for my $ha (qw(left right center)) {
        my @ops = ml_layout(0, 0, "aa\nbbbb", align => $ha);
        ok((grep { $_->[3] eq $ha } @ops) == 2, "halign=$ha delegated to every line");
    }
}

# ---------------------------------------------------------------
# 5. line_spacing が行間に効く
# ---------------------------------------------------------------
{
    my @tight = ml_layout(0, 0, "a\nb", size => 10, line_spacing => 1.0, valign => 'top');
    my @loose = ml_layout(0, 0, "a\nb", size => 10, line_spacing => 2.0, valign => 'top');
    my $gap_t = $tight[1][1] - $tight[0][1];   # =10
    my $gap_l = $loose[1][1] - $loose[0][1];   # =20
    ok(near($gap_t, 10), "line_spacing=1.0 -> gap 10");
    ok(near($gap_l, 20), "line_spacing=2.0 -> gap 20");
    ok($gap_l > $gap_t, "larger line_spacing -> larger gap");
}

# ---------------------------------------------------------------
# 6. 回転 angle=90: 行が横並び(縦オフセット -> +x)
#    th = -90deg, sin=-1, cos=0 -> sx = x - dy*sin = x + dy, sy = y
# ---------------------------------------------------------------
{
    my @ops = ml_layout(200, 300, "a\nb", angle => 90, valign => 'middle',
        size => 10, line_spacing => 1.2);   # LH=12, dy = -6, +6
    ok(near($ops[0][1], 300) && near($ops[1][1], 300),
        "angle=90: all lines share the same screen-y (horizontal stacking)");
    ok(near($ops[0][0], 194) && near($ops[1][0], 206),
        "angle=90: lines separate along x by line height (194,206)");
    ok((grep { $_->[5] == 90 } @ops) == 2, "angle passed through to each line op");
}

# 回転 angle=0 の逆確認: 横位置は動かない
{
    my @ops = ml_layout(200, 300, "a\nb", angle => 0, valign => 'middle');
    ok(near($ops[0][0], 200) && near($ops[1][0], 200), "angle=0: x fixed for all lines");
}

# ---------------------------------------------------------------
# 7. ml_max_width: 最長行の幅
# ---------------------------------------------------------------
{
    # 幅コールバックは文字数 * 6px の擬似メトリクス
    my $cb = sub { length($_[0]) * 6 };
    ok(ml_max_width("Fp1\n(4 uV)", $cb) == 6 * 6,
        "ml_max_width: longest line '(4 uV)' = 36");
    ok(ml_max_width("single", $cb) == 6 * 6, "ml_max_width: single line");
    ok(ml_max_width("", $cb) == 0, "ml_max_width: empty -> 0");
    # コールバックが die しても 0 に落ちて全体は壊れない
    ok(ml_max_width("x\ny", sub { die "boom" }) == 0,
        "ml_max_width: width_cb failure tolerated (-> 0)");
}

# ---------------------------------------------------------------
# 8. MockBackend 経由の統合: _text_ml が行数ぶん text() を呼ぶ
#    (Axes::_text_ml と同じ流し込みを最小再現)
# ---------------------------------------------------------------
{
    package MockBackend;
    sub new { bless { calls => [] }, shift }
    sub text {
        my ($self, $x, $y, $str, %o) = @_;
        push @{$self->{calls}}, { x => $x, y => $y, str => $str, %o };
    }
    sub text_width { length($_[1]) * 6 }
}
{
    my $b = MockBackend->new;
    # Axes::_text_ml の中身と同じ: ml_layout の結果を text() に流す
    for my $op (ml_layout(10, 20, "row1\nrow2\nrow3",
        align => 'right', valign => 'middle', size => 10, line_spacing => 1.2)) {
        my ($sx, $sy, $line, $al, $va, $ang) = @$op;
        $b->text($sx, $sy, $line, align => $al, valign => $va, angle => $ang);
    }
    ok(@{$b->{calls}} == 3, "integration: 3-line label -> 3 backend text() calls");
    ok($b->{calls}[0]{str} eq 'row1' && $b->{calls}[2]{str} eq 'row3',
        "integration: lines drawn in order");
    ok((grep { $_->{align} eq 'right' } @{$b->{calls}}) == 3,
        "integration: right-align reaches backend for every line");

    # 単一行は 1 回だけ(後方互換: 呼び出し数が増えない)
    my $b2 = MockBackend->new;
    for my $op (ml_layout(10, 20, "solo", align => 'left', valign => 'bottom')) {
        my ($sx, $sy, $line, $al, $va, $ang) = @$op;
        $b2->text($sx, $sy, $line, align => $al, valign => $va, angle => $ang);
    }
    ok(@{$b2->{calls}} == 1 && $b2->{calls}[0]{valign} eq 'bottom',
        "integration: single line -> exactly 1 call, valign preserved");
}

# ---------------------------------------------------------------
# 9b. estimate_max_line_px: tight_layout の描画前マージン見積り
#     (backend 無しでラベル占有幅を文字数から推定)
# ---------------------------------------------------------------
{
    # 最長行の文字数で決まる。size=10, ratio=0.62 -> char=6.2px
    ok(near(estimate_max_line_px("Fp1\n(4 uV)", 10), 6 * 6.2),
        "estimate: longest line '(4 uV)'=6ch * 10 * 0.62");
    ok(near(estimate_max_line_px("x", 10), 1 * 6.2), "estimate: single char");
    ok(estimate_max_line_px("", 10) == 0, "estimate: empty -> 0");
    # フォントが大きいほど広く見積もる
    ok(estimate_max_line_px("abcd", 14) > estimate_max_line_px("abcd", 7),
        "estimate: scales with font size");
    # 多行では最長行が支配。'(250 uV)'(8) が 'T7'(2) より長い
    ok(near(estimate_max_line_px("T7\n(250 uV)", 10), 8 * 6.2),
        "estimate: multi-line dominated by longest line");
    # margin 用途は「切れ防止」なので実測より広め(比0.62)である想定
    ok(estimate_max_line_px("MMMMM", 10) >= 5 * 5,
        "estimate: generous enough vs a ~5px/char floor");
}


#    "Fp1\n(4 uV)" が右寄せ・中心対称・最長行で測れること
# ---------------------------------------------------------------
{
    my @ops = ml_layout(72, 200, "Fp1\n(4 uV)",
        align => 'right', valign => 'middle', size => 7, line_spacing => 1.2);
    ok(@ops == 2, "EEG y-label: two lines");
    ok((grep { $_->[3] eq 'right' } @ops) == 2, "EEG y-label: right-aligned");
    ok(near(($ops[0][1] + $ops[1][1]) / 2, 200),
        "EEG y-label: block centred on tick y");
    my $cb = sub { length($_[0]) * 5.4 };
    ok(ml_max_width("Fp1\n(4 uV)", $cb) == length("(4 uV)") * 5.4,
        "EEG y-label: margin measured from longest line '(4 uV)'");
}

print "1..$N\n";
if ($FAIL) { warn "\nFAILED $FAIL/$N\n"; exit 1 }
else       { warn "\nAll $N tests passed.\n"; exit 0 }
