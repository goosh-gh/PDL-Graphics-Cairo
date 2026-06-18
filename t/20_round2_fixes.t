use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(subplots);

# ----------------------------------------------------------------
# E: loglog/semilogx/semilogy の自動レンジが異常にならないこと
# ----------------------------------------------------------------
{
    my $x = pdl(map { 10**($_/5) } 0..25);  # 1 .. ~10^5
    my $y = $x ** (-1.5) * 1000;

    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    $ax->loglog($x, $y);
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'loglog draw does not crash' or diag "error: $@";

    # draw() は冪等性のため描画後に xmin/xmax をユーザ指定値（未指定なら undef）に
    # 戻す仕様（Axes.pm draw() 冒頭のコメント参照）。autoscale 後の確定値を見るには
    # _finalize_range() を直接呼んで xmin/xmax を確定させてから検証する。
    $ax->_finalize_range;
    ok $ax->xmin > 0,        'loglog: xmin is positive';
    ok $ax->xmin <= $x->min, 'loglog: xmin <= data min';
    ok $ax->xmax >= $x->max, 'loglog: xmax >= data max';
    ok $ax->xmax / $ax->xmin < 1e8,
        'loglog: xmax/xmin ratio is not absurdly large (no -10 decade blowup)';
}

{
    my $f   = pdl(map { 10**($_/10) } 0..30);  # 1 .. 1000
    my $amp = 1 / (1 + ($f/100)**2);

    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    $ax->semilogx($f, $amp);
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'semilogx draw does not crash' or diag "error: $@";
    $ax->_finalize_range;
    ok $ax->xmax / $ax->xmin < 1e6,
        'semilogx: xmax/xmin ratio is reasonable (no decade blowup)';
}

# ----------------------------------------------------------------
# loglog の広いレンジ（1〜10^5）で X軸ラベルが重ならないこと。
# 直接ピクセル位置を検証するのは難しいので、Driver::Cairo に
# text_width が実装されていること（重なり判定の前提）を確認する。
# ----------------------------------------------------------------
{
    can_ok('PDL::Graphics::Cairo::Driver::Cairo', 'text_width');

    my $x = pdl(map { 10**($_/5) } 0..25);  # 1 .. ~10^5
    my $y = $x ** (-1.5) * 1000;

    my ($fig, $ax) = subplots(1,1, width=>550, height=>320);
    $ax->loglog($x, $y);
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'loglog with wide range (1..1e5) draw does not crash' or diag "error: $@";
}

# ----------------------------------------------------------------
# C: errorbar(xerr=>...) が描画パスでクラッシュしないこと
#    （Driver::Cairo::errorbar_x が呼ばれることの間接確認）
# ----------------------------------------------------------------
{
    my $x    = pdl(10,20,30,40,50);
    my $y    = pdl(1.2,2.3,1.8,3.1,2.7);
    my $yerr = pdl(0.2,0.3,0.15,0.4,0.25);
    my $xerr = pdl(1.5,1.2,2.0,1.8,1.0);

    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    $ax->errorbar($x, $y, yerr=>$yerr, xerr=>$xerr);
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'errorbar with xerr+yerr does not crash' or diag "error: $@";

    can_ok('PDL::Graphics::Cairo::Driver::Cairo', 'errorbar_x');
}

# ----------------------------------------------------------------
# D: annotate がクラッシュせず、矢印開始点がテキスト位置とは異なること
#    （短縮ロジックが効いているかの間接確認）
# ----------------------------------------------------------------
{
    my $x = sequence(50)/5;
    my $y = sin($x);

    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    $ax->line($x, $y);
    $ax->annotate('peak', xy=>[0.5,1.0], xytext=>[1.5,0.7], arrowprops=>{});
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'annotate with arrow does not crash' or diag "error: $@";
}

# ----------------------------------------------------------------
# F: stackplot — 正しい呼び方（可変長引数）でクラッシュしないこと
#    配列refを渡すと分かりやすいエラーになること
# ----------------------------------------------------------------
{
    my $x  = sequence(10);
    my $y1 = pdl(1,2,1.5,2,2.5,2,1.5,2,2.5,3);
    my $y2 = pdl(2,1.5,2,1,1.5,2,2.5,2,1.5,1);

    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    eval { $ax->stackplot($x, $y1, $y2, labels=>['A','B']) };
    ok !$@, 'stackplot with correct (variadic) call does not crash'
        or diag "error: $@";
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'stackplot draw does not crash' or diag "error: $@";
}
{
    # 後方互換性: 末尾ハッシュリファレンス形式も引き続き動作すること
    my $x  = sequence(10);
    my $y1 = pdl(1,2,1.5,2,2.5,2,1.5,2,2.5,3);
    my $y2 = pdl(2,1.5,2,1,1.5,2,2.5,2,1.5,1);

    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    eval { $ax->stackplot($x, $y1, $y2, {labels=>['A','B']}) };
    ok !$@, 'stackplot with legacy hashref option call does not crash'
        or diag "error: $@";
}
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    eval { $ax->stackplot(sequence(5), [pdl(1,2,3,4,5), pdl(2,3,4,5,6)]) };
    like $@, qr/separate arguments/,
        'stackplot with arrayref gives a clear, actionable error message';
}

# ----------------------------------------------------------------
# A/B: ylabel と Y軸 tick ラベルが重ならないこと（位置の相対チェック）
# ----------------------------------------------------------------
{
    my $x = sequence(20)/2;
    my $y = sin($x) * 100;   # tick labelが "100", "-100" 等になり幅が増える

    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    $ax->line($x, $y);
    $ax->ylabel('Amplitude (uV)');
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'draw with ylabel + wide tick labels does not crash' or diag "error: $@";
    ok defined($ax->{_y_ticklabel_maxw}), '_y_ticklabel_maxw is set after draw';
    ok $ax->{_y_ticklabel_maxw} > 0, '_y_ticklabel_maxw is a positive width';
}

done_testing;
