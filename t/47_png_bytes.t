use strict;
use warnings;
use Test::More;
use PDL;
use Cairo;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::Driver::Cairo;

# ==================================================================
# png_bytes の速い経路(_argb32_surface_to_png_bytes)を確かめる。
# 作った PNG を Cairo の PNG 読み込み(libpng)でデコードし、元の surface の
# 画素と 1 バイトずつ比べる。デコーダはエンコーダと別物なので、R と B の
# 取り違えなどは一致しない。
# ==================================================================

sub decode {
    my ($png) = @_;
    my $pos = 0;
    return Cairo::ImageSurface->create_from_png_stream(sub {
        my (undef, $n) = @_;
        my $c = substr($png, $pos, $n);
        $pos += length $c;
        return $c;
    });
}

# surface の画素を (4, W, H) の byte piddle(B, G, R, A)で
sub bgra {
    my ($s) = @_;
    $s->flush;
    my ($w, $h, $st) = ($s->get_width, $s->get_height, $s->get_stride);
    my $p = zeroes(byte, $st, $h);
    ${ $p->get_dataref } = $s->get_data;
    $p->upd_data;
    return $p->slice('0:' . (4 * $w - 1) . ',:')->reshape(4, $w, $h)->copy;
}

my $LE = (pack('L', 1) eq "\1\0\0\0");

# 速い経路は 2 通り: PDL::IO::PNG の png_encode(あれば)と、Perl で組む経路。
# どちらも同じ確かめ方をする。カラータイプは png_encode が RGB(2)、Perl が RGBA(6)。
my @modes = ([ 'Perl', 0, 6 ]);
push @modes, [ 'png_encode', 1, 2 ] if $PDL::Graphics::Cairo::Driver::Cairo::HAVE_PNG_ENCODE;
diag('PDL::IO::PNG::png_encode not available: only the Perl path is tested')
    unless $PDL::Graphics::Cairo::Driver::Cairo::HAVE_PNG_ENCODE;

for my $mode (@modes) {
SKIP: {
    my ($mname, $use, $ctype) = @$mode;
    skip 'the fast path is little-endian only', 8 unless $LE;
    local $PDL::Graphics::Cairo::Driver::Cairo::HAVE_PNG_ENCODE = $use;

    # 波形の図(不透明)
    my $fig = figure(width => 333, height => 211);        # 幅は 4 の倍数でない
    $fig->add_subplot(1, 2, $_)->plot(sequence(200), sin(sequence(200) / (9 + $_))) for 1 .. 2;
    my $d = PDL::Graphics::Cairo::Driver::Cairo->new(width => 333, height => 211, file => ':memory:');
    $fig->_render_to($d);

    my $png = PDL::Graphics::Cairo::Driver::Cairo::_argb32_surface_to_png_bytes($d->{surface});
    ok(defined $png, "$mname: opaque figure: the fast path is taken");
    is(ord(substr($png, 25, 1)), $ctype, "$mname: PNG colour type $ctype");
    my $img = decode($png);
    is($img->status, 'success', "$mname: libpng decodes it");
    my $ndiff = ((bgra($img) != bgra($d->{surface}))->orover)->sum->sclr;
    is($ndiff, 0, "$mname: every pixel equals the surface");

    # 既知の色: 赤・緑・青の帯
    my $s  = Cairo::ImageSurface->create('argb32', 30, 10);
    my $cr = Cairo::Context->create($s);
    my @c  = ([1, 0, 0], [0, 1, 0], [0, 0, 1]);
    for my $i (0 .. 2) {
        $cr->set_source_rgb(@{ $c[$i] });
        $cr->rectangle(10 * $i, 0, 10, 10);
        $cr->fill;
    }
    my $k = bgra(decode(PDL::Graphics::Cairo::Driver::Cairo::_argb32_surface_to_png_bytes($s)));
    is_deeply([ map { [ $k->slice(":,($_),(5)")->list ] } 5, 15, 25 ],
              [ [0, 0, 255, 255], [0, 255, 0, 255], [255, 0, 0, 255] ],
              "$mname: red, green and blue come back as red, green and blue");

    # 否定対照: R と B を入れ替えないと赤が青になる(比較が効いていることの確認)
    my $swapped = $k->dice_axis(0, [2, 1, 0, 3]);
    isnt(join(',', $swapped->slice(':,(5),(5)')->list), join(',', $k->slice(':,(5),(5)')->list),
         "$mname: negative control: a red/blue swap would be detected");

    # 圧縮レベル 0 でも同じ画素(サイズだけ違う)
    my $png0 = PDL::Graphics::Cairo::Driver::Cairo::_argb32_surface_to_png_bytes($d->{surface}, 0);
    ok(length($png0) > 2 * length($png), "$mname: level 0 is larger than level 1");
    is(((bgra(decode($png0)) != bgra($d->{surface}))->orover)->sum->sclr, 0,
       "$mname: level 0: every pixel equals the surface");
}
}

# 透明な画素があると速い経路は使わない(色がプリマルチプライ済みのため)。
# png_bytes はそれでも正しい PNG を返す
{
    my $d = PDL::Graphics::Cairo::Driver::Cairo->new(width => 20, height => 10, file => ':memory:');
    my $cr = $d->{cr};
    $cr->set_operator('source');
    $cr->set_source_rgba(0, 0, 0, 0);
    $cr->paint;
    $cr->set_source_rgba(1, 0, 0, 0.5);
    $cr->rectangle(0, 0, 10, 10);
    $cr->fill;
    ok(!defined PDL::Graphics::Cairo::Driver::Cairo::_argb32_surface_to_png_bytes($d->{surface}),
       'not opaque: the fast path declines');
    my $img = decode($d->png_bytes);
    is($img->status, 'success', 'png_bytes falls back and still returns a PNG');
    is(join('x', $img->get_width, $img->get_height), '20x10', 'fallback PNG has the surface size');
    my $p = bgra($img);
    # 以前からの経路は PDL::IO::PNG の有無で変わる:
    #   あり: wpng が RGB で書く。アルファは落ち、プリマルチプライ済みの R(約 128)が残る
    #         (B,G,R,A = 0,0,128,255)
    #   なし: Cairo の write_to_png が RGBA で書く。読み戻すとプリマルチプライ済みで
    #         R = A = 約 128
    # どちらでも、その画素は赤み(R が約 128)で、緑と青は 0。
    my ($bb, $gg, $rr, $aa) = $p->slice(':,(5),(5)')->list;
    ok($rr >= 127 && $rr <= 128 && $gg == 0 && $bb == 0,
       "the half-transparent red pixel is red in the fallback PNG (B,G,R,A = $bb,$gg,$rr,$aa)");
}

done_testing;
