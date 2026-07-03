use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots style);

style('default');

my $x = sequence(100) / 10;

# ============================================================
# 1. fillstyle='none' — scatter 中抜きマーカー
# ============================================================
{
    my ($fig, $ax) = subplots(width=>400, height=>300);
    $ax->scatter($x->slice('0:19'), sin($x->slice('0:19')),
        fillstyle => 'none',
        marker    => 'o',
        color     => 'blue',
        label     => 'hollow circles',
    );
    $ax->legend();
    $fig->tight_layout();
    $fig->save('/tmp/test_fillstyle_scatter.png');
    ok(-f '/tmp/test_fillstyle_scatter.png', 'fillstyle=none scatter: save ok');
}

# ============================================================
# 2. fillstyle='none' — line + marker 中抜き
# ============================================================
{
    my ($fig, $ax) = subplots(width=>400, height=>300);
    $ax->plot($x->slice('0:19'), cos($x->slice('0:19')),
        marker    => 's',
        fillstyle => 'none',
        color     => 'red',
        label     => 'hollow squares',
    );
    $ax->legend();
    $fig->tight_layout();
    $fig->save('/tmp/test_fillstyle_line.png');
    ok(-f '/tmp/test_fillstyle_line.png', 'fillstyle=none line+marker: save ok');
}

# ============================================================
# 3. fill_between(where=>) — 条件付き塗りつぶし
# ============================================================
{
    my $x2 = sequence(200) / 20;
    my $y1 = sin($x2);
    my $y2 = cos($x2);
    my $mask = ($y1 > $y2);   # PDL boolean

    my ($fig, $ax) = subplots(width=>500, height=>300);
    $ax->plot($x2, $y1, color=>'blue',   label=>'sin');
    $ax->plot($x2, $y2, color=>'orange', label=>'cos');
    $ax->fill_between($x2, $y1, $y2,
        where => $mask,
        color => 'blue',
        alpha => 0.3,
        label => 'sin > cos',
    );
    $ax->legend();
    $ax->set_title('fill_between(where=)');
    $fig->tight_layout();
    $fig->save('/tmp/test_fill_where.png');
    ok(-f '/tmp/test_fill_where.png', 'fill_between(where=): save ok');
}

# ============================================================
# 4. fill_between(where=) — 全True (従来と同じ挙動)
# ============================================================
{
    my ($fig, $ax) = subplots(width=>400, height=>300);
    my $y1 = sin($x->slice('0:49'));
    my $y2 = zeroes(50);
    my $all_true = ones(50)->long;
    $ax->fill_between($x->slice('0:49'), $y1, $y2,
        where => $all_true,
        color => 'green',
        alpha => 0.4,
    );
    $ax->plot($x->slice('0:49'), $y1, color=>'darkgreen');
    $fig->tight_layout();
    $fig->save('/tmp/test_fill_where_all.png');
    ok(-f '/tmp/test_fill_where_all.png', 'fill_between(where=all true): save ok');
}

# ============================================================
# 5. set_position([left,bottom,width,height])
# ============================================================
{
    my $fig = figure(width=>600, height=>400);
    my $ax1 = $fig->axes();
    $ax1->set_position([0.05, 0.1, 0.4, 0.8]);
    $ax1->plot($x->slice('0:19'), sin($x->slice('0:19')), color=>'blue');
    $ax1->set_title('Left');

    my $ax2 = $fig->axes();
    $ax2->set_position([0.55, 0.1, 0.4, 0.8]);
    $ax2->plot($x->slice('0:19'), cos($x->slice('0:19')), color=>'red');
    $ax2->set_title('Right');

    $fig->tight_layout();
    $fig->save('/tmp/test_set_position.png');
    ok(-f '/tmp/test_set_position.png', 'set_position: save ok');
}

# ============================================================
# 6. subplots_adjust
# ============================================================
{
    my ($fig, $ax1, $ax2) = subplots(1, 2, width=>600, height=>300);
    $ax1->plot($x->slice('0:19'), sin($x->slice('0:19')));
    $ax2->plot($x->slice('0:19'), cos($x->slice('0:19')));
    $fig->tight_layout();
    $fig->subplots_adjust(left=>0.08, right=>0.96, wspace=>0.35);
    $fig->save('/tmp/test_subplots_adjust.png');
    ok(-f '/tmp/test_subplots_adjust.png', 'subplots_adjust: save ok');
}

# ============================================================
# 7. savefig(dpi=>192) — 2x解像度
# ============================================================
{
    my ($fig, $ax) = subplots(width=>400, height=>300);
    $ax->plot($x->slice('0:19'), sin($x->slice('0:19')));
    $ax->set_title('HiDPI (2x)');
    $fig->tight_layout();
    $fig->savefig('/tmp/test_hidpi.png', dpi=>192);
    ok(-f '/tmp/test_hidpi.png', 'savefig(dpi=>192): save ok');
    # ファイルサイズが通常の約4倍になるか確認
    my $sz = -s '/tmp/test_hidpi.png';
    $fig->savefig('/tmp/test_normal.png');
    my $sz_n = -s '/tmp/test_normal.png';
    ok($sz > $sz_n, "HiDPI file ($sz) larger than normal ($sz_n)");
}

done_testing();
