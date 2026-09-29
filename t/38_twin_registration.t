use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);
use Cairo;
use File::Temp qw(tempdir);

# ==================================================================
# twinx()/twiny() で作った twin が Figure に一度だけ登録され、実際に
# 描画されることを検証する。matplotlib では Axes.twinx()/twiny() が
# 返す Axes は親と同じ Figure に属し、fig.savefig() で描かれる。
# 親を figure()->axes() で作った場合も subplots() で作った場合も同じ。
# Figure への登録は重複しない(同じ Axes を重ねて登録しても 1 個)。
# ==================================================================

my $dir = tempdir(CLEANUP => 1);

# 純赤 (255,0,0) 近傍の画素数。Cairo ARGB32 は little-endian で B,G,R,A。
sub red_pixels {
    my ($path) = @_;
    my $s = Cairo::ImageSurface->create_from_png($path);
    $s->flush;
    my ($w, $h, $stride) = ($s->get_width, $s->get_height, $s->get_stride);
    my $data = $s->get_data;
    my $n = 0;
    for my $y (0 .. $h-1) {
        my $row = substr($data, $y*$stride, $w*4);
        for my $x (0 .. $w-1) {
            my ($b, $g, $r) = unpack('C3', substr($row, $x*4, 4));
            $n++ if $r > 200 && $g < 60 && $b < 60;
        }
    }
    return $n;
}

sub make_parent {
    my ($how) = @_;
    if ($how eq 'axes') {
        my $fig = figure(width => 400, height => 300);
        return ($fig, $fig->axes);
    }
    my ($fig, $ax) = subplots(1, 1, width => 400, height => 300);
    return ($fig, $ax);
}

sub occurrences {
    my ($fig, $ax) = @_;
    return scalar grep { $_ == $ax } @{ $fig->axes_list };
}

for my $how (qw(axes subplots)) {
    for my $tw (qw(twinx twiny)) {
        my $tag = "$how/$tw";
        my ($fig, $ax) = make_parent($how);
        my $twin = $ax->$tw;

        # 親は青、twin だけが赤を描く
        $ax->line(pdl(0, 1), pdl(0, 1), color => 'blue');
        $twin->line(pdl(0, 1), pdl(0, 1), color => 'red');

        is occurrences($fig, $twin), 1, "$tag: twin is in axes_list exactly once";

        my $png = "$dir/${how}_$tw.png";
        $fig->save($png);
        cmp_ok red_pixels($png), '>', 50, "$tag: twin's line is drawn";

        # add_axes を重ねて呼んでも登録は 1 個のまま
        $fig->add_axes($twin);
        $fig->add_axes($twin);
        is occurrences($fig, $twin), 1, "$tag: repeated add_axes keeps a single entry";
    }
}

# 否定対照: 親に何も足さなければ赤は出ない(赤画素の検出が背景や
# 既定色で誤検出していないこと)
{
    my ($fig, $ax) = make_parent('axes');
    $ax->line(pdl(0, 1), pdl(0, 1), color => 'blue');
    my $png = "$dir/control.png";
    $fig->save($png);
    is red_pixels($png), 0, 'control: no red pixels without a red line';
}

done_testing;
