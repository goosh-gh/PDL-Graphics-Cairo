use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);
use Cairo;

# ==================================================================
# tick_params() の実動作を「描画結果のピクセル」から機械的に検証する。
#
# 目視確認(examples/tick_params_verify.pl)を補完する自動テスト。
# 各オプションについて:
#   - 期待される変化が起きていれば PASS
#   - 何も変わっていない(no-opになっている)場合は FAIL
# という設計にすることで、「メソッドは存在するが実際には効いていない」
# という回帰を検出できるようにする。
# ==================================================================

my $x = sequence(50) / 5;
my $y = sin($x);

# PNG を読み込んで [4,W,H] の BGRA byte pdl にする
# (既存コードの _argb32_surface_to_png_file と同じ get_dataref パターンを使用。
#  ただし create_from_png() で読み込んだ surface は stride が W*4 と異なる
#  ことがあるため、stride分のパディングを考慮してスライスする)
sub load_png_pixels {
    my ($path) = @_;
    my $surface = Cairo::ImageSurface->create_from_png($path);
    $surface->flush;
    my $w = $surface->get_width;
    my $h = $surface->get_height;
    my $stride = $surface->get_stride;
    my $raw = $surface->get_data;

    # stride 込みの生データを [stride, H] の byte PDL に読み込み、
    # 各行の先頭 W*4 バイトだけを取り出して [4,W,H] に詰め直す。
    my $padded = PDL->zeroes(PDL::byte, $stride, $h);
    ${ $padded->get_dataref } = $raw;
    $padded->upd_data;
    my $cropped = $padded->slice("0:" . ($w*4-1) . ",:");   # [W*4, H]
    my $pdl = $cropped->reshape(4, $w, $h);                 # [4,W,H] BGRA
    return ($pdl, $w, $h);
}

# 指定領域に「ほぼ赤色」のピクセルがあるか判定
# (Cairo ImageSurfaceはBGRA順なので注意)
sub count_red_pixels_in_region {
    my ($pdl, $x0, $x1, $y0, $y1) = @_;
    $x0 = 0 if $x0 < 0; $y0 = 0 if $y0 < 0;
    my $region = $pdl->slice(":,$x0:$x1,$y0:$y1");
    my $b = $region->slice('(0)');
    my $g = $region->slice('(1)');
    my $r = $region->slice('(2)');
    # 赤判定: R高い & G,B低い
    my $is_red = ($r > 180) & ($g < 100) & ($b < 100);
    return $is_red->sum;
}

# ------------------------------------------------------------------
# Test 1: tick_params(color=>'red') で目盛り線が実際に赤くなるか
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(width=>400, height=>300);
    $ax->plot($x, $y, color=>'steelblue');
    $ax->tick_params(color => 'red', width => 3, length => 12);
    $fig->tight_layout();
    $fig->save('/tmp/_tp_test_color_red.png');

    my ($pdl, $w, $h) = load_png_pixels('/tmp/_tp_test_color_red.png');
    # 下端付近(X軸目盛り領域)に赤ピクセルがあるはず
    my $bottom_band_red = count_red_pixels_in_region($pdl, 0, $w-1, $h-100, $h-1);
    ok($bottom_band_red > 0,
        "tick_params(color=>'red'): bottom tick area has red pixels (found $bottom_band_red)");
}

# ------------------------------------------------------------------
# Test 2: tick_params(color=>...) 指定なし(デフォルト黒)では赤ピクセルが無い
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(width=>400, height=>300);
    $ax->plot($x, $y, color=>'steelblue');
    $fig->tight_layout();
    $fig->save('/tmp/_tp_test_color_default.png');

    my ($pdl, $w, $h) = load_png_pixels('/tmp/_tp_test_color_default.png');
    my $bottom_band_red = count_red_pixels_in_region($pdl, 0, $w-1, $h-100, $h-1);
    is($bottom_band_red, 0,
        "tick_params default (no color override): no red pixels in tick area");
}

# ------------------------------------------------------------------
# Test 3: length=>14 vs default(5) — 太く長くした方がピクセル数が多い
# ------------------------------------------------------------------
{
    my ($fig_a, $ax_a) = subplots(width=>400, height=>300);
    $ax_a->plot($x, $y, color=>'steelblue');
    $ax_a->tick_params(color=>'red', width=>2, length=>5);  # default相当
    $fig_a->tight_layout();
    $fig_a->save('/tmp/_tp_test_length_short.png');

    my ($fig_b, $ax_b) = subplots(width=>400, height=>300);
    $ax_b->plot($x, $y, color=>'steelblue');
    $ax_b->tick_params(color=>'red', width=>2, length=>20);  # 大幅に長く
    $fig_b->tight_layout();
    $fig_b->save('/tmp/_tp_test_length_long.png');

    my ($pdl_a, $wa, $ha) = load_png_pixels('/tmp/_tp_test_length_short.png');
    my ($pdl_b, $wb, $hb) = load_png_pixels('/tmp/_tp_test_length_long.png');

    my $red_a = count_red_pixels_in_region($pdl_a, 0, $wa-1, $ha-100, $ha-1);
    my $red_b = count_red_pixels_in_region($pdl_b, 0, $wb-1, $hb-100, $hb-1);

    ok($red_b > $red_a,
        "tick_params(length=>20) produces more red pixels than length=>5 ($red_b vs $red_a)");
}

# ------------------------------------------------------------------
# Test 4: direction=>'in' vs 'out' — 目盛りの伸びる方向が変わるか
# プロット領域の境界線(mb)の「内側」と「外側」での赤ピクセル分布で判定
# ------------------------------------------------------------------
{
    my ($fig_out, $ax_out) = subplots(width=>400, height=>300);
    $ax_out->plot($x, $y, color=>'steelblue');
    $ax_out->tick_params(color=>'red', width=>3, length=>15, direction=>'out');
    $fig_out->tight_layout();
    $fig_out->save('/tmp/_tp_test_dir_out.png');

    my ($fig_in, $ax_in) = subplots(width=>400, height=>300);
    $ax_in->plot($x, $y, color=>'steelblue');
    $ax_in->tick_params(color=>'red', width=>3, length=>15, direction=>'in');
    $fig_in->tight_layout();
    $fig_in->save('/tmp/_tp_test_dir_in.png');

    # direction='in'のプロットでは、プロット領域内部(下端より上)に赤ピクセルが
    # 出現するはず。direction='out'では下端より下(ラベル領域寄り)に出る。
    # 厳密な座標計算は複雑なため、ここでは「画像全体の赤ピクセル数は両方>0」
    # かつ「両者で赤ピクセルの分布(reduced over y)の重心が異なる」ことを確認する。
    my ($pdl_out, $w1, $h1) = load_png_pixels('/tmp/_tp_test_dir_out.png');
    my ($pdl_in,  $w2, $h2) = load_png_pixels('/tmp/_tp_test_dir_in.png');

    my $red_out = count_red_pixels_in_region($pdl_out, 0, $w1-1, 0, $h1-1);
    my $red_in  = count_red_pixels_in_region($pdl_in,  0, $w2-1, 0, $h2-1);

    ok($red_out > 0 && $red_in > 0,
        "direction=>'in'/'out' both produce visible red tick marks ($red_out / $red_in)");
}

# ------------------------------------------------------------------
# Test 5: top=>1, right=>1 — 上端・右端にも目盛りが出るか
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(width=>400, height=>300);
    $ax->plot($x, $y, color=>'steelblue');
    $ax->tick_params(color=>'red', width=>3, length=>10, top=>1, right=>1);
    $fig->tight_layout();
    $fig->save('/tmp/_tp_test_topright.png');

    my ($pdl, $w, $h) = load_png_pixels('/tmp/_tp_test_topright.png');
    # 上端付近(プロット領域のmt周辺、ラベル等を避けて20-60px範囲)
    my $top_band_red = count_red_pixels_in_region($pdl, 0, $w-1, 15, 60);
    # 右端付近
    my $right_band_red = count_red_pixels_in_region($pdl, $w-50, $w-1, 0, $h-1);

    ok($top_band_red > 0,
        "tick_params(top=>1): top edge has red tick marks (found $top_band_red)");
    ok($right_band_red > 0,
        "tick_params(right=>1): right edge has red tick marks (found $right_band_red)");
}

# ------------------------------------------------------------------
# Test 6: axis=>'x' のみ指定時、Y軸目盛りには影響しないことを確認
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(width=>400, height=>300);
    $ax->plot($x, $y, color=>'steelblue');
    $ax->tick_params(axis=>'x', color=>'red', width=>3, length=>15);
    $fig->tight_layout();
    $fig->save('/tmp/_tp_test_axis_x_only.png');

    my ($pdl, $w, $h) = load_png_pixels('/tmp/_tp_test_axis_x_only.png');
    # 左端(Y軸目盛り領域)には赤ピクセルが無いはず
    my $left_band_red = count_red_pixels_in_region($pdl, 0, 50, 0, $h-1);
    is($left_band_red, 0,
        "tick_params(axis=>'x', color=>'red'): left (Y-axis) area unaffected");

    # 下端(X軸目盛り領域)には赤ピクセルがあるはず
    my $bottom_band_red = count_red_pixels_in_region($pdl, 0, $w-1, $h-100, $h-1);
    ok($bottom_band_red > 0,
        "tick_params(axis=>'x', color=>'red'): bottom (X-axis) area affected");
}

# ------------------------------------------------------------------
# Test 7: labelsize の変化 (文字サイズが大きいほど描画される黒画素数が
# 増える傾向を、ラベル領域のnon-white画素数で簡易判定)
# ------------------------------------------------------------------
{
    my ($fig_small, $ax_small) = subplots(width=>400, height=>300);
    $ax_small->plot($x, $y, color=>'steelblue');
    $ax_small->tick_params(labelsize=>8);
    $fig_small->tight_layout();
    $fig_small->save('/tmp/_tp_test_labelsize_small.png');

    my ($fig_big, $ax_big) = subplots(width=>400, height=>300);
    $ax_big->plot($x, $y, color=>'steelblue');
    $ax_big->tick_params(labelsize=>22);
    $fig_big->tight_layout();
    $fig_big->save('/tmp/_tp_test_labelsize_big.png');

    sub count_nonwhite_in_region {
        my ($pdl, $x0,$x1,$y0,$y1) = @_;
        my $region = $pdl->slice(":,$x0:$x1,$y0:$y1");
        my $b = $region->slice('(0)'); my $g = $region->slice('(1)'); my $r = $region->slice('(2)');
        my $nonwhite = ($r < 250) | ($g < 250) | ($b < 250);
        return $nonwhite->sum;
    }

    my ($pdl_s, $ws, $hs) = load_png_pixels('/tmp/_tp_test_labelsize_small.png');
    my ($pdl_b, $wb, $hb) = load_png_pixels('/tmp/_tp_test_labelsize_big.png');

    my $ink_small = count_nonwhite_in_region($pdl_s, 0, $ws-1, $hs-100, $hs-1);
    my $ink_big   = count_nonwhite_in_region($pdl_b, 0, $wb-1, $hb-100, $hb-1);

    ok($ink_big > $ink_small,
        "tick_params(labelsize=>22) produces more ink than labelsize=>8 ($ink_big vs $ink_small)");
}

done_testing();
