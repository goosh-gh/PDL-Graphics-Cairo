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
use List::Util qw(min max);

# -------------------------------------------------------------
#

# -------------------------------------------------------------
has width  => (is => 'ro', required => 1);
has height => (is => 'ro', required => 1);
has file   => (is => 'ro', default  => sub { 'out.png' });
has dpi    => (is => 'ro', default  => sub { 96 });

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

    # Pango 
    $self->{pango}   = Pango::Cairo::create_layout($cr);
    $self->{font_family} = 'Sans';
    $self->{font_size}   = 11;
    $self->{font_weight} = 'normal';
    $self->{font_slant}  = 'normal';
    $self->_update_pango_font();
}

sub _update_pango_font {
    my ($self) = @_;
    my $w = $self->{font_weight} eq 'bold' ? 'Bold ' : '';
    my $i = $self->{font_slant}  eq 'italic' ? 'Italic ' : '';
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
    $cr->move_to($x->at(0), $y->at(0));
    for my $i (1 .. $x->nelem - 1) {
        $cr->line_to($x->at($i), $y->at($i));
    }
    $cr->stroke;
}

# PDL piddle
sub filled_polygon {
    my ($self, $x, $y) = @_;
    my $cr = $self->{cr};
    return unless $x->nelem > 0;
    $cr->move_to($x->at(0), $y->at(0));
    for my $i (1 .. $x->nelem - 1) {
        $cr->line_to($x->at($i), $y->at($i));
    }
    $cr->close_path;
    $cr->fill;
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
    $dy = -$h   if $valign eq 'top';
    # bottom y=0Pango $h
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

# -------------------------------------------------------------
# finish
# -------------------------------------------------------------
sub finish {
    my ($self) = @_;
    if ($self->file eq ':memory:') {
        # In-memory mode: keep the surface alive; do NOT finish() it
        # (write_to_png_stream needs a live surface). png_bytes() reads it.
        $self->{surface}->flush;
        return;
    }
    if ($self->file =~ /\.png$/i) {
        $self->{surface}->write_to_png($self->file);
    }
    $self->{surface}->finish if $self->{surface}->can('finish');
}

# -------------------------------------------------------------
# png_bytes — return PNG as an in-memory scalar (no temp file).
# Only valid when constructed with file => ':memory:'.
# -------------------------------------------------------------
sub png_bytes {
    my ($self) = @_;
    die "png_bytes: driver not in :memory: mode (file=" . $self->file . ")\n"
        unless $self->file eq ':memory:';
    $self->{surface}->flush;
    my $png = '';
    $self->{surface}->write_to_png_stream(sub {
        my (undef, $chunk) = @_;
        $png .= $chunk;
        return 'success';
    });
    return $png;
}

1;
