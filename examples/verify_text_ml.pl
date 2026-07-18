#!/usr/bin/env perl
# examples/verify_text_ml.pl
#
# text() 複数行対応 (P:G:C14) の headless 検証。
# PDL::Graphics::Cairo::TextLayout のレイアウト計算だけを対象にするので、
# PDL も Moo も cairo も giza-server も要らない。Cocoa/Xlib 両プラットフォーム
# で同一に green になる(そもそも backend に触れない純幾何テスト)。
#
# 【契約(2026-07-19 改訂)】ml_layout が返す op の水平そろえは常に 'left'
# (左アンカー)。halign(right/center)は widths(各行の実測幅)を使って明示的な
# 左アンカー座標に解決される。これは Xlib/giza-server backend が
# align=>'right'/'center' を honor しないため(Cocoa は honor する)で、
# 左アンカー描画 + text_width だけに依存することでプラットフォーム非依存に
# する狙い。
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
# 1. 単一行: 1 op・左アンカー・valign 保持・widths 無しで無シフト
# ---------------------------------------------------------------
{
    my @ops = ml_layout(100, 50, "hello", align => 'right', valign => 'top', angle => 0);
    ok(@ops == 1, "single line -> exactly 1 op");
    ok($ops[0][2] eq 'hello', "single line: text passed through");
    ok($ops[0][0] == 100 && $ops[0][1] == 50,
        "single line: no shift when widths absent (anchor 100,50)");
    ok($ops[0][3] eq 'left', "single line: op always left-anchored");
    ok($ops[0][4] eq 'top', "single line: valign preserved (not forced to middle)");
}
{
    my @ops = ml_layout(0, 0, "", valign => 'bottom');
    ok(@ops == 1 && $ops[0][4] eq 'bottom', "empty string -> 1 op, valign preserved");
}

# ---------------------------------------------------------------
# 2. halign を widths で座標解決 (単一行)
# ---------------------------------------------------------------
{
    my @r = ml_layout(100, 50, "abcd", align => 'right',  widths => [40]);
    ok(near($r[0][0], 60), "single right: x shifted left by width (100-40=60)");
    ok($r[0][3] eq 'left', "single right: resolved to left anchor");

    my @c = ml_layout(100, 50, "abcd", align => 'center', widths => [40]);
    ok(near($c[0][0], 80), "single center: x shifted left by half width (100-20=80)");

    my @l = ml_layout(100, 50, "abcd", align => 'left',   widths => [40]);
    ok(near($l[0][0], 100), "single left: no shift");
}

# ---------------------------------------------------------------
# 3. 複数行 + 垂直センタリング(middle)  size=10,lsp=1.2 -> LH=12,N=3
# ---------------------------------------------------------------
{
    my @ops = ml_layout(100, 50, "a\nb\nc",
        align => 'left', valign => 'middle', size => 10, line_spacing => 1.2);
    ok(@ops == 3, "3 lines -> 3 ops");
    ok($ops[0][2] eq 'a' && $ops[1][2] eq 'b' && $ops[2][2] eq 'c', "lines split in order");
    ok(near($ops[0][1], 38) && near($ops[1][1], 50) && near($ops[2][1], 62),
        "middle: lines centred on anchor (38,50,62)");
    ok(near($ops[1][1] - $ops[0][1], 12) && near($ops[2][1] - $ops[1][1], 12),
        "middle: even line spacing = size*line_spacing = 12");
    ok((grep { $_->[4] eq 'middle' } @ops) == 3, "multi: each line drawn valign=middle");
    ok((grep { $_->[3] eq 'left' } @ops) == 3, "multi: each op left-anchored");
    ok((grep { $_->[0] == 100 } @ops) == 3, "angle=0,left: x anchor unchanged for all lines");
}

# ---------------------------------------------------------------
# 4. valign top / bottom  LH=12,N=2 -> ブロック全高 24
# ---------------------------------------------------------------
{
    my @top = ml_layout(0, 100, "x\ny", valign => 'top', size => 10, line_spacing => 1.2);
    ok(near($top[0][1], 106) && near($top[1][1], 118),
        "valign=top: block top at anchor (centres 106,118)");
    my @bot = ml_layout(0, 100, "x\ny", valign => 'bottom', size => 10, line_spacing => 1.2);
    ok(near($bot[0][1], 82) && near($bot[1][1], 94),
        "valign=bottom: block bottom at anchor (centres 82,94)");
    ok(near($top[0][1] - $bot[0][1], 24), "top vs bottom differ by block height (24)");
}

# ---------------------------------------------------------------
# 5. 複数行 halign が行ごとの幅で個別解決される
# ---------------------------------------------------------------
{
    my @r = ml_layout(200, 0, "aa\nbbbb",
        align => 'right', valign => 'middle', widths => [20, 40]);
    ok(near($r[0][0], 180), "multi right: line0 left-x = 200-20 = 180");
    ok(near($r[1][0], 160), "multi right: line1 left-x = 200-40 = 160");
    ok(near($r[0][0] + 20, 200) && near($r[1][0] + 40, 200),
        "multi right: right edges aligned at x=200");

    my @c = ml_layout(200, 0, "aa\nbbbb",
        align => 'center', valign => 'middle', widths => [20, 40]);
    ok(near($c[0][0], 190) && near($c[1][0], 180),
        "multi center: each line centred (200-w/2)");
}

# ---------------------------------------------------------------
# 6. line_spacing
# ---------------------------------------------------------------
{
    my @t = ml_layout(0, 0, "a\nb", size => 10, line_spacing => 1.0, valign => 'top');
    my @l = ml_layout(0, 0, "a\nb", size => 10, line_spacing => 2.0, valign => 'top');
    ok(near($t[1][1] - $t[0][1], 10), "line_spacing=1.0 -> gap 10");
    ok(near($l[1][1] - $l[0][1], 20), "line_spacing=2.0 -> gap 20");
}

# ---------------------------------------------------------------
# 7. 回転 angle=90: 行が横並び(同一 screen-y)、左揃え(widths 無し)
# ---------------------------------------------------------------
{
    my @ops = ml_layout(200, 300, "a\nb", angle => 90, valign => 'middle',
        size => 10, line_spacing => 1.2);   # dy = -6,+6
    ok(near($ops[0][1], 300) && near($ops[1][1], 300),
        "angle=90: all lines share screen-y (horizontal stacking)");
    ok(near($ops[0][0], 194) && near($ops[1][0], 206),
        "angle=90: lines separate along x by line height (194,206)");
    ok((grep { $_->[5] == 90 } @ops) == 2, "angle passed through to each op");
}

# ---------------------------------------------------------------
# 8. ml_max_width / estimate_max_line_px
# ---------------------------------------------------------------
{
    my $cb = sub { length($_[0]) * 6 };
    ok(ml_max_width("Fp1\n(4 uV)", $cb) == 6 * 6, "ml_max_width: longest line '(4 uV)' = 36");
    ok(ml_max_width("", $cb) == 0, "ml_max_width: empty -> 0");
    ok(ml_max_width("x\ny", sub { die "boom" }) == 0, "ml_max_width: width_cb failure -> 0");

    ok(near(estimate_max_line_px("Fp1\n(4 uV)", 10), 6 * 6.2),
        "estimate: longest line '(4 uV)'=6ch * 10 * 0.62");
    ok(estimate_max_line_px("", 10) == 0, "estimate: empty -> 0");
    ok(estimate_max_line_px("abcd", 14) > estimate_max_line_px("abcd", 7),
        "estimate: scales with font size");
    ok(near(estimate_max_line_px("T7\n(250 uV)", 10), 8 * 6.2),
        "estimate: multi-line dominated by longest line");
}

# ---------------------------------------------------------------
# 9. MockBackend 経由の _text_ml 相当: 幅実測 → ml_layout(widths) → 左アンカー
# ---------------------------------------------------------------
{
    package MockBackend;
    sub new { bless { calls => [], cw => $_[1] // 6 }, $_[0] }
    sub text {
        my ($self, $x, $y, $str, %o) = @_;
        push @{$self->{calls}}, { x => $x, y => $y, str => $str, %o };
    }
    sub text_width { length($_[1]) * $_[0]->{cw} }
}
# Axes::_text_ml の本質を最小再現するローカル sub
sub emit {
    my ($b, $x, $y, $str, %opt) = @_;
    my $align = $opt{align} // 'left';
    my $widths;
    if ($align ne 'left') {
        my @lines = split /\n/, (defined $str ? $str : ''), -1;
        $widths = [ map { eval { $b->text_width($_) } // 0 } @lines ];
    }
    for my $op (ml_layout($x, $y, $str, %opt, widths => $widths)) {
        my ($sx, $sy, $line, $al, $va, $ang) = @$op;
        $b->text($sx, $sy, $line, align => $al, valign => $va, angle => $ang);
    }
}
{
    my $b = MockBackend->new(6);   # 6px/char
    emit($b, 10, 20, "row1\nrow22\nrow333",
        align => 'right', valign => 'middle', size => 10, line_spacing => 1.2);
    ok(@{$b->{calls}} == 3, "integration: 3-line label -> 3 backend text() calls");
    ok((grep { $_->{align} eq 'left' } @{$b->{calls}}) == 3,
        "integration: backend always receives align=left (Xlib-safe)");
    ok(near($b->{calls}[0]{x}, 10 - 24)
     && near($b->{calls}[1]{x}, 10 - 30)
     && near($b->{calls}[2]{x}, 10 - 36),
        "integration: right-align resolved per-line via measured width");
    ok(near($b->{calls}[0]{x} + 24, 10)
     && near($b->{calls}[2]{x} + 36, 10),
        "integration: all right edges aligned at anchor x=10");

    my $b2 = MockBackend->new(6);
    emit($b2, 10, 20, "solo", align => 'left', valign => 'bottom');
    ok(@{$b2->{calls}} == 1 && near($b2->{calls}[0]{x}, 10)
       && $b2->{calls}[0]{valign} eq 'bottom',
        "integration: single left -> 1 call, no shift, valign preserved");
}

# ---------------------------------------------------------------
# 10. 実ユースケース回帰: read_nihonkohden の Y軸2行ラベル
# ---------------------------------------------------------------
{
    my $b = MockBackend->new(5);   # ~5px/char
    emit($b, 72, 200, "Fp1\n(4 uV)",
        align => 'right', valign => 'middle', size => 7, line_spacing => 1.2);
    ok(@{$b->{calls}} == 2, "EEG y-label: two lines");
    ok((grep { $_->{align} eq 'left' } @{$b->{calls}}) == 2,
        "EEG y-label: emitted left-anchored (Xlib-safe)");
    ok(near($b->{calls}[0]{x} + 3*5, 72) && near($b->{calls}[1]{x} + 6*5, 72),
        "EEG y-label: right edges aligned at x=72 (right-justified)");
    ok(near(($b->{calls}[0]{y} + $b->{calls}[1]{y}) / 2, 200),
        "EEG y-label: block centred on tick y");
}

print "1..$N\n";
if ($FAIL) { warn "\nFAILED $FAIL/$N\n"; exit 1 }
else       { warn "\nAll $N tests passed.\n"; exit 0 }
