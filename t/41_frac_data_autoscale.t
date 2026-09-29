use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);
use Cairo;
use File::Temp qw(tempdir);

# ==================================================================
# image_frac_to_data / data_to_image_frac / get_xlim / get_ylim が、
# draw 後は「実際に描かれた範囲」で答えること。autoscale の軸では描画時に
# データ端の外へ余白が付くので、データ端そのもので換算すると画素位置と
# 読み取り値がずれる(show_grid_scrub の潜時読み取りが端で ±19 ms ずれた)。
# matplotlib の get_xlim も autoscale 後の確定範囲を返す。
#
# 方法: ERP 風の潜時軸 -100..600 ms に、既知の潜時 L で赤の縦線を描く。
# PNG から赤の列重心(画素中心 = i+0.5)を測り、その画素位置を
# image_frac_to_data で読んだ値が L と 0.5 ms 以内で一致すること。
# 明示 xlim の場合も同じく一致すること(回帰防止)。
# ==================================================================

my $dir = tempdir(CLEANUP => 1);
my ($W, $H) = (900, 700);
my $t = sequence(701) - 100;            # -100..600 ms
my $y = 5 * sin($t / 60);

sub load {
    my ($path) = @_;
    my $s = Cairo::ImageSurface->create_from_png($path);
    $s->flush;
    return ($s->get_data, $s->get_width, $s->get_height, $s->get_stride);
}

# 赤みで重み付けした列重心(px)
sub red_column {
    my ($path) = @_;
    my ($d, $w, $h, $st) = load($path);
    my ($sum, $ws) = (0, 0);
    for my $yy (0 .. $h-1) {
        for my $x (0 .. $w-1) {
            my ($b, $g, $r) = unpack('C3', substr($d, $yy*$st + $x*4, 4));
            my $wt = $r - ($g > $b ? $g : $b);
            next if $wt <= 0;
            $sum += $wt * ($x + 0.5);
            $ws  += $wt;
        }
    }
    return $ws ? $sum / $ws : undef;
}

sub make_fig {
    my ($lat, $mode) = @_;
    my $fig = figure(width => $W, height => $H);
    my $ax  = $fig->axes;
    $ax->line($t, $y, color => 'green');
    $ax->line(pdl($lat, $lat), pdl(-2, 2), color => 'red');
    $ax->xlim(-100, 600) if $mode eq 'xlim';
    return ($fig, $ax);
}

for my $mode (qw(autoscale xlim)) {
    for my $lat (-90, 0, 250, 500, 590) {
        my $tag = "$mode L=$lat";
        my ($fig, $ax) = make_fig($lat, $mode);
        my $png = "$dir/$mode-$lat.png";
        $fig->save($png);
        my $px = red_column($png);
        my $fy = 0.5;

        my ($xd) = $ax->image_frac_to_data($px / $W, $fy);
        ok defined $xd && abs($xd - $lat) <= 0.5,
            sprintf("%s: image_frac_to_data reads %s ms", $tag,
                    defined $xd ? sprintf('%.2f', $xd) : 'undef');

        my ($fx) = $ax->data_to_image_frac($lat, 0);
        ok defined $fx && abs($fx * $W - $px) <= 0.5,
            sprintf("%s: data_to_image_frac gives %.2f px (drawn at %.2f px)",
                    $tag, ($fx // 0) * $W, $px);
    }
}

# ------------------------------------------------------------------
# get_xlim / get_ylim: draw 後は描かれた範囲を返す。枠の端は範囲の端なので、
# 返った範囲の端を、既知の2点の画素位置から求めた一次写像で画素に直すと、
# PNG 上の枠線の位置に一致する。
# ------------------------------------------------------------------
{
    my $fig = figure(width => $W, height => $H);
    my $ax  = $fig->axes;
    $ax->line($t, $y, color => 'green');
    $ax->line(pdl(0, 0),     pdl(-1, 1), color => 'red');     # x の既知点
    $ax->line(pdl(500, 500), pdl(-1, 1), color => 'red');
    $ax->line(pdl(100, 150), pdl(-3, -3), color => 'blue');   # y の既知点
    $ax->line(pdl(100, 150), pdl(3, 3),   color => 'blue');
    my $png = "$dir/lim.png";
    $fig->save($png);
    my ($d, $w, $h, $st) = load($png);

    # 色の重心を、画像を半分に分けた前半/後半ごとに求める
    my (%sum, %wt);
    my (@dark_col, @dark_row);
    for my $yy (0 .. $h-1) {
        for my $x (0 .. $w-1) {
            my ($b, $g, $r) = unpack('C3', substr($d, $yy*$st + $x*4, 4));
            my $red  = $r - ($g > $b ? $g : $b);
            my $blue = $b - ($g > $r ? $g : $r);
            if ($red > 0)  { my $k = $x < $w/2 ? 0 : 1; $sum{"r$k"} += $red*($x+0.5);  $wt{"r$k"} += $red }
            if ($blue > 0) { my $k = $yy < $h/2 ? 0 : 1; $sum{"b$k"} += $blue*($yy+0.5); $wt{"b$k"} += $blue }
            if ($r < 80 && $g < 80 && $b < 80) { $dark_col[$x]++; $dark_row[$yy]++ }
        }
    }
    my ($px0, $px500) = map { $sum{"r$_"} / $wt{"r$_"} } 0, 1;
    my ($py3, $pym3)  = map { $sum{"b$_"} / $wt{"b$_"} } 0, 1;   # 上半分 = y=+3

    # 枠線 = 暗い画素が最も多い列(左半分/右半分)と行(上半分/下半分)。
    # 線の中心は画素中心 i+0.5 とする。
    my $argmax = sub {
        my ($arr, $lo, $hi) = @_;
        my ($best, $bi) = (-1, undef);
        for my $i ($lo .. $hi) { my $v = $arr->[$i] // 0; ($best, $bi) = ($v, $i) if $v > $best }
        return $bi + 0.5;
    };
    my $frame_l = $argmax->(\@dark_col, 0, int($w/2));
    my $frame_r = $argmax->(\@dark_col, int($w/2), $w-1);
    my $frame_t = $argmax->(\@dark_row, 0, int($h/2));
    my $frame_b = $argmax->(\@dark_row, int($h/2), $h-1);

    my ($xlo, $xhi) = $ax->get_xlim;
    my ($ylo, $yhi) = $ax->get_ylim;
    my $x2px = sub { $px0 + ($_[0] - 0) * ($px500 - $px0) / 500 };
    my $y2px = sub { $pym3 + ($_[0] + 3) * ($py3 - $pym3) / 6 };

    cmp_ok abs($x2px->($xlo) - $frame_l), '<=', 1.0,
        sprintf("get_xlim lo=%s maps to the left frame (%.1f vs %.1f px)", $xlo, $x2px->($xlo), $frame_l);
    cmp_ok abs($x2px->($xhi) - $frame_r), '<=', 1.0,
        sprintf("get_xlim hi=%s maps to the right frame (%.1f vs %.1f px)", $xhi, $x2px->($xhi), $frame_r);
    cmp_ok abs($y2px->($ylo) - $frame_b), '<=', 1.0,
        sprintf("get_ylim lo=%s maps to the bottom frame (%.1f vs %.1f px)", $ylo, $y2px->($ylo), $frame_b);
    cmp_ok abs($y2px->($yhi) - $frame_t), '<=', 1.0,
        sprintf("get_ylim hi=%s maps to the top frame (%.1f vs %.1f px)", $yhi, $y2px->($yhi), $frame_t);

    # 明示の lim はそのまま返る
    my $f2 = figure(width => 300, height => 200);
    my $a2 = $f2->axes;
    $a2->line($t, $y);
    $a2->xlim(-100, 600);
    $a2->ylim(-8, 8);
    $f2->to_png;
    is_deeply [ $a2->get_xlim ], [ -100, 600 ], 'get_xlim returns an explicit xlim unchanged';
    is_deeply [ $a2->get_ylim ], [ -8, 8 ],     'get_ylim returns an explicit ylim unchanged';
}

done_testing;
