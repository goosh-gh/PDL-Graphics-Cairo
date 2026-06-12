package PDL::Graphics::Cairo::GridSpec;

use strict;
use warnings;
use Moo;
use Carp qw(croak);

# ============================================================
# Attributes
# ============================================================
has nrows  => (is => 'ro', required => 1);
has ncols  => (is => 'ro', required => 1);
has figure => (is => 'ro', required => 1);   # parent Figure

# Layout bounds: matplotlib convention
#   left/right : 0..1 from left edge of figure
#   bottom/top : 0..1 from BOTTOM edge of figure (matplotlib style)
#   So top=0.92 means 8% from top, bottom=0.08 means 8% from bottom
has left   => (is => 'ro', default => sub { 0.10 });
has right  => (is => 'ro', default => sub { 0.95 });
has top    => (is => 'ro', default => sub { 0.92 });   # fraction from bottom
has bottom => (is => 'ro', default => sub { 0.08 });   # fraction from bottom

# Spacing between subplots (fraction of average cell size)
has hspace => (is => 'ro', default => sub { 0.30 });
has wspace => (is => 'ro', default => sub { 0.25 });

# ============================================================
# at($row, $col)  →  GridSpecCell
#
# $row / $col can be:
#   integer        → single cell
#   "0:2"          → rows 0..1 (Python-style exclusive end)
#   ":"            → all rows/cols
#   aref [$r0,$r1] → explicit span (exclusive end)
# ============================================================
sub at {
    my ($self, $row, $col) = @_;
    my ($r0, $r1) = $self->_parse_slice($row, $self->nrows);
    my ($c0, $c1) = $self->_parse_slice($col, $self->ncols);
    return PDL::Graphics::Cairo::GridSpecCell->new(
        gridspec => $self,
        r0 => $r0, r1 => $r1,
        c0 => $c0, c1 => $c1,
    );
}

sub _parse_slice {
    my ($self, $spec, $n) = @_;
    if (!defined $spec) {
        return (0, $n);
    } elsif (ref $spec eq 'ARRAY') {
        return ($spec->[0], $spec->[1]);
    } elsif ($spec =~ /^(\d*):(\d*)$/) {
        my $lo = $1 ne '' ? $1 : 0;
        my $hi = $2 ne '' ? $2 : $n;
        return ($lo, $hi);
    } elsif ($spec =~ /^\d+$/) {
        return ($spec+0, $spec+1);
    } else {
        croak "GridSpec: invalid slice spec '$spec'";
    }
}

# ============================================================
# pixel_rect($r0,$r1,$c0,$c1)  →  (fig_x, fig_y, w, h) in pixels
#
# Cairo/screen coordinates: y increases downward.
# matplotlib convention: top/bottom are fractions from BOTTOM.
#   top=0.92 → pixel_y = (1-0.92)*fh = 0.08*fh  (near top of screen)
#   bottom=0.08 → pixel_y = (1-0.08)*fh = 0.92*fh (near bottom of screen)
# ============================================================
sub pixel_rect {
    my ($self, $r0, $r1, $c0, $c1) = @_;

    my $fw = $self->figure->width;
    my $fh = $self->figure->height;

    # Convert matplotlib fractions to pixel coordinates (y flipped)
    my $px_left   = $self->left   * $fw;
    my $px_right  = $self->right  * $fw;
    my $px_top    = (1 - $self->top)    * $fh;   # small pixel y = near top
    my $px_bottom = (1 - $self->bottom) * $fh;   # large pixel y = near bottom

    my $avail_w = $px_right - $px_left;
    my $avail_h = $px_bottom - $px_top;   # positive since px_bottom > px_top

    my $nr = $self->nrows;
    my $nc = $self->ncols;

    # Cell size (gap between cells = wspace/hspace * cell size)
    my $cell_w = $avail_w / ($nc + ($nc > 1 ? ($nc-1) * $self->wspace : 0));
    my $cell_h = $avail_h / ($nr + ($nr > 1 ? ($nr-1) * $self->hspace : 0));
    my $gap_w  = $cell_w * $self->wspace;
    my $gap_h  = $cell_h * $self->hspace;

    my $x0 = $px_left + $c0 * ($cell_w + $gap_w);
    my $y0 = $px_top  + $r0 * ($cell_h + $gap_h);
    my $x1 = $px_left + ($c1-1) * ($cell_w + $gap_w) + $cell_w;
    my $y1 = $px_top  + ($r1-1) * ($cell_h + $gap_h) + $cell_h;

    return (int($x0), int($y0), int($x1 - $x0), int($y1 - $y0));
}

1;

# ============================================================
package PDL::Graphics::Cairo::GridSpecCell;

use strict;
use warnings;
use Moo;

has gridspec => (is => 'ro', required => 1);
has r0       => (is => 'ro', required => 1);
has r1       => (is => 'ro', required => 1);
has c0       => (is => 'ro', required => 1);
has c1       => (is => 'ro', required => 1);

sub pixel_rect {
    my ($self) = @_;
    return $self->gridspec->pixel_rect(
        $self->r0, $self->r1, $self->c0, $self->c1);
}

sub row_span { ($_[0]->r0, $_[0]->r1) }
sub col_span { ($_[0]->c0, $_[0]->c1) }

1;
