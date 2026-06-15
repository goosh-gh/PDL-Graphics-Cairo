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

# height_ratios / width_ratios: arrayref of relative sizes per row/col
# e.g. height_ratios=>[1,1,1,0.3] makes last row 0.3x height of others
has height_ratios => (is => 'ro', default => sub { undef });
has width_ratios  => (is => 'ro', default => sub { undef });

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

    my $px_left   = $self->left   * $fw;
    my $px_right  = $self->right  * $fw;
    my $px_top    = (1 - $self->top)    * $fh;
    my $px_bottom = (1 - $self->bottom) * $fh;

    my $avail_w = $px_right - $px_left;
    my $avail_h = $px_bottom - $px_top;

    my $nr = $self->nrows;
    my $nc = $self->ncols;

    # ── height_ratios 対応 ────────────────────────────────────────
    # gap = hspace * 平均セル高さ (matplotlib互換)
    my @row_px;   # 各行のピクセル高さ
    if (my $hr = $self->height_ratios) {
        my $total_ratio = 0; $total_ratio += $_ for @$hr;
        # gap数 = nr-1、gap幅 = hspace * avail_h / (total_ratio + (nr-1)*hspace)
        my $unit = $avail_h / ($total_ratio + ($nr > 1 ? ($nr-1) * $self->hspace : 0));
        @row_px = map { $_ * $unit } @$hr;
    } else {
        my $cell_h = $avail_h / ($nr + ($nr > 1 ? ($nr-1) * $self->hspace : 0));
        @row_px = ($cell_h) x $nr;
    }
    my $gap_h = $nr > 1
        ? ($avail_h - do { my $s=0; $s+=$_ for @row_px; $s }) / ($nr - 1)
        : 0;

    # ── width_ratios 対応 ─────────────────────────────────────────
    my @col_px;
    if (my $wr = $self->width_ratios) {
        my $total_ratio = 0; $total_ratio += $_ for @$wr;
        my $unit = $avail_w / ($total_ratio + ($nc > 1 ? ($nc-1) * $self->wspace : 0));
        @col_px = map { $_ * $unit } @$wr;
    } else {
        my $cell_w = $avail_w / ($nc + ($nc > 1 ? ($nc-1) * $self->wspace : 0));
        @col_px = ($cell_w) x $nc;
    }
    my $gap_w = $nc > 1
        ? ($avail_w - do { my $s=0; $s+=$_ for @col_px; $s }) / ($nc - 1)
        : 0;

    # 各行/列の開始ピクセル位置を累積
    my @row_start = ($px_top);
    for my $r (0 .. $nr-2) {
        push @row_start, $row_start[-1] + $row_px[$r] + $gap_h;
    }
    my @col_start = ($px_left);
    for my $c (0 .. $nc-2) {
        push @col_start, $col_start[-1] + $col_px[$c] + $gap_w;
    }

    my $x0 = $col_start[$c0];
    my $y0 = $row_start[$r0];
    my $x1 = $col_start[$c1-1] + $col_px[$c1-1];
    my $y1 = $row_start[$r1-1] + $row_px[$r1-1];

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
