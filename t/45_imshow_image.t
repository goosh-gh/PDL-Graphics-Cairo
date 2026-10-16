use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::Driver::Cairo;
use PDL::Graphics::Cairo::ColorMap;
use PDL::Graphics::Cairo::ListedColormap;

# ==================================================================
# imshow を 1 枚の画像として描く経路(Driver::Cairo::image_rgb)と、
# カラーマップを配列ごと引く rgb_norm_pdl を確かめる。
#
# 基準は「セルごとに colored_rect で塗る」描き方(以前の imshow と同じ方法)。
# image_rgb の実装とは別の経路なので、同じ誤りで一致することはない。
# ==================================================================

# ARGB32 の surface を (4, W, H) の byte piddle(B, G, R, A)にする
sub pixels {
    my ($drv) = @_;
    my $s = $drv->{surface};
    $s->flush;
    my ($w, $h, $stride) = ($s->get_width, $s->get_height, $s->get_stride);
    my $p = zeroes(byte, $stride, $h);
    ${ $p->get_dataref } = $s->get_data;
    $p->upd_data;
    return $p->slice('0:' . ($w * 4 - 1) . ',:')->reshape(4, $w, $h)->copy;
}

sub new_drv {
    my ($w, $h) = @_;
    my $d = PDL::Graphics::Cairo::Driver::Cairo->new(
        width => $w, height => $h, file => ':memory:');
    $d->{cr}->set_source_rgb(1, 1, 1);
    $d->{cr}->paint;
    return $d;
}

# 5 行 × 7 列(正方でない)。全セルの色が違う
my ($NR, $NC) = (5, 7);
my $R = (sequence($NC, $NR) / ($NC * $NR - 1));          # (cols, rows)
my $G = ($NC - 1 - xvals($NC, $NR)) / ($NC - 1);
my $B = yvals($NC, $NR) / ($NR - 1);

# ---- 1. 整数画素に乗る配置では全画素が一致する ------------------------
{
    my ($x0, $y0, $cw, $ch) = (10, 20, 11, 9);
    my ($W, $H) = (120, 80);

    my $ref = new_drv($W, $H);
    for my $r (0 .. $NR - 1) {
        for my $c (0 .. $NC - 1) {
            $ref->colored_rect($x0 + $c * $cw, $y0 + $r * $ch, $cw, $ch,
                $R->at($c, $r), $G->at($c, $r), $B->at($c, $r), 1.0);
        }
    }
    my $new = new_drv($W, $H);
    ok($new->image_rgb($x0, $y0, $NC * $cw, $NR * $ch, $R, $G, $B, 1.0),
       'image_rgb returns true');

    my ($pr, $pn) = (pixels($ref), pixels($new));
    my $ndiff = (($pr != $pn)->orover)->sum->sclr;
    is($ndiff, 0, 'aligned cells: every pixel equals the colored_rect drawing');

    # 否定対照: 行と列を取り違えた(上下を反転した)画像は一致しない
    my $flip = new_drv($W, $H);
    $flip->image_rgb($x0, $y0, $NC * $cw, $NR * $ch,
        map { $_->slice(':,-1:0') } $R, $G, $B);
    my $nflip = ((pixels($flip) != $pr)->orover)->sum->sclr;
    cmp_ok($nflip, '>', 0.5 * $NC * $cw * $NR * $ch,
       'negative control: an upside-down image differs in most cell pixels');

    # 画像の外側(余白)は触らない: 白のまま
    my $out = $pn->slice(':,0:' . ($x0 - 1) . ',:');
    ok(all($out == 255), 'pixels left of the image stay white');
}

# ---- 2. 端数のある配置: セルの中央の画素は一致する -----------------------
{
    my ($x0, $y0, $w, $h) = (7.3, 12.6, 93.7, 61.1);
    my ($cw, $ch) = ($w / $NC, $h / $NR);
    my ($W, $H) = (120, 90);

    my $ref = new_drv($W, $H);
    for my $r (0 .. $NR - 1) {
        for my $c (0 .. $NC - 1) {
            $ref->colored_rect($x0 + $c * $cw, $y0 + $r * $ch, $cw, $ch,
                $R->at($c, $r), $G->at($c, $r), $B->at($c, $r), 1.0);
        }
    }
    my $new = new_drv($W, $H);
    $new->image_rgb($x0, $y0, $w, $h, $R, $G, $B, 1.0);
    my ($pr, $pn) = (pixels($ref), pixels($new));

    my $bad = 0;
    for my $r (0 .. $NR - 1) {
        for my $c (0 .. $NC - 1) {
            my $px = int($x0 + ($c + 0.5) * $cw);
            my $py = int($y0 + ($r + 0.5) * $ch);
            $bad++ if any($pr->slice(":,($px),($py)") != $pn->slice(":,($px),($py)"));
        }
    }
    is($bad, 0, 'fractional cells: the centre pixel of all 35 cells matches');
}

# ---- 3. alpha と NaN ----------------------------------------------------
{
    my ($W, $H) = (80, 60);
    my $Rn = $R->copy; $Rn->set(2, 1, 'nan' + 0);         # セル (列2, 行1) を NaN に
    my $d = new_drv($W, $H);
    $d->{cr}->set_source_rgb(0, 0, 1); $d->{cr}->paint;   # 背景は青
    $d->image_rgb(0, 0, 70, 50, $Rn, $G, $B, 1.0);
    my $p = pixels($d);
    is_deeply([ $p->slice(':,(25),(15)')->list ], [255, 0, 0, 255],
        'a NaN cell is transparent (the blue background shows)');

    my $ref = new_drv($W, $H);
    my $new = new_drv($W, $H);
    $ref->colored_rect(0, 0, 70, 50, 0.8, 0.2, 0.4, 0.5);
    $new->image_rgb(0, 0, 70, 50, (pdl(0.8)->dummy(0, 7)->dummy(1, 5)),
        (pdl(0.2)->dummy(0, 7)->dummy(1, 5)), (pdl(0.4)->dummy(0, 7)->dummy(1, 5)), 0.5);
    my $dmax = (pixels($ref)->long - pixels($new)->long)->abs->max;
    cmp_ok($dmax, '<=', 1, "alpha 0.5: within 1 level of colored_rect (got $dmax)");
}

# ---- 4. rgb_norm_pdl は rgb_norm と同じ値を返す ----------------------
{
    my $v = pdl(-3, -1, -0.5, 0, 0.01, 0.125, 0.3333, 0.5, 0.875, 0.999, 1, 1.5, 7);
    my $vv = $v->dummy(0, 2)->copy;                         # 2 次元でも同じ
    for my $name (PDL::Graphics::Cairo::ColorMap->list) {
        my $cm = PDL::Graphics::Cairo::ColorMap->new($name);
        my @got = $cm->rgb_norm_pdl($vv, -1, 1);
        my $err = 0;
        for my $i (0 .. $v->nelem - 1) {
            my @want = $cm->rgb_norm($v->at($i), -1, 1);
            for my $k (0 .. 2) {
                my $e = abs($got[$k]->at(1, $i) - $want[$k]);
                $err = $e if $e > $err;
            }
        }
        cmp_ok($err, '<', 1e-12, "ColorMap $name: rgb_norm_pdl == rgb_norm");
    }
    my $cm = PDL::Graphics::Cairo::ColorMap->new('viridis');
    my @eq = $cm->rgb_norm_pdl(pdl(3, 4), 2, 2);
    my @w  = $cm->rgb_norm(3, 2, 2);
    ok(abs($eq[0]->at(1) - $w[0]) < 1e-12, 'vmin == vmax gives the middle colour');
    my @n = $cm->rgb_norm_pdl(pdl(0, 'nan'), 0, 1);
    ok(!isfinite($n[1]->slice('(1)'))->sclr && isfinite($n[1]->slice('(0)'))->sclr,
       'NaN in, NaN out (others finite)');

    # 末尾の :: が要る: PDL::Graphics::Cairo には ListedColormap という関数もあり、
    # 無いとそちらの呼び出しと解釈される
    my $lc = PDL::Graphics::Cairo::ListedColormap::->new(
        ['#ff0000', '#00ff00', '#0000ff', '#808080']);
    my $lv = pdl(-1, 0, 0.24, 0.25, 0.26, 0.5, 0.74, 0.75, 0.99, 1, 2);
    my @lg = $lc->rgb_norm_pdl($lv, 0, 1);
    my $lerr = 0;
    for my $i (0 .. $lv->nelem - 1) {
        my @want = $lc->rgb_norm($lv->at($i), 0, 1);
        for my $k (0 .. 2) {
            my $e = abs($lg[$k]->at($i) - $want[$k]);
            $lerr = $e if $e > $lerr;
        }
    }
    is($lerr, 0, 'ListedColormap: rgb_norm_pdl == rgb_norm (bin edges included)');
}

# ---- 5. imshow 全体: 新しい経路と以前の経路の違いはセルの境目だけ ----
#   以前の描き方はセルを 0.5 px ずつ重ねて塗っていたので、端数の位置にある
#   境目の 1 画素だけはアンチエイリアスの混ざり方が違う。それ以外は同じ。
sub render_fig {
    my ($build) = @_;
    my $fig = figure(width => 400, height => 300);
    my $ax  = $fig->add_subplot(1, 1, 1);
    $build->($ax);
    my $d = PDL::Graphics::Cairo::Driver::Cairo->new(
        width => 400, height => 300, file => ':memory:');
    $fig->_render_to($d);
    return (pixels($d), $ax);
}

# 差のある画素のうち、セルの境目(縦・横)から 1.5 px より遠いものの数
sub off_edge {
    my ($dmask, $ax, $nr, $nc) = @_;
    my ($ml, $mr, $mt, $mb) = map { $ax->$_ } qw(_plot_ml _plot_mr _plot_mt _plot_mb);
    my $bx = $ml + sequence($nc + 1) * ($mr - $ml) / $nc;   # 縦の境目(px)
    my $by = $mt + sequence($nr + 1) * ($mb - $mt) / $nr;   # 横の境目(px)
    my $w  = whichND($dmask);                              # (2, n): x, y
    return 0 unless $w->dim(1);
    my $px = $w->slice('(0),:')->double + 0.5;             # 画素の中心
    my $py = $w->slice('(1),:')->double + 0.5;
    my $dx = ($px->dummy(0) - $bx)->abs->minimum;          # 一番近い縦の境目まで
    my $dy = ($py->dummy(0) - $by)->abs->minimum;
    return (($dx > 1.5) & ($dy > 1.5))->sum->sclr;
}

for my $case (
    [ 'scalar, origin upper', 9, 13, sub { $_[0]->imshow(sequence(9, 13)->sin, cmap => 'RdBu') } ],
    [ 'scalar, origin lower', 9, 13, sub { $_[0]->imshow(sequence(9, 13)->sin, origin => 'lower') } ],
    [ 'RGB (rows, cols, 3)',  $NR, $NC,
          sub { $_[0]->imshow(cat($R, $G, $B)->xchg(0, 1), origin => 'lower') } ],
) {
    my ($name, $nr, $nc, $build) = @$case;
    my ($pn, $ax) = render_fig($build);
    my ($po) = do {
        no warnings 'redefine';
        local *PDL::Graphics::Cairo::Driver::Cairo::image_rgb;   # 以前の経路に戻す
        render_fig($build);
    };
    my $dmask = ($pn != $po)->orover;                          # (400, 300)
    my $ndiff = $dmask->sum->sclr;
    is(off_edge($dmask, $ax, $nr, $nc), 0,
       "$name: all $ndiff differing pixels are on cell edges");

    # 否定対照: 1 セル分ずらした境目で数えると、境目から外れる画素が出る
    my ($ml, $mr) = ($ax->_plot_ml, $ax->_plot_mr);
    my $shift = (($mr - $ml) / $nc) / 2;
    my $sm = zeroes(byte, 400, 300);
    my $xs = int($shift + 0.5);
    $sm->slice($xs . ':-1,:') .= $dmask->slice('0:' . (399 - $xs) . ',:');
    cmp_ok(off_edge($sm, $ax, $nr, $nc), '>', 0,
       "$name: negative control (edges moved by half a cell) is caught");
}

# 否定対照: origin を取り違えると大きく違う
{
    my $z = sequence(9, 13)->sin;
    my ($pu) = render_fig(sub { $_[0]->imshow($z, origin => 'upper') });
    my ($pl) = render_fig(sub { $_[0]->imshow($z, origin => 'lower') });
    my $frac = ((($pu != $pl)->orover)->sum->sclr) / (400 * 300);
    cmp_ok($frac, '>', 0.1, sprintf('negative control: upper vs lower differ in %.0f%% of pixels',
        100 * $frac));
}

done_testing;
