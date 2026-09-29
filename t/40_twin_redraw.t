use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);
use Cairo;
use File::Temp qw(tempdir);

# ==================================================================
# twinx()/twiny() を含む図を save した後にデータを足し、もう一度 save
# すると、autoscale の範囲が新しいデータに合わせて広がること。
# matplotlib では autoscale は描画のたびにデータから決まり、先の描画の
# 範囲に固着しない。親の軸と、twin 自身の独立軸(twinx の y、twiny の x)
# の両方で確かめる。
#
# 範囲は draw() が確定した範囲(_plot_range)で見るほか、新しい範囲に
# だけ入る位置に置いた印(親は赤、twin は青)が PNG に出ることでも見る。
# 範囲が固着していれば印はクリップされて画素が出ない。
# ==================================================================

my $dir = tempdir(CLEANUP => 1);

sub count_color {
    my ($path, $color) = @_;
    my $s = Cairo::ImageSurface->create_from_png($path);
    $s->flush;
    my ($w, $h, $stride) = ($s->get_width, $s->get_height, $s->get_stride);
    my $data = $s->get_data;
    my $n = 0;
    for my $y (0 .. $h-1) {
        my $row = substr($data, $y*$stride, $w*4);
        for my $x (0 .. $w-1) {
            my ($b, $g, $r) = unpack('C3', substr($row, $x*4, 4));
            $n++ if $color eq 'red'  && $r > 200 && $g < 60 && $b < 60;
            $n++ if $color eq 'blue' && $b > 200 && $g < 60 && $r < 60;
        }
    }
    return $n;
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

for my $how (qw(axes subplots)) {
    for my $tw (qw(twinx twiny)) {
        my $tag = "$how/$tw";
        my ($fig, $ax) = make_parent($how);
        my $twin = $ax->$tw;
        my $shared_is_x = $tw eq 'twinx';

        # (shared, independent) の順で座標を組み立てる
        my $xy = sub {
            my ($s, $i) = @_;
            return $shared_is_x ? ($s, $i) : ($i, $s);
        };

        # 1回目: 親 0..10(両軸)、twin の独立軸 0..1
        $ax->line(pdl(0, 10), pdl(0, 10), color => 'black');
        $twin->line($xy->(pdl(0, 10), pdl(0, 1)), color => 'black');
        $fig->save("$dir/$how-$tw-1.png");

        # データを足す: 親は両軸 0..50、twin の独立軸 0..100
        $ax->line(pdl(0, 50), pdl(0, 50), color => 'black');
        $twin->line($xy->(pdl(0, 10), pdl(0, 100)), color => 'black');
        # 新しい範囲にだけ入る位置の印
        $ax->line(pdl(40, 45), pdl(40, 45), color => 'red');
        $twin->line($xy->(pdl(5, 5), pdl(80, 95)), color => 'blue');

        my $png = "$dir/$how-$tw-2.png";
        $fig->save($png);

        my $p = $ax->_plot_range;
        my $c = $twin->_plot_range;
        my ($ci_lo, $ci_hi) = $shared_is_x ? @$c[2, 3] : @$c[0, 1];

        cmp_ok $p->[1], '>=', 50, "$tag: parent x range grows on 2nd save (xmax=$p->[1])";
        cmp_ok $p->[3], '>=', 50, "$tag: parent y range grows on 2nd save (ymax=$p->[3])";
        cmp_ok $ci_hi,  '>=', 100, "$tag: twin independent range grows on 2nd save (max=$ci_hi)";
        cmp_ok count_color($png, 'red'),  '>', 0, "$tag: parent mark in the new range is drawn";
        cmp_ok count_color($png, 'blue'), '>', 0, "$tag: twin mark in the new range is drawn";
    }
}

done_testing;
