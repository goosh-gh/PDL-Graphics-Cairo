use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(subplots);

# ----------------------------------------------------------------
# set_xticklabels(rotation=>N) — 既存動作の確認（regression guard）
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->set_xticklabels(['a','b','c'], rotation=>45);
    is $ax->{_xtick_rot}, 45, 'set_xticklabels stores rotation in _xtick_rot';
}

# ----------------------------------------------------------------
# set_yticklabels(rotation=>N) — 新規対応（このパッチで追加）
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->set_yticklabels(['lo','mid','hi'], rotation=>30);
    is $ax->{_ytick_rot}, 30, 'set_yticklabels stores rotation in _ytick_rot';
}

# ----------------------------------------------------------------
# rotation省略時はデフォルト0（x/y対称）
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->set_xticklabels(['a','b']);
    $ax->set_yticklabels(['c','d']);
    is $ax->{_xtick_rot}, 0, 'set_xticklabels defaults rotation to 0';
    is $ax->{_ytick_rot}, 0, 'set_yticklabels defaults rotation to 0';
}

# ----------------------------------------------------------------
# tick_params(y_labelrotation) が _ytick_rot より優先される
# （x側の既存フォールバック順 x_labelrotation // _xtick_rot // 0 と対称）
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->set_yticklabels(['c','d'], rotation=>30);
    $ax->tick_params(axis=>'y', labelrotation=>60);
    my $tp = $ax->_tick_params;
    is $tp->{y_labelrotation}, 60, 'tick_params(labelrotation) overrides set_yticklabels rotation value';
    is $ax->{_ytick_rot}, 30, 'set_yticklabels rotation value itself unchanged (still available as fallback)';
}

# ----------------------------------------------------------------
# draw() がクラッシュしないことの確認（実際の描画パス）
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->line(pdl(0..4), pdl(1,4,2,5,3));
    $ax->yticks([1,2,3,4,5], ['Low','Mid-low','Mid','Mid-high','High']);
    $ax->set_yticklabels(['Low','Mid-low','Mid','Mid-high','High'], rotation=>45);
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'draw with set_yticklabels(rotation=>45) does not crash'
        or diag "error: $@";
}

done_testing;
