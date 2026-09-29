use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);
use Cairo;
use File::Temp qw(tempdir);

# ==================================================================
# twinx()/twiny() の共有軸で、同じデータ値が親と twin で同じ画素位置に
# 写ることを描画結果から検証する。matplotlib では twinx() は x 軸を、
# twiny() は y 軸を親と共有し、共有軸の同じ値は同じ位置に描かれる。
#
# 方法: 共有軸の値 c=2 と c=8 に、親は赤、twin は青の線を描く
# (共有軸に垂直な線)。赤と青は独立軸の方向で重ならない区間に置く。
# PNG から赤・青それぞれの重心を共有軸方向で測り、左右(上下)の半分
# ごとに比べる。tight_layout・subplots_adjust の後でも一致すること。
# ==================================================================

my $dir = tempdir(CLEANUP => 1);
my $TOL = 0.5;   # px

# 赤み・青みで重み付けした重心を返す。$axis は 'x'(列)か 'y'(行)。
# 画像を共有軸方向で2分し、[前半の重心, 後半の重心] を返す。
# Cairo ARGB32 は little-endian で B,G,R,A。白地・黒/灰の線は重み 0。
sub centroids {
    my ($path, $color, $axis) = @_;
    my $s = Cairo::ImageSurface->create_from_png($path);
    $s->flush;
    my ($w, $h, $stride) = ($s->get_width, $s->get_height, $s->get_stride);
    my $data = $s->get_data;
    my $half = ($axis eq 'x' ? $w : $h) / 2;
    my @sum  = (0, 0);
    my @wsum = (0, 0);
    for my $y (0 .. $h-1) {
        my $row = substr($data, $y*$stride, $w*4);
        for my $x (0 .. $w-1) {
            my ($b, $g, $r) = unpack('C3', substr($row, $x*4, 4));
            my $wt = $color eq 'red'
                ? $r - ($g > $b ? $g : $b)
                : $b - ($g > $r ? $g : $r);
            next if $wt <= 0;
            my $pos = $axis eq 'x' ? $x : $y;
            my $k = $pos < $half ? 0 : 1;
            $sum[$k]  += $wt * $pos;
            $wsum[$k] += $wt;
        }
    }
    return [ map { $wsum[$_] > 0 ? $sum[$_] / $wsum[$_] : undef } 0, 1 ];
}

sub make_parent {
    my ($how) = @_;
    if ($how eq 'axes') {
        my $fig = figure(width => 600, height => 400);
        return ($fig, $fig->axes);
    }
    my ($fig, $ax) = subplots(1, 1, width => 600, height => 400);
    return ($fig, $ax);
}

# 共有軸の値 c=2, 8 に線を描く。親は独立軸の 0-4(範囲 0-10 の下側/左側)、
# twin は独立軸の 60-100(範囲 0-100 の上側/右側)で、互いに重ならない。
sub draw_marks {
    my ($ax, $twin, $tw) = @_;
    for my $c (2, 8) {
        if ($tw eq 'twinx') {       # x 共有: 縦線
            $ax->line(pdl($c, $c), pdl(0, 4),     color => 'red');
            $twin->line(pdl($c, $c), pdl(60, 100), color => 'blue');
        } else {                    # y 共有: 横線
            $ax->line(pdl(0, 4),     pdl($c, $c), color => 'red');
            $twin->line(pdl(60, 100), pdl($c, $c), color => 'blue');
        }
    }
    # 独立軸の範囲だけ明示する(共有軸は autoscale のまま)
    if ($tw eq 'twinx') {
        $ax->ylim(0, 10);
        $twin->ylim(0, 100);
    } else {
        $ax->xlim(0, 10);
        $twin->xlim(0, 100);
    }
}

my %layout = (
    auto           => sub { },                       # save 内の自動 tight_layout
    tight_layout   => sub { $_[0]->tight_layout },
    subplots_adjust => sub { $_[0]->subplots_adjust(left => 0.2, right => 0.75,
                                                    bottom => 0.2, top => 0.8) },
);

for my $how (qw(axes subplots)) {
    for my $tw (qw(twinx twiny)) {
        for my $lay (qw(auto tight_layout subplots_adjust)) {
            my $tag = "$how/$tw/$lay";
            my ($fig, $ax) = make_parent($how);
            my $twin = $ax->$tw;
            draw_marks($ax, $twin, $tw);
            $layout{$lay}->($fig);

            my $png = "$dir/$how-$tw-$lay.png";
            unless (eval { $fig->save($png); 1 }) {
                fail "$tag: save succeeds" for 1, 2;
                diag "save died: $@";
                next;
            }

            my $axis = $tw eq 'twinx' ? 'x' : 'y';
            my $r = centroids($png, 'red',  $axis);
            my $b = centroids($png, 'blue', $axis);
            for my $k (0, 1) {
                my $which = $k ? 'c=8 side' : 'c=2 side';
                if (!defined $r->[$k] || !defined $b->[$k]) {
                    fail "$tag $which: red and blue marks are both drawn";
                    next;
                }
                cmp_ok abs($r->[$k] - $b->[$k]), '<=', $TOL,
                    sprintf("%s %s: parent %.2f px vs twin %.2f px", $tag, $which, $r->[$k], $b->[$k]);
            }
        }
    }
}

done_testing;
