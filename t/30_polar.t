use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots style);

style('default');

my $pi = 3.14159265358979;

# ============================================================
# 1. 基本的な polar plot
# ============================================================
{
    my $theta = sequence(200) / 200 * 2 * $pi;
    my $r     = sin(2*$theta)**2;

    my $fig = figure(width=>500, height=>500);
    my $ax  = $fig->add_subplot(1,1,1, projection=>'polar');

    isa_ok($ax, 'PDL::Graphics::Cairo::PolarAxes', 'add_subplot(polar) returns PolarAxes');

    $ax->plot($theta, $r, color=>'steelblue', lw=>2, label=>'sin²(2θ)');
    $ax->set_title('Rose Curve');
    $ax->legend();
    $fig->tight_layout();
    $fig->save('/tmp/test_polar_basic.png');
    ok(-f '/tmp/test_polar_basic.png', 'polar plot: save ok');
}

# ============================================================
# 2. polar scatter
# ============================================================
{
    my $theta = sequence(20) / 20 * 2 * $pi;
    my $r     = grandom(20)->abs + 0.5;

    my $fig = figure(width=>500, height=>500);
    my $ax  = $fig->add_subplot(1,1,1, projection=>'polar');
    $ax->scatter($theta, $r, color=>'red', s=>16, label=>'random');
    $ax->legend();
    $fig->tight_layout();
    $fig->save('/tmp/test_polar_scatter.png');
    ok(-f '/tmp/test_polar_scatter.png', 'polar scatter: save ok');
}

# ============================================================
# 3. polar bar (rose diagram)
# ============================================================
{
    my $n     = 8;
    my $theta = sequence($n) / $n * 2 * $pi;
    my $r     = pdl(3, 1.5, 4, 2, 5, 3.5, 2, 1);

    my $fig = figure(width=>500, height=>500);
    my $ax  = $fig->add_subplot(1,1,1, projection=>'polar');
    $ax->bar($theta, $r,
        color => 'steelblue',
        alpha => 0.7,
        label => 'wind speed',
    );
    $ax->set_title('Rose Diagram');
    $fig->tight_layout();
    $fig->save('/tmp/test_polar_bar.png');
    ok(-f '/tmp/test_polar_bar.png', 'polar bar: save ok');
}

# ============================================================
# 4. theta_zero=N, direction=-1 (方位角/コンパス)
# ============================================================
{
    my $theta = sequence(200) / 200 * 2 * $pi;
    my $r     = (1 + cos($theta)) * 2;

    my $fig = figure(width=>500, height=>500);
    my $ax  = $fig->add_subplot(1,1,1, projection=>'polar');
    $ax->set_theta_zero_location('N');
    $ax->set_theta_direction(-1);
    $ax->plot($theta, $r, color=>'darkorange', lw=>2);
    $ax->set_title('Compass (N=0, clockwise)');
    $fig->tight_layout();
    $fig->save('/tmp/test_polar_compass.png');
    ok(-f '/tmp/test_polar_compass.png', 'polar compass: save ok');
}

# ============================================================
# 5. set_rmax / set_rticks
# ============================================================
{
    my $theta = sequence(100) / 100 * 2 * $pi;
    my $r     = abs(sin($theta) * 3);

    my $fig = figure(width=>500, height=>500);
    my $ax  = $fig->add_subplot(1,1,1, projection=>'polar');
    $ax->plot($theta, $r, color=>'purple');
    $ax->set_rmax(4);
    $ax->set_rticks([1, 2, 3, 4]);
    $ax->set_title('Custom rmax/rticks');
    $fig->tight_layout();
    $fig->save('/tmp/test_polar_rmax.png');
    ok(-f '/tmp/test_polar_rmax.png', 'polar rmax/rticks: save ok');
}

# ============================================================
# 6. fill (閉じた塗りつぶし)
# ============================================================
{
    my $theta = sequence(100) / 100 * 2 * $pi;
    my $r     = (sin(3*$theta))->abs + 0.3;

    my $fig = figure(width=>500, height=>500);
    my $ax  = $fig->add_subplot(1,1,1, projection=>'polar');
    $ax->fill($theta, $r, color=>'green', alpha=>0.4);
    $ax->plot($theta, $r, color=>'darkgreen', lw=>1.5);
    $ax->set_title('Polar Fill');
    $fig->tight_layout();
    $fig->save('/tmp/test_polar_fill.png');
    ok(-f '/tmp/test_polar_fill.png', 'polar fill: save ok');
}

# ============================================================
# 7. EEG/神経科学: 方向チューニングカーブ (typical use case)
# ============================================================
{
    # 8方向の選好性チューニングカーブ（ガウシアン）
    my $n      = 64;
    my $theta  = sequence($n) / $n * 2 * $pi;
    my $pref   = $pi / 4;   # 45度に選好性
    my $sigma  = 0.6;
    my $r_raw  = exp(-0.5 * (($theta - $pref) / $sigma)**2);

    my $fig = figure(width=>500, height=>500);
    my $ax  = $fig->add_subplot(1,1,1, projection=>'polar');
    $ax->plot($theta, $r_raw, color=>'steelblue', lw=>2, label=>'tuning');
    $ax->fill($theta, $r_raw, color=>'steelblue', alpha=>0.2);
    $ax->set_rmax(1.1);
    $ax->set_theta_zero_location('N');
    $ax->set_title('Direction Tuning Curve');
    $ax->legend();
    $fig->tight_layout();
    $fig->save('/tmp/test_polar_tuning.png');
    ok(-f '/tmp/test_polar_tuning.png', 'polar tuning curve: save ok');
}

# ============================================================
# 8. stacked bar (bottom=>PDL配列) — 積み上げ風配図の回帰テスト
#   2026-06-19: bottom がスカラーのみ対応で、PDL配列(方位ごとに
#   異なる積み上げ底辺)を渡すと描画位置が破綻するバグを修正。
# ============================================================
{
    my $n     = 6;
    my $theta = sequence($n) / $n * 2 * $pi;
    my $bin1  = pdl(3, 2, 4, 5, 3, 2);
    my $bin2  = pdl(2, 3, 2, 1, 4, 3);

    my $fig = figure(width=>500, height=>500);
    my $ax  = $fig->add_subplot(1,1,1, projection=>'polar');

    # 1段目: bottom=>0(デフォルト)
    $ax->bar($theta, $bin1, color=>'steelblue', label=>'bin1');
    # 2段目: bottom=>$bin1 (PDL配列、方位ごとに異なる積み上げ底辺)
    $ax->bar($theta, $bin2, bottom=>$bin1, color=>'darkorange', label=>'bin2');

    $ax->set_title('Stacked bar regression test');
    $ax->legend();
    $fig->tight_layout();
    $fig->save('/tmp/test_polar_stacked_bar.png');
    ok(-f '/tmp/test_polar_stacked_bar.png', 'polar stacked bar (bottom=>PDL): save ok');

    # rmax が bottom+r の最大値(積み上げ後の最大値)に正しく拡張されて
    # いることを確認する。bin1+bin2の最大は (5+1)=6 or (4+2)=6 等。
    my $expected_max = ($bin1 + $bin2)->max;
    ok($ax->_rmax >= $expected_max,
        "stacked bar: rmax(${\ $ax->_rmax}) accounts for bottom+r (expected >= $expected_max)");
}

done_testing();
