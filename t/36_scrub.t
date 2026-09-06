use strict;
use warnings;
use Test::More;
use PDL::Lite;
use PDL;
use lib 'lib';
use PDL::Graphics::Cairo::Interactive::Scrub qw(nearest_on_line nearest_on_lines clamp);

# ---- clamp ----------------------------------------------------------
is(clamp(5, 0, 10), 5, 'clamp inside');
is(clamp(-3, 0, 10), 0, 'clamp low');
is(clamp(99, 0, 10), 10, 'clamp high');

# ---- nearest_on_line: x-only snap (scrubber) ------------------------
# ERP 風の潜時軸 0..100ms を 1ms 刻み、値は既知の関数。
my $x = sequence(101);            # 0..100
my $y = sin($x / 10);             # 任意のトレース
{
    my ($i, $xa, $ya) = nearest_on_line($x, $y, 37.2, undef, 100, 2);
    is($i, 37, 'x-only: nearest index to 37.2 is 37');
    is($xa, 37, 'x-only: x_at is 37');
    ok(abs($ya - sin(3.7)) < 1e-9, 'x-only: y_at is trace value at 37');
}
{   # ちょうど中間 (37.5) は下側 37 に落ちる（minimum_ind の最初のヒット）
    my ($i) = nearest_on_line($x, $y, 37.5, undef, 100, 2);
    ok($i == 37 || $i == 38, 'x-only: 37.5 snaps to an adjacent sample');
}

# ---- nearest_on_line: レンジ正規化が最近傍の選択を左右すること --------
# 同じクエリ (480,0) で、x レンジ(xr)だけ変えると選ばれる点が入れ替わる
# ことを確認する（= x と y が正規化後に比較されている証拠）。
{
    my $xx = pdl(0, 500, 1000);
    my $yy = pdl(0, 0.9, 0);      # 真ん中だけ y が高い
    # xr=1000: y の差(0.9)が支配 → x=0,y=0 の点0 が最近傍
    my ($i_wide) = nearest_on_line($xx, $yy, 480, 0.0, 1000, 1);
    is($i_wide, 0, 'wide xr: y gap dominates, picks x=0 sample');
    # xr=50: x を強く効かせる → x=500 の点1 に入れ替わる
    my ($i_tight) = nearest_on_line($xx, $yy, 480, 0.0, 50, 1);
    is($i_tight, 1, 'tight xr: x weighting flips choice to x=500 sample');
}
{
    # 正規化しない素の距離だと y=0.9 が効いて別の点を選ぶ状況を、
    # レンジを y 側だけ極端にして再現 → yr を大きくすると y 差が薄まる
    my $xx = pdl(0, 10, 20);
    my $yy = pdl(0, 5, 0);
    my ($i_small) = nearest_on_line($xx, $yy, 10, 0, 20, 100); # yr大→y無視
    is($i_small, 1, 'large yr makes y difference negligible');
}

# ---- nearest_on_lines: 複数ライン横断 -------------------------------
{
    my $l0 = { x => pdl(0,1,2,3), y => pdl(0,0,0,0) };
    my $l1 = { x => pdl(0,1,2,3), y => pdl(9,9,9,9) };
    # クエリ y=8.5 → line1 が近い
    my ($li, $pi, $xa, $ya) = nearest_on_lines([$l0,$l1], 2.1, 8.5, 3, 9);
    is($li, 1, 'multi-line: picks the closer line (upper)');
    is($pi, 2, 'multi-line: picks nearest x sample on that line');
    is($ya, 9, 'multi-line: y_at correct');
}

# ---- 空ライン / 空リストの安全性 ------------------------------------
{
    my @r = nearest_on_line(pdl([]), pdl([]), 1, 1, 1, 1);
    is(scalar(@r), 0, 'empty line returns empty list');
    my @r2 = nearest_on_lines([], 1, 1, 1, 1);
    is(scalar(@r2), 0, 'empty list returns empty list');
    # x のみのラインが混ざっても落ちない
    my ($li) = nearest_on_lines([{x=>pdl(1,2),y=>pdl(3,4)}], 1.9, undef, 1, 1);
    is($li, 0, 'x-only across lines works');
}

done_testing();
