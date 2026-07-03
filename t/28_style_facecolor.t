use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots style rcParams);

my $x = sequence(50) / 5;

# ============================================================
# 1. style.use() — ggplot スタイル
# ============================================================
{
    style('ggplot');
    my $fc = rcParams('axes.facecolor');
    is($fc, '#E5E5E5', 'style.use(ggplot): axes.facecolor');

    # 描画確認
    my ($fig, $ax) = subplots(width=>400, height=>300);
    $ax->plot($x, sin($x), label=>'sin');
    $ax->legend();
    $fig->tight_layout();
    $fig->save('/tmp/test_ggplot.png');
    ok(-f '/tmp/test_ggplot.png', 'ggplot style: save ok');
}

# ============================================================
# 2. style.use() — dark_background スタイル
# ============================================================
{
    style('dark_background');
    my $fc = rcParams('axes.facecolor');
    is($fc, '#121212', 'style.use(dark_background): axes.facecolor');
    my ($fig, $ax) = subplots(width=>400, height=>300);
    $ax->plot($x, cos($x), color=>'#8dd3c7');
    $fig->tight_layout();
    $fig->save('/tmp/test_dark.png');
    ok(-f '/tmp/test_dark.png', 'dark_background style: save ok');
}

# ============================================================
# 3. style.use('default') — デフォルトに戻す
# ============================================================
{
    style('default');
    my $fc = rcParams('axes.facecolor');
    is($fc, 'white', 'style.use(default): axes.facecolor reset');
}

# ============================================================
# 4. style->available() で一覧取得
# ============================================================
{
    my @avail = PDL::Graphics::Cairo::Style->available();
    ok(scalar(@avail) >= 5, 'style->available() returns >= 5 styles');
    ok((grep { $_ eq 'ggplot' } @avail), 'ggplot in available');
    ok((grep { $_ eq 'seaborn' } @avail), 'seaborn in available');
}

# ============================================================
# 5. rcParams('font.family') でフォント設定
# ============================================================
{
    style('default');
    rcParams('font.family' => 'Sans');
    is(rcParams('font.family'), 'Sans', 'rcParams font.family set');
    my ($fig, $ax) = subplots(width=>400, height=>300);
    $ax->plot($x, sin($x));
    $ax->set_title('Sans Font Test');
    $fig->tight_layout();
    $fig->save('/tmp/test_font.png');
    ok(-f '/tmp/test_font.png', 'custom font: save ok');
    rcParams('font.family' => 'Helvetica Neue');  # 戻す
}

# ============================================================
# 6. ax.set_facecolor()
# ============================================================
{
    style('default');
    my ($fig, $ax) = subplots(width=>400, height=>300);
    $ax->set_facecolor('#EAEAF2');
    $ax->plot($x, sin($x));
    $ax->grid(1);
    $fig->tight_layout();
    $fig->save('/tmp/test_facecolor.png');
    ok(-f '/tmp/test_facecolor.png', 'set_facecolor: save ok');
}

done_testing();
