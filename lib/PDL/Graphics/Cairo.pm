package PDL::Graphics::Cairo;

use strict;
use warnings;

our $VERSION = '0.01';

use Exporter 'import';
our @EXPORT_OK = qw(figure subplots);

use PDL::Graphics::Cairo::Figure;

sub figure {
    my (%args) = @_;
    return PDL::Graphics::Cairo::Figure->new(%args);
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

=head2 subplots($nrows, $ncols, %opts)

Creates a Figure with a grid of Axes and returns C<($fig, @axes)>.

  my ($fig, $ax1, $ax2) = subplots(1, 2, width => 1200, height => 500);

For a 2D grid, axes are returned row-by-row as array refs:

  my ($fig, @rows) = subplots(2, 2);
  my ($ax1, $ax2) = @{ $rows[0] };
  my ($ax3, $ax4) = @{ $rows[1] };

=head1 PREREQUISITES

  PDL           >= 2.0
  Cairo         (Perl binding, libcairo-perl)
  Cairo::GObject (libgtk3-perl)
  Pango         (Perl binding, libpango-perl)
  Moo           >= 2.0

On macOS with MacPorts:

  sudo port install p5-cairo p5-pango p5-moo

On Ubuntu/Debian:

  sudo apt install libcairo-perl libpango-perl libmoo-perl libgtk3-perl

=head1 AUTHOR

Your Name E<lt>you@example.comE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
