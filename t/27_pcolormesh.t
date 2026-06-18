use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

# ------------------------------------------------------------------
# pcolormesh(): キューに正しく積まれること
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $x = pdl(0,1,2,3);       # セル境界4点 → セル数3(x方向)
    my $y = pdl(0,1,2);         # セル境界3点 → セル数2(y方向)
    # contourf等の既存テストと同じ慣習: $z->at($r,$c) で次元0=y方向,
    # 次元1=x方向となるよう、sequenceから(y方向セル数, x方向セル数)
    # の形状を作る。x=4点→3cell(x方向), y=3点→2cell(y方向)なので
    # 次元0=2(y), 次元1=3(x)。
    my $z = sequence(2, 3);
    $ax->pcolormesh($x, $y, $z);

    my $cmd = $ax->_queue->[-1];
    is $cmd->{type}, 'pcolormesh', 'pcolormesh queued with correct type';
}

# ------------------------------------------------------------------
# pcolor(): pcolormeshの別名として動作すること
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $x = pdl(0,1,2,3);
    my $y = pdl(0,1,2);
    my $z = sequence(2, 3);  # 次元0=2(y方向セル数), 次元1=3(x方向セル数)
    $ax->pcolor($x, $y, $z);

    my $cmd = $ax->_queue->[-1];
    is $cmd->{type}, 'pcolormesh', 'pcolor() is an alias for pcolormesh()';
}

# ------------------------------------------------------------------
# vmin/vmax未指定時はzのmin/maxが使われること
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $x = pdl(0,1,2);
    my $y = pdl(0,1,2);
    my $z = pdl(2,5,8,3)->reshape(2,2);
    $ax->pcolormesh($x, $y, $z);

    my $cmd = $ax->_queue->[-1];
    is $cmd->{vmin}, 2, 'vmin defaults to z->min';
    is $cmd->{vmax}, 8, 'vmax defaults to z->max';
}

# ------------------------------------------------------------------
# colorbar連携: imshow/contourfと同じ仕組みでcolorbarが使えること
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $x = pdl(0,1,2,3);
    my $y = pdl(0,1,2);
    my $z = sequence(2, 3);  # 次元0=2(y方向セル数), 次元1=3(x方向セル数)
    $ax->pcolormesh($x, $y, $z, cmap=>'viridis');
    $ax->colorbar(label=>'value');

    ok $ax->_colorbar, 'pcolormesh sets up _colorbar like imshow/contourf';
    is $ax->colorbar_label, 'value', 'colorbar(label=>...) works after pcolormesh';
}

# ------------------------------------------------------------------
# 均一グリッドでのPNG描画がクラッシュしないこと(基本ケース)
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $x = sequence(11);  # 0..10, セル境界11点 → セル数10
    my $y = sequence(9);   # 0..8,  セル境界9点  → セル数8
    my $z = sequence(8,10);  # 次元0=8(y方向セル数), 次元1=10(x方向セル数)。
                              # at($r,$c)はr<8(次元0), c<10(次元1)で
                              # アクセスするため、この順序でないと
                              # 次元1の範囲外アクセスでdieする。
    $ax->pcolormesh($x, $y, $z, cmap=>'plasma');
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'pcolormesh uniform grid renders without crashing' or diag "error: $@";
}

# ------------------------------------------------------------------
# 不均一グリッドでのPNG描画がクラッシュしないこと
# (imshowでは表現できない、pcolormeshの本来の用途)
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    # 不等間隔なセル境界(対数的に間隔が広がる)
    my $x = pdl(0, 1, 3, 7, 15, 31);     # 5セル(x方向)、間隔1,2,4,8,16
    my $y = pdl(0, 1, 2, 4, 8);          # 4セル(y方向)、間隔1,1,2,4
    my $z = sequence(4, 5);              # 次元0=4(y方向セル数), 次元1=5(x方向セル数)
    $ax->pcolormesh($x, $y, $z, cmap=>'viridis');
    $ax->set_title('uneven grid pcolormesh');
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'pcolormesh non-uniform grid renders without crashing' or diag "error: $@";
}

# ------------------------------------------------------------------
# z が境界点と同じ形状(簡易指定)で渡されてもクラッシュしないこと
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $x = sequence(5);   # セル境界5点 → セル数4(x方向)
    my $y = sequence(4);   # セル境界4点 → セル数3(y方向)
    # z を厳密なセル数(3,4)=(次元0:3(y), 次元1:4(x))ではなく、
    # 境界点と同じ(次元0:4(yの境界点数), 次元1:5(xの境界点数))で
    # 渡す簡易指定。at($r,$c)はr<3(次元0の範囲内), c<4(次元1の範囲内)
    # しか使わないので、この余裕のある形状でもクラッシュしない。
    my $z = sequence(4, 5);
    eval { $ax->pcolormesh($x, $y, $z); $fig->tight_layout; $fig->to_png };
    ok !$@, 'pcolormesh with boundary-shaped z does not crash' or diag "error: $@";
}

done_testing;
