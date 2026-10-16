package PDL::Graphics::Cairo::Driver::Cairo;

# =============================================================
# Driver::Cairo — Cairo/Pango 
#   - PNG / PDF / SVG 
#   - 
#   - Axes  API
# =============================================================

use strict;
use warnings;
use Moo;
use utf8;
use Encode qw(encode is_utf8);
use Cairo;
use Cairo::GObject;
use Pango;
use POSIX qw(floor ceil);
# use List::Util qw(min max);
use List::Util ();
use PDL;
# PDL::IO::PNG (wpng) is optional: it makes PNG writing faster (~3.4ms vs
# ~9.2ms), but is not required. When absent we fall back to Cairo's own
# write_to_png. This mirrors imread()'s PNG -> Image -> rpic fallback, so the
# module loads and builds with or without PDL::IO::PNG installed.
our $HAVE_WPNG = eval { require PDL::IO::PNG; PDL::IO::PNG->import('wpng'); 1 };

# -------------------------------------------------------------
#

# -------------------------------------------------------------
has width  => (is => 'ro', required => 1);
has height => (is => 'ro', required => 1);
has file      => (is => 'ro', default  => sub { 'out.png' });
has dpi    => (is => 'ro', default  => sub { 96 });
has scale  => (is => 'ro', default  => sub { 1.0 });  # savefig(dpi=>) 用スケール因数

# -------------------------------------------------------------
# BUILD
# -------------------------------------------------------------

sub BUILD {
    my ($self) = @_;

    my $surface;
    if ($self->file eq ':memory:' || $self->file =~ /\.png$/i) {
        # :memory: — render to an in-memory ARGB32 surface; PNG bytes are
        # later extracted via png_bytes() with no temp file (used by Driver::GS).
        $surface = Cairo::ImageSurface->create(
            'argb32', $self->width, $self->height);
    }
    elsif ($self->file =~ /\.pdf$/i) {
        $surface = Cairo::PdfSurface->create(
            $self->file, $self->width, $self->height);
    }
    elsif ($self->file =~ /\.svg$/i) {
        $surface = Cairo::SvgSurface->create(
            $self->file, $self->width, $self->height);
    }
    else {
        die "Backend::Cairo: unsupported format (png/pdf/svg): " . $self->file;
    }

    my $cr = Cairo::Context->create($surface);

    # アンチエイリアス設定（環境変数 PDLCAIRO_ANTIALIAS で上書き可能）
    # 'none'=最速, 'fast'=高速, 'good'=高品質(デフォルト), 'best'=最高品質
    {
        my $aa = lc($ENV{PDLCAIRO_ANTIALIAS} // 'gray');
        # Cairo::Perl有効値を実測: 'gray' のみ安定動作
        # none/default/subpixelはこの環境でクラッシュするため無効化
        # gray=グレースケールAA（高速・安定）
        if ($aa eq 'gray' || $aa eq 'good' || $aa eq 'fast') {
            $cr->set_antialias('gray');
        }
        # それ以外はデフォルト（set_antialiasを呼ばない）
    }

    # Background color:
    # Only read PGPLOT_BACKGROUND when called from the PGPLOT layer.
    # The Cairo API (figure/axes) always uses white background.
    # PGPLOT layer sets _PDLCAIRO_PGBG=black internally when needed.
    my $bg = $ENV{_PDLCAIRO_PGBG} // 'white';
    if (lc($bg) eq 'black') {
        $cr->set_source_rgb(0,0,0);
    } else {
        $cr->set_source_rgb(1,1,1);
    }
    $cr->paint;

    # Foreground: white on black background, black on white
    if (lc($bg) eq 'black') {
        $cr->set_source_rgb(1,1,1);
    } else {
        $cr->set_source_rgb(0,0,0);
    }
    $cr->set_line_width(1.5);

    $self->{cr}      = $cr;
    $self->{surface} = $surface;

    # dpi scale: 1.0 以外のとき全座標をスケール変換して高解像度出力
    if ($self->scale != 1.0) {
        $cr->scale($self->scale, $self->scale);
    }

    # Pango — デフォルトフォントは rcParams['font.family'] から取得
    # (rcParams未設定時は 'Helvetica Neue' フォールバック)
    $self->{pango}   = Pango::Cairo::create_layout($cr);
    # 文字のアンチエイリアスはグレースケールに固定する。$cr->set_antialias は
    # 図形にしか効かず、文字は fontconfig の rgba 設定に従う。Ubuntu 26.04 など
    # rgba=rgb の環境ではサブピクセル描画になり、保存画像の文字に赤・青の
    # 色にじみが出る(t/39・t/41 の色重心測定もこれで狂った)。
    {
        my $fo = Cairo::FontOptions->create;
        $fo->set_antialias('gray');
        $fo->set_subpixel_order('default');
        Pango::Cairo::Context::set_font_options($self->{pango}->get_context, $fo);
        $self->{pango}->context_changed;
    }
    {
        my $rcp = \%PDL::Graphics::Cairo::_RCPARAMS;
        $self->{font_family} = $rcp->{'font.family'} // 'Helvetica Neue';
        $self->{font_size}   = $rcp->{'font.size'}   // 11;
    }
    $self->{font_weight} = 'normal';
    $self->{font_slant}  = 'normal';
    $self->_update_pango_font();
}

sub _update_pango_font {
    my ($self) = @_;
    my $w = $self->{font_weight} eq 'bold'   ? 'Bold '   : '';
    my $i = $self->{font_slant}  eq 'italic' ? 'Italic ' : '';

    # fontconfig/Pangoはシステムに存在しないフォント名を指定しても
    # 自動フォールバックするが、明示的にフォールバックチェーンを
    # コメントで示しておく:
    #   Helvetica Neue (macOS native) → Helvetica → Arial → Sans
    # Pangoはfontconfigを通じてこの順で解決する。
    my $desc_str = $self->{font_family} . ' ' . $w . $i . $self->{font_size};
    my $fd = Pango::FontDescription->from_string($desc_str);
    $self->{pango}->set_font_description($fd);
}

# -------------------------------------------------------------
#

# -------------------------------------------------------------
# Unicode → Pango markup 
sub _to_markup {
    my ($str) = @_;
    # UTF-8UTF-8
    if (!utf8::is_utf8($str)) {
        my $decoded = eval { Encode::decode('UTF-8', $str, Encode::FB_CROAK()) };
        $str = $decoded if defined $decoded;
    }
    # Pango markup 
    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    # ASCIIPango
    $str =~ s/([^\x00-\x7E])/sprintf("&#x%X;", ord($1))/ge;
    return $str;
}

sub set_color {
    my ($self, $r, $g, $b, $a) = @_;
    $a //= 1.0;
    $self->{cr}->set_source_rgba($r, $g, $b, $a);
}

sub set_linewidth { $_[0]->{cr}->set_line_width($_[1]) }

# linestyle: 'solid' / 'dashed' / 'dotted' / 'dashdot'
sub set_linestyle {
    my ($self, $style, $lw) = @_;
    $lw //= 1.5;
    my $cr = $self->{cr};
    if    ($style eq 'dashed')  { $cr->set_dash(0, $lw*4, $lw*2) }
    elsif ($style eq 'dotted')  { $cr->set_dash(0, $lw,   $lw*2) }
    elsif ($style eq 'dashdot') { $cr->set_dash(0, $lw*4, $lw*2, $lw, $lw*2) }
    else                        { $cr->set_dash(0) }   # solid
}


sub set_font {
    my ($self, %opt) = @_;
    $self->{font_family} = $opt{family} // $self->{font_family};
    $self->{font_size}   = $opt{size}   // $self->{font_size};
    $self->{font_weight} = $opt{weight} // 'normal';
    $self->{font_slant}  = $opt{slant}  // 'normal';
    $self->_update_pango_font();
}

# -------------------------------------------------------------
#

# -------------------------------------------------------------
sub save    { $_[0]->{cr}->save }
sub restore { $_[0]->{cr}->restore }

# -------------------------------------------------------------
#

# -------------------------------------------------------------
sub clip_rect {
    my ($self, $x, $y, $w, $h) = @_;
    $self->{cr}->rectangle($x, $y, $w, $h);
    $self->{cr}->clip;
}
sub reset_clip { $_[0]->{cr}->reset_clip }

# -------------------------------------------------------------
#

# -------------------------------------------------------------

# PDL piddle
sub polyline {
    my ($self, $x, $y) = @_;
    my $cr = $self->{cr};
    return unless $x->nelem > 0;
    # One ->list per axis instead of ->at() per point (at() is slow per call).
    my @xs = $x->list;
    my @ys = $y->list;
    $cr->move_to($xs[0], $ys[0]);
    for my $i (1 .. $#xs) {
        $cr->line_to($xs[$i], $ys[$i]);
    }
    $cr->stroke;
}

# PDL piddle

sub filled_rect {
    my ($self, $x, $y, $w, $h) = @_;
    return if $w <= 0 || $h <= 0;
    $self->{cr}->rectangle($x, $y, $w, $h);
    $self->{cr}->fill;
}

sub set_alpha { my ($self, $a) = @_; $self->{_alpha} = $a // 1.0; }

sub filled_polygon_xy {
    my ($self, $xs, $ys) = @_;  # arrayrefs
    return unless @$xs >= 3;
    my $cr = $self->{cr};
    $cr->new_path;
    $cr->move_to($xs->[0], $ys->[0]);
    for my $i (1..$#$xs) { $cr->line_to($xs->[$i], $ys->[$i]) }
    $cr->close_path;
    my $a = $self->{_alpha} // 1.0;
    if ($a < 1.0) {
        $cr->save; $cr->clip; $cr->paint_with_alpha($a); $cr->restore;
    } else { $cr->fill; }
}

sub filled_polygon {
    my ($self, $x, $y) = @_;
    my $cr = $self->{cr};
    return unless $x->nelem > 0;
    # One ->list per axis instead of ->at() per point (at() is slow per call).
    my @xs = $x->list;
    my @ys = $y->list;
    $cr->move_to($xs[0], $ys[0]);
    for my $i (1 .. $#xs) {
        $cr->line_to($xs[$i], $ys[$i]);
    }
    $cr->close_path;
    my $a = $self->{_alpha} // 1.0;
    if ($a < 1.0) {
        $cr->save;
        $cr->clip;
        $cr->paint_with_alpha($a);
        $cr->restore;
    } else {
        $cr->fill;
    }
}

#

sub line_seg {
    my ($self, $x1, $y1, $x2, $y2) = @_;
    my $cr = $self->{cr};
    $cr->move_to($x1, $y1);
    $cr->line_to($x2, $y2);
    $cr->stroke;
}

#

sub rect_stroke {
    my ($self, $x, $y, $w, $h) = @_;
    $self->{cr}->rectangle($x, $y, $w, $h);
    $self->{cr}->stroke;
}

#

sub rect_fill {
    my ($self, $x, $y, $w, $h) = @_;
    $self->{cr}->rectangle($x, $y, $w, $h);
    $self->{cr}->fill;
}

#  or 
sub circle {
    my ($self, $cx, $cy, $r, $fill) = @_;
    my $cr = $self->{cr};
    $cr->arc($cx, $cy, $r, 0, 2*3.14159265358979);
    $fill ? $cr->fill : $cr->stroke;
}

# scatter 
# style: 'o' circle / 's' square / '^' triangle / '+' plus / 'x' cross / 'd' diamond
sub marker {
    my ($self, $cx, $cy, $size, $style, $fill) = @_;
    $style //= 'o';
    $size  //= 4;
    $fill  //= 1;
    my $cr = $self->{cr};

    $cr->save;
    if ($style eq 'o') {
        $cr->arc($cx, $cy, $size, 0, 2*3.14159265358979);
        $fill ? $cr->fill_preserve : ();
        $cr->stroke;
    }
    elsif ($style eq 's') {
        $cr->rectangle($cx - $size, $cy - $size, $size*2, $size*2);
        $fill ? $cr->fill_preserve : ();
        $cr->stroke;
    }
    elsif ($style eq '^') {
        $cr->move_to($cx,        $cy - $size);
        $cr->line_to($cx+$size,  $cy + $size);
        $cr->line_to($cx-$size,  $cy + $size);
        $cr->close_path;
        $fill ? $cr->fill_preserve : ();
        $cr->stroke;
    }
    elsif ($style eq 'd') {
        $cr->move_to($cx,        $cy - $size);
        $cr->line_to($cx+$size,  $cy);
        $cr->line_to($cx,        $cy + $size);
        $cr->line_to($cx-$size,  $cy);
        $cr->close_path;
        $fill ? $cr->fill_preserve : ();
        $cr->stroke;
    }
    elsif ($style eq '+') {
        $cr->move_to($cx - $size, $cy); $cr->line_to($cx + $size, $cy); $cr->stroke;
        $cr->move_to($cx, $cy - $size); $cr->line_to($cx, $cy + $size); $cr->stroke;
    }
    elsif ($style eq 'x') {
        $cr->move_to($cx-$size,$cy-$size); $cr->line_to($cx+$size,$cy+$size); $cr->stroke;
        $cr->move_to($cx+$size,$cy-$size); $cr->line_to($cx-$size,$cy+$size); $cr->stroke;
    }
    $cr->restore;
}

#

sub errorbar_y {
    my ($self, $xp, $yp, $ye_lo, $ye_hi, $capw) = @_;
    $capw //= 4;
    my $cr = $self->{cr};
    $cr->move_to($xp, $yp - $ye_hi);
    $cr->line_to($xp, $yp + $ye_lo);
    $cr->stroke;
    $cr->move_to($xp - $capw, $yp - $ye_hi);
    $cr->line_to($xp + $capw, $yp - $ye_hi);
    $cr->stroke;
    $cr->move_to($xp - $capw, $yp + $ye_lo);
    $cr->line_to($xp + $capw, $yp + $ye_lo);
    $cr->stroke;
}

#

# errorbar_y の水平版。$xe_lo/$xe_hi は画面座標系での左右オフセット（px）。
# cap は縦線で描く（errorbar_y の cap が横線であることと対称）。
sub errorbar_x {
    my ($self, $xp, $yp, $xe_lo, $xe_hi, $caph) = @_;
    $caph //= 4;
    my $cr = $self->{cr};
    $cr->move_to($xp - $xe_lo, $yp);
    $cr->line_to($xp + $xe_hi, $yp);
    $cr->stroke;
    $cr->move_to($xp - $xe_lo, $yp - $caph);
    $cr->line_to($xp - $xe_lo, $yp + $caph);
    $cr->stroke;
    $cr->move_to($xp + $xe_hi, $yp - $caph);
    $cr->line_to($xp + $xe_hi, $yp + $caph);
    $cr->stroke;
}

#

sub grid_line_h {
    my ($self, $x1, $x2, $yp, $color, $alpha) = @_;
    $color //= [0.8, 0.8, 0.8];
    $alpha //= 1.0;
    my $cr = $self->{cr};
    $cr->save;
    $cr->set_source_rgba(@$color, $alpha);
    $cr->set_line_width(0.8);
    $cr->set_dash(0, 4, 4);
    $cr->move_to($x1, $yp); $cr->line_to($x2, $yp); $cr->stroke;
    $cr->restore;
}

sub grid_line_v {
    my ($self, $xp, $y1, $y2, $color, $alpha) = @_;
    $color //= [0.8, 0.8, 0.8];
    $alpha //= 1.0;
    my $cr = $self->{cr};
    $cr->save;
    $cr->set_source_rgba(@$color, $alpha);
    $cr->set_line_width(0.8);
    $cr->set_dash(0, 4, 4);
    $cr->move_to($xp, $y1); $cr->line_to($xp, $y2); $cr->stroke;
    $cr->restore;
}

#

# align: 'left'/'center'/'right'  valign: 'top'/'middle'/'bottom'

sub text {
    my ($self, $x, $y, $str, %opt) = @_;
    my $cr     = $self->{cr};
    my $layout = $self->{pango};
    my $align  = $opt{align}  // 'left';
    my $valign = $opt{valign} // 'bottom';
    my $angle  = $opt{angle}  // 0;

    my $utf8_str = Encode::is_utf8($str) ? Encode::encode("UTF-8", $str) : $str;
    $layout->set_markup(_to_markup($str));
    my ($w, $h) = $layout->get_pixel_size();

    $cr->save;
    $cr->translate($x, $y);
    $cr->rotate(-$angle * 3.14159265358979 / 180) if $angle;

    my $dx = 0;
    my $dy = 0;
    $dx = -$w/2 if $align  eq 'center';
    $dx = -$w   if $align  eq 'right';
    $dy = -$h/2 if $valign eq 'middle';
    # valign='top': 基準点をテキスト上端に合わせる → 描画開始点(左上)は
    # そのまま基準点 (dy=0)。
    # valign='bottom': 基準点をテキスト下端に合わせる → 描画開始点は
    # 基準点よりテキスト高さ$h分上 (dy=-$h)。
    # NOTE (2026-06-19 修正): 旧実装は top/bottom 両方が dy=-$h になっており
    # 実質的に同じ動作(="bottom"相当)だった。X軸下側ラベル(valign=>'top'
    # で「目盛り線のすぐ下から書き始めたい」という意図)が、実際には
    # テキストが上にせり出して目盛り線と重なって見える原因になっていた。
    # labelsize を大きくするほど $h が増え、ズレ量(=$h)も大きくなるため
    # 重なりが目立ちやすかった。
    $dy = 0     if $valign eq 'top';
    $dy = -$h   if $valign eq 'bottom';

    $cr->move_to($dx, $dy);
    Pango::Cairo::show_layout($cr, $layout);
    $cr->restore;
}

sub text_width {
    my ($self, $str) = @_;
    my $utf8_str2 = Encode::is_utf8($str) ? Encode::encode("UTF-8", $str) : $str;
    $self->{pango}->set_markup(_to_markup($str));
    my ($w, $h) = $self->{pango}->get_pixel_size();
    return $w;
}

# fillplot
sub colored_rect {
    my ($self, $x, $y, $w, $h, $r, $g, $b, $a) = @_;
    $a //= 1.0;
    $self->{cr}->set_source_rgba($r, $g, $b, $a);
    $self->{cr}->rectangle($x, $y, $w, $h);
    $self->{cr}->fill;
}

# image_rgb($x, $y, $w, $h, $r, $g, $b, $alpha)
#   Draws a grid of colored cells as one image, in the rectangle
#   ($x, $y, $w, $h). $r, $g, $b are piddles of dims (ncol, nrow), values
#   0..1: element ($c, $r) is the cell in column $c (left to right) and
#   row $r (top to bottom). Each cell is scaled to w/ncol x h/nrow pixels
#   with no smoothing (nearest neighbour). Cells where any of $r, $g, $b is
#   not finite are left transparent. $alpha (default 1) applies to the
#   whole image.
#   It does what one colored_rect per cell does, but in one call.
sub image_rgb {
    my ($self, $x, $y, $w, $h, $r, $g, $b, $alpha) = @_;
    $alpha //= 1.0;
    my ($nc, $nr) = $r->dims;
    return unless $nc && $nr && $w > 0 && $h > 0;

    my $ok = $r->isfinite & $g->isfinite & $b->isfinite;
    # Cairo turns a double colour into 8 bits as floor((d*65535+0.5)/256)
    # (via a 16-bit value). Doing the same keeps each cell exactly the
    # colour that colored_rect would give it.
    my $to8 = sub {
        my $c = $_[0]->double->copy;
        $c->where(!$ok) .= 0;                   # NaN would not convert to an integer
        $c = $c->clip(0, 1);
        return (($c * 65535 + 0.5)->floor->ulong >> 8) * $ok;
    };
    # ARGB32 is one native-endian 32-bit word per pixel, premultiplied by
    # alpha: A<<24 | R<<16 | G<<8 | B. Opaque, so no premultiplication needed;
    # cells that are not finite are 0 (transparent).
    my $pix = ($ok->ulong * 0xFF << 24)
            | ($to8->($r) << 16) | ($to8->($g) << 8) | $to8->($b);
    $pix = $pix->copy;                          # own, contiguous data
    my $stride = Cairo::Format::stride_for_width('argb32', $nc);
    die "image_rgb: unexpected stride $stride for width $nc"
        unless $stride == 4 * $nc;
    my $buf = ${ $pix->get_dataref };
    my $img = Cairo::ImageSurface->create_for_data(
        $buf, 'argb32', $nc, $nr, $stride);
    $img->mark_dirty;

    my $cr  = $self->{cr};
    my $pat = Cairo::SurfacePattern->create($img);
    $pat->set_filter('nearest');
    my $m = Cairo::Matrix->init_scale($nc / $w, $nr / $h);
    $m->translate(-$x, -$y);
    $pat->set_matrix($m);

    $cr->save;
    $cr->rectangle($x, $y, $w, $h);
    $cr->clip;
    $cr->set_source($pat);
    if ($alpha < 1.0) { $cr->paint_with_alpha($alpha) } else { $cr->paint }
    $cr->restore;
    $img->finish;                               # done with $buf
    return 1;
}

# -------------------------------------------------------------
# finish
# -------------------------------------------------------------
sub finish {
    my ($self) = @_;
    if ($self->file eq ':memory:') {
        # In-memory mode: keep the surface alive; do NOT finish() it.
        # png_bytes() reads it.
        $self->{surface}->flush;
        return;
    }
    if ($self->file =~ /\.png$/i) {
        _argb32_surface_to_png_file($self->{surface}, $self->file);
        return;
    }
    $self->{surface}->finish if $self->{surface}->can('finish');
}

# -------------------------------------------------------------
# _argb32_surface_to_png_file — Cairo ARGB32 surface を wpng で高速書き出し
#
# Cairo ARGB32 メモリレイアウト (little-endian 32bit = 0xAARRGGBB):
#   byte[0]=B, byte[1]=G, byte[2]=R, byte[3]=A  (1ピクセル4バイト)
#
# wpng 要求フォーマット: PDL [H,W,3] float32, 値 0.0–1.0
#   PDL内部 (column-major) では [3,W,H] と等価
#
# 変換手順:
#   1. get_data() → スカラー W*H*4 bytes
#   2. PDL::byte [4,W,H] に詰める (index 0=B,1=G,2=R,3=A)
#   3. slice('2:0:-1,:,:') で [R,G,B] = [3,W,H] を取り出す
#   4. ->float / 255.0 で正規化
#   5. wpng($rgb, $filename)
# -------------------------------------------------------------
sub _argb32_surface_to_png_file {
    my ($surface, $filename) = @_;

    $surface->flush;

    unless ($HAVE_WPNG) {
        # PDL::IO::PNG absent: use Cairo's own PNG writer (~9.2ms). The
        # surface is already ARGB32, so Cairo writes it directly.
        $surface->write_to_png($filename);
        return;
    }

    my $raw = $surface->get_data;   # スカラー: W*H*4 bytes
    my $W   = $surface->get_width;
    my $H   = $surface->get_height;

    # PDL [4, W, H] uint8
    my $pdl = PDL->zeroes(PDL::byte, 4, $W, $H);
    ${ $pdl->get_dataref } = $raw;
    $pdl->upd_data;

    # BGRA → RGB: slice index 2=R, 1=G, 0=B → [3,W,H] float32
    my $rgb = $pdl->slice('2:0:-1,:,:')->float / 255.0;

    wpng($rgb, $filename);
}

# -------------------------------------------------------------
# _argb32_surface_to_png_bytes($surface [, $level])
#   Encodes an ARGB32 image surface as an RGBA PNG in memory, using only
#   PDL and Compress::Zlib (core Perl).
#   Cairo's ARGB32 pixel is one native-endian 32-bit word A<<24|R<<16|G<<8|B,
#   so on a little-endian machine the bytes are B, G, R, A; swapping bytes 0
#   and 2 gives R, G, B, A, which is PNG colour type 6. Cairo's colours are
#   premultiplied by alpha while PNG's are not, so this is only exact when
#   every pixel is opaque. Returns undef (the caller then uses another path)
#   on a big-endian machine or when any pixel is not opaque.
#   $level: zlib level, default $ENV{PDLCAIRO_PNG_LEVEL} // 1.
#   When PDL::IO::PNG has png_encode (from 41a25b0), the PNG is made by it
#   (libpng swaps B and R and drops the alpha byte: an RGB PNG); otherwise
#   it is assembled here in Perl as an RGBA PNG. The pixels are the same.
# -------------------------------------------------------------
my $LITTLE_ENDIAN = (pack('L', 1) eq "\1\0\0\0");
our $HAVE_PNG_ENCODE = $HAVE_WPNG && PDL::IO::PNG->can('png_encode') ? 1 : 0;

sub _argb32_surface_to_png_bytes {
    my ($surface, $level) = @_;
    return undef unless $LITTLE_ENDIAN;
    $level //= $ENV{PDLCAIRO_PNG_LEVEL} // 1;
    require Compress::Zlib;

    $surface->flush;
    my $w      = $surface->get_width;
    my $h      = $surface->get_height;
    my $stride = $surface->get_stride;
    return undef unless $w && $h && $stride % 4 == 0;

    my $px = zeroes(PDL::ulong, $stride / 4, $h);   # one word per pixel (+ row padding)
    ${ $px->get_dataref } = $surface->get_data;
    $px->upd_data;
    # opaque <=> alpha byte 0xFF <=> word >= 0xFF000000 (row padding excluded)
    return undef if $px->slice('0:' . ($w - 1) . ',:')->min < 0xFF000000;

    my $b = zeroes(PDL::byte, $stride, $h);
    ${ $b->get_dataref } = ${ $px->get_dataref };
    $b->upd_data;
    my $bgra = $b->reshape(4, $stride / 4, $h);

    if ($HAVE_PNG_ENCODE) {
        # ARGB32 rows have no padding (stride == 4*W), so $bgra is passed as
        # it is. A slice, even one that keeps everything, costs about 12 ms
        # at 1100x850 when png_encode makes it physical.
        my $img = ($stride == 4 * $w) ? $bgra
                                      : $bgra->slice(':,0:' . ($w - 1) . ',:')->copy;
        return PDL::IO::PNG::png_encode($img, bgr => 1, alpha => 0, level => $level);
    }
    my $blue = $bgra->slice('(0),:,:')->copy;
    $bgra->slice('(0),:,:') .= $bgra->slice('(2),:,:');
    $bgra->slice('(2),:,:') .= $blue;               # now R, G, B, A

    # each row: filter type 0 (none), then the row's pixels without padding
    my $raw = ${ $b->get_dataref };
    my $rl  = 4 * $w;
    my $data = join '', map { "\0" . substr($raw, $_ * $stride, $rl) } 0 .. $h - 1;

    my $chunk = sub {
        my ($type, $body) = @_;
        return pack('N', length $body) . $type . $body
             . pack('N', Compress::Zlib::crc32($type . $body));
    };
    return "\x89PNG\r\n\x1a\n"
         . $chunk->('IHDR', pack('NNCCCCC', $w, $h, 8, 6, 0, 0, 0))
         . $chunk->('IDAT', Compress::Zlib::compress($data, $level))
         . $chunk->('IEND', '');
}

# -------------------------------------------------------------
# png_bytes — return PNG as an in-memory scalar (no temp file).
# Only valid when constructed with file => ':memory:'.
# wpng経由 (tmpファイル) で高速化。
# -------------------------------------------------------------
sub png_bytes {
    my ($self) = @_;
    die "png_bytes: driver not in :memory: mode (file=" . $self->file . ")\n"
        unless $self->file eq ':memory:';

    # Fast path: encode the surface directly (no float conversion, no temp
    # file). Returns undef when it cannot (big-endian, or not fully opaque),
    # and then the path below is used.
    my $fast = _argb32_surface_to_png_bytes($self->{surface});
    return $fast if defined $fast;

    require File::Temp;
    my $tmp = File::Temp->new(SUFFIX => '.png', UNLINK => 1);
    my $tmpname = $tmp->filename;
    _argb32_surface_to_png_file($self->{surface}, $tmpname);
    $tmp->close;

    open my $fh, '<:raw', $tmpname
        or die "png_bytes: cannot read tmp PNG $tmpname: $!";
    local $/;
    my $bytes = <$fh>;
    close $fh;
    return $bytes;
}

1;
