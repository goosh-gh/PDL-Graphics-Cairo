package PDL::Graphics::Cairo;

use strict;
use warnings;

our $VERSION = '0.01';

use Exporter;
our @EXPORT_OK = qw(figure subplots subplot_mosaic imread);
our %EXPORT_TAGS = (
    gnuplot => [],
);

# カスタム import: ':gnuplot' タグが指定されたら互換レイヤーを注入する。
# Exporter::export($class, $caller, @symbols) で通常のエクスポートも処理する。
sub import {
    my $class  = shift;
    my @args   = @_;
    my $gnuplot = grep { $_ eq ':gnuplot' } @args;
    my @rest    = grep { $_ ne ':gnuplot' } @args;

    my $caller = caller(0);
    Exporter::export($class, $caller, @rest);

    if ($gnuplot) {
        require PDL::Graphics::Cairo::Compat::Gnuplot;
        PDL::Graphics::Cairo::Compat::Gnuplot::install();
    }
}

use Scalar::Util qw(looks_like_number);
use PDL::Graphics::Cairo::Figure;

sub figure {
    my (%args) = @_;
    if (my $fs = delete $args{figsize}) {
        my ($w, $h) = @$fs;
        $args{width}  //= int($w * 96) if defined $w;
        $args{height} //= int($h * 96) if defined $h;
    }
    return PDL::Graphics::Cairo::Figure->new(%args);
}

sub new {
    my $class = shift;
    return figure(@_);
}

sub subplot_mosaic {
    my ($layout, %opt) = @_;
    my $fig = PDL::Graphics::Cairo::Figure->new(
        width  => $opt{width}  // 640,
        height => $opt{height} // 480,
    );
    return $fig->subplot_mosaic($layout, %opt);
}

sub subplots {
    my @a = @_;
    my ($nrows, $ncols);
    if (@a && looks_like_number($a[0])) {
        $nrows = shift @a;
        $ncols = shift @a if @a && looks_like_number($a[0]);
    }

    my %args = @a;
    my $kw_nrows = delete $args{nrows};
    my $kw_ncols = delete $args{ncols};
    $nrows //= $kw_nrows;
    $ncols //= $kw_ncols;
    $nrows //= 1;
    $ncols //= 1;

    if (my $fs = delete $args{figsize}) {
        my ($w, $h) = @$fs;
        $args{width}  //= int($w * 96) if defined $w;
        $args{height} //= int($h * 96) if defined $h;
    }
    my $fig  = PDL::Graphics::Cairo::Figure->new(%args);
    my @axes = $fig->subplots($nrows, $ncols);
    # MxN のとき @axes は ArrayRef のリスト。フラット Axes と混同しないよう案内。
    if ($nrows > 1 && $ncols > 1) {
        warn "PDL::Graphics::Cairo: subplots($nrows,$ncols) — "
           . "return value contains ArrayRefs, not Axes objects.\n"
           . "  my (\$fig, \@rows) = subplots($nrows,$ncols);\n"
           . "  \$rows[\$r][\$c]->line(...);  # correct access\n";
    }
    return ($fig, @axes);
}

sub imread {
    my ($path) = @_;
    die "imread: file not found: $path\n" unless -f $path;

    if (eval { require PDL::IO::PNG; 1 }) {
        return PDL::IO::PNG::rpng($path);
    } elsif (eval { require PDL::IO::Image; 1 }) {
        my $img = PDL::IO::Image->new_from_file($path);
        return $img->pixels_to_pdl->reorder(1,0,2)->float / 255.0;
    } else {
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
  $ax->plot($x, sin($x), color => 'blue', label => 'sin(x)');
  $ax->legend();
  $ax->grid(1);
  $fig->save('plot.png');

  # subplot grid
  my ($fig, $ax1, $ax2) = subplots(1, 2, width => 1200, height => 500);
  $ax1->scatter($x, sin($x));
  $ax2->hist(grandom(500), bins => 25);
  $fig->save('multi.png');

  # gnuplot compat layer
  use PDL::Graphics::Cairo qw(figure subplots :gnuplot);
  my ($fig, $ax) = subplots();
  $ax->lines($x, sin($x), "with lines lw 2 lc 'steelblue' title 'sin'");
  $ax->gset("xrange [0:10]");
  $ax->gset("title 'My Plot'");
  $fig->save('plot.png');

=head1 DESCRIPTION

PDL::Graphics::Cairo is a 2D plotting library for PDL, using Cairo and Pango
as the rendering backend. It provides a matplotlib-like API with the following
plot types:

  plot/line     Line plot (linestyle, alpha, colormap)
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

=head2 figure(%opts)

  my $fig = figure(width => 800, height => 600);
  my $fig = figure(figsize => [800, 600]);

=head2 subplots($nrows, $ncols, %opts)

  my ($fig, $ax)        = subplots();
  my ($fig, $ax1, $ax2) = subplots(1, 2, figsize => [1200, 400]);
  my ($fig, @rows)      = subplots(2, 3);   # $rows[$r][$c]

=head2 imread($path)

Load an image as a [H,W,3] float32 PDL ndarray (row 0 = top).

=head1 GNUPLOT COMPATIBILITY

  use PDL::Graphics::Cairo qw(figure subplots :gnuplot);

Activates gnuplot-style aliases and style-string parsing:

  $ax->lines($x, $y, "with lines lw 2 lc 'red' title 'data'");
  $ax->points($x, $y, "with points pt 7 ps 0.5");
  $ax->linespoints($x, $y);
  $ax->gset("xrange [0:10]");
  $ax->gset("title 'My title'");
  $ax->gset("logscale y");
  $ax->gset("grid");

=cut
