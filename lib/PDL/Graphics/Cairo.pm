package PDL::Graphics::Cairo;

use strict;
use warnings;

our $VERSION = '0.01';

use Exporter 'import';
our @EXPORT_OK = qw(figure subplots imread);

use PDL::Graphics::Cairo::Figure;

sub figure {
    my (%args) = @_;
    return PDL::Graphics::Cairo::Figure->new(%args);
}

# new(%opts) — figure() の別名（OO 風の入口）。
# 主入口はあくまで figure()（matplotlib の plt.figure() 相当）だが、
# PDL::Graphics::Cairo->new(...) と書けるよう、先頭のクラス名を捨てて
# figure() に委譲する。返り値は PDL::Graphics::Cairo::Figure。
sub new {
    my $class = shift;
    return figure(@_);
}

sub subplots {
    my ($nrows, $ncols, %args) = @_;
    $nrows //= 1;
    $ncols //= 1;

    # figsize => [w, h] supported
    if (exists $args{figsize}) {
        my ($w, $h) = @{ $args{figsize} };
        $args{width}  = $w;
        $args{height} = $h;
        delete $args{figsize};
    }

    my $fig = PDL::Graphics::Cairo::Figure->new(%args);
    my @axes = $fig->subplots($nrows, $ncols);
    return ($fig, @axes);
}

# ==================================================================
# imread — 画像ファイルをimshow()用のPDL ndarrayとして読み込む
# PDL::IO::Image（高速）が使えればそちらを優先、なければrpicにフォールバック
# ==================================================================

sub imread {
    my ($path) = @_;
    die "imread: file not found: $path\n" unless -f $path;

    if (eval { require PDL::IO::PNG; 1 }) {
        # PDL::IO::PNG: [H,W,3] float32, row=0が上端 (2.5ms, libpngのみ)
        return PDL::IO::PNG::rpng($path);
    } elsif (eval { require PDL::IO::Image; 1 }) {
        # PDL::IO::Image: [W,H,3], row=0が上端 (5.3ms, FreeImage)
        # reorder(1,0,2) → [H,W,3]
        my $img = PDL::IO::Image->new_from_file($path);
        return $img->pixels_to_pdl->reorder(1,0,2)->float / 255.0;
    } else {
        # rpic fallback: [3,W,H], row=0が下端 (18.9ms)
        # reorder後H軸反転でrow=0を上端に揃える
        require PDL::IO::Pic;
        my $hwc = PDL::IO::Pic::rpic($path)->reorder(2,1,0)->float / 255.0;
        return $hwc->slice("-1:0,:,:");
    }
}


1;

__END__

=head1 NAME

PDL::Graphics::Cairo - matplotlib-inspired 2D plotting for PDL using Cairo

=head1 VERSION

0.01

=head1 SYNOPSIS

  use PDL;
  use PDL::Graphics::Cairo qw(figure subplots);

  my $x = sequence(200) / 10;

  # single plot
  my $fig = figure(width => 800, height => 500);
  my $ax  = $fig->axes();
  $ax->line($x, sin($x), color => 'blue', label => 'sin(x)');
  $ax->legend();
  $ax->set_grid(1);
  $fig->save('plot.png');

  # subplot grid
  my ($fig, $ax1, $ax2) = subplots(1, 2, width => 1200, height => 500);
  $ax1->scatter($x, sin($x));
  $ax2->hist(grandom(500), bins => 25);
  $fig->save('multi.png');

=head1 DESCRIPTION

PDL::Graphics::Cairo is a 2D plotting library for PDL, using Cairo and Pango
as the rendering backend. It provides a matplotlib-like API with the following
plot types:

  line          Line plot (linestyle, alpha, colormap)
  scatter       Scatter plot (marker shapes, scalar colormap)
  bar / barh    Vertical / horizontal bar chart
  hist          Histogram (bins, density, overlay)
  errorbar      Error bars (yerr, xerr, capsize)
  fill_between  Filled confidence bands
  step          Step function plot (pre/post)
  stem          Stem plot
  imshow        2D matrix image with colorbar
  contourf      Filled contour plot
  pie           Pie chart (explode, autopct)
  axhline/vline Horizontal / vertical reference lines
  axvspan/hspan Shaded span regions
  annotate      Arrow annotation

Axes features: autoscale, grid, legend, colorbar, twinx,
log scale (semilog-x/y, log-log), subplot grid, Unicode text via Pango.

Colormaps: viridis, plasma, jet, hot, cool, gray, RdBu.

Output formats: PNG, PDF, SVG (via Cairo).

=head1 FUNCTIONS

=head2 figure(%opts)

Creates and returns a Figure object.

  my $fig = figure(width => 800, height => 600);

Options: C<width>, C<height>, C<dpi>.

=head2 PDL::Graphics::Cairo->new(%opts)

Alias for C<figure()>, provided as an object-style entry point. Takes the
same options and returns a Figure object. C<figure()> remains the primary,
idiomatic entry point (mirroring matplotlib's C<plt.figure()>); C<new()> is
offered only as a convenience for callers who prefer a constructor form.

  my $fig = PDL::Graphics::Cairo->new(width => 800, height => 600);

=head2 subplots($nrows, $ncols, %opts)

Creates a Figure with a grid of Axes and returns C<($fig, @axes)>.

B<1×N or N×1 (single row/column):>

  my ($fig, $ax1, $ax2, $ax3) = subplots(1, 3, width => 1200, height => 400);

B<2D grid — axes returned row-by-row as array refs:>

  my ($fig, @rows) = subplots(2, 2);
  # Access by row/column index:
  my $ax = $rows[$r][$c];       # row $r, column $c (0-based)
  # Or unpack explicitly:
  my ($ax00, $ax01) = @{ $rows[0] };   # top row
  my ($ax10, $ax11) = @{ $rows[1] };   # bottom row

B<Flatten all axes:>

  my ($fig, @rows) = subplots(3, 4);
  my @all_axes = map { @$_ } @rows;    # 12 axes in row-major order

B<Common options:>

  width    => 1200   # figure width in pixels (default: 800)
  height   => 600    # figure height in pixels (default: 600)
  figsize  => [1200, 600]  # alternative to width/height

=cut

