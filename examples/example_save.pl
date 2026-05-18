#!/usr/bin/env perl
# =============================================================
# example_save.pl  --  PDL::Graphics::Cairo file format demo
#
# Run from PDL-Graphics-Cairo/ root:
#   perl -I./lib examples/example_save.pl
#   perl -I./lib examples/example_save.pl ~/Desktop   # custom output dir
#
# Output files:
#   plot.png   PNG  (raster, suitable for web)
#   plot.pdf   PDF  (vector, print quality)
#   plot.svg   SVG  (vector, web embedding)
# =============================================================

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure);

my $OUT = $ARGV[0] // '.';
die "Output directory not found: $OUT\n" unless -d $OUT;

# --- Build the plot ---
sub make_figure {
    my $x  = sequence(300) / 15;
    my $y1 = sin($x);
    my $y2 = cos($x);

    my $fig = figure(width => 800, height => 500);
    my $ax  = $fig->axes();

    $ax->title("PDL::Graphics::Cairo  --  File Output Demo");
    $ax->xlabel("x");
    $ax->ylabel("y");
    $ax->set_grid(1);

    $ax->line($x, $y1, color=>'blue',   lw=>2.0, label=>'sin(x)');
    $ax->line($x, $y2, color=>'orange', lw=>2.0, label=>'cos(x)', ls=>'dashed');
    $ax->fill_between($x, $y1, $y2,
        color=>'purple', alpha=>0.08, label=>'sin-cos band');
    $ax->axhline(0, color=>'gray', lw=>0.8, ls=>'dotted');
    $ax->legend(loc=>'upper right');

    return $fig;
}

# PNG
{
    my $file = "$OUT/plot.png";
    make_figure()->save($file);
    my $kb = int((-s $file) / 1024) || 1;
    printf "PNG: %-40s  (%d KB)\n", $file, $kb;
}

# PDF
{
    my $file = "$OUT/plot.pdf";
    make_figure()->save($file);
    my $kb = int((-s $file) / 1024) || 1;
    printf "PDF: %-40s  (%d KB)\n", $file, $kb;
}

# SVG
{
    my $file = "$OUT/plot.svg";
    make_figure()->save($file);
    my $kb = int((-s $file) / 1024) || 1;
    printf "SVG: %-40s  (%d KB)\n", $file, $kb;
}

print "\nDone. Open the files to compare formats.\n";
