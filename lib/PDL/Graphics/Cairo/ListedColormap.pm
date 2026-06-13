package PDL::Graphics::Cairo::ListedColormap;

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);

# ============================================================
# ListedColormap — discrete color list as a colormap
#
# Usage:
#   my $cmap = PDL::Graphics::Cairo::ListedColormap->new(['red','blue','green']);
#   my $cmap = PDL::Graphics::Cairo::ListedColormap->new([[1,0,0],[0,1,0],[0,0,1]]);
#   my $cmap = PDL::Graphics::Cairo::ListedColormap->new(\@colors, N=>256);
#
# Colors can be:
#   - Named color strings ('red', '#ff0000')
#   - [r,g,b] arrayrefs (0..1 range)
#   - [r,g,b,a] arrayrefs
# ============================================================

my %NAMED = (
    red     => [1,0,0],     green   => [0,0.502,0],
    blue    => [0,0,1],     yellow  => [1,1,0],
    cyan    => [0,1,1],     magenta => [1,0,1],
    white   => [1,1,1],     black   => [0,0,0],
    orange  => [1,0.647,0], purple  => [0.502,0,0.502],
    gray    => [0.5,0.5,0.5], grey  => [0.5,0.5,0.5],
    pink    => [1,0.753,0.796], brown => [0.647,0.165,0.165],
    lime    => [0,1,0],     navy    => [0,0,0.502],
    teal    => [0,0.502,0.502], maroon => [0.502,0,0],
    silver  => [0.753,0.753,0.753], gold => [1,0.843,0],
);

sub _parse_color {
    my ($c) = @_;
    return $c if ref $c eq 'ARRAY';
    if ($c =~ /^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$/) {
        return [hex($1)/255, hex($2)/255, hex($3)/255];
    }
    return $NAMED{lc($c)} // [0,0,0];
}

sub new {
    my ($class, $colors, %opt) = @_;
    die "ListedColormap: colors must be an arrayref" unless ref $colors eq 'ARRAY';
    my @parsed = map { _parse_color($_) } @$colors;
    return bless {
        colors => \@parsed,
        name   => $opt{name} // 'listed',
        N      => $opt{N} // scalar(@parsed),
    }, $class;
}

# rgb_at($t) — t in 0..1, returns (r,g,b)
sub rgb_at {
    my ($self, $t) = @_;
    $t = 0 if $t < 0;
    $t = 1 if $t > 1;
    my $n   = scalar @{ $self->{colors} };
    my $idx = int($t * $n);
    $idx = $n - 1 if $idx >= $n;
    return @{ $self->{colors}[$idx] };
}

# rgb_norm($val, $vmin, $vmax) — normalize then map
sub rgb_norm {
    my ($self, $val, $vmin, $vmax) = @_;
    my $t = ($vmax == $vmin) ? 0.5 : ($val - $vmin) / ($vmax - $vmin);
    return $self->rgb_at($t);
}

# lut($n) — return lookup table of n colors
sub lut {
    my ($self, $n) = @_;
    $n //= 256;
    return [map { [$self->rgb_at($_ / ($n-1))] } 0..$n-1];
}

sub name { $_[0]->{name} }

1;

# ============================================================
package PDL::Graphics::Cairo::Normalize;

use strict;
use warnings;
use POSIX qw(log10);
use Carp qw(croak);

# ============================================================
# Normalize — linear normalization vmin..vmax → 0..1
# Usage:
#   my $norm = PDL::Graphics::Cairo::Normalize->new(vmin=>0, vmax=>100);
#   my $t = $norm->call($val);   # or $norm->($val) if used as coderef
# ============================================================

sub new {
    my ($class, %opt) = @_;
    return bless {
        vmin => $opt{vmin} // 0,
        vmax => $opt{vmax} // 1,
        clip => $opt{clip} // 0,
    }, $class;
}

sub call {
    my ($self, $val) = @_;
    my ($vmin, $vmax) = ($self->{vmin}, $self->{vmax});
    return 0.5 if $vmax == $vmin;
    my $t = ($val - $vmin) / ($vmax - $vmin);
    if ($self->{clip}) {
        $t = 0 if $t < 0;
        $t = 1 if $t > 1;
    }
    return $t;
}

sub vmin { $_[0]->{vmin} }
sub vmax { $_[0]->{vmax} }

# ============================================================
package PDL::Graphics::Cairo::LogNorm;

use strict;
use warnings;
use POSIX qw(log10);
our @ISA = ('PDL::Graphics::Cairo::Normalize');

sub new {
    my ($class, %opt) = @_;
    my $self = PDL::Graphics::Cairo::Normalize::new($class, %opt);
    $self->{vmin} = $opt{vmin} // 1e-3;
    $self->{vmax} = $opt{vmax} // 1;
    $self->{base} = $opt{base} // 10;
    return $self;
}

sub call {
    my ($self, $val) = @_;
    my $base = $self->{base};
    $val = 1e-300 if $val <= 0;
    my $log_min = log($self->{vmin}) / log($base);
    my $log_max = log($self->{vmax}) / log($base);
    my $log_val = log($val)          / log($base);
    return 0.5 if $log_max == $log_min;
    my $t = ($log_val - $log_min) / ($log_max - $log_min);
    $t = 0 if $t < 0;
    $t = 1 if $t > 1;
    return $t;
}

# ============================================================
package PDL::Graphics::Cairo::BoundaryNorm;

use strict;
use warnings;
our @ISA = ('PDL::Graphics::Cairo::Normalize');

# BoundaryNorm(boundaries=>[0,1,5,10,50])
# Maps val into the bucket index, normalized 0..1
sub new {
    my ($class, %opt) = @_;
    my $bounds = $opt{boundaries} // [0, 1];
    my $self = bless {
        boundaries => $bounds,
        vmin       => $bounds->[0],
        vmax       => $bounds->[-1],
        ncolors    => $opt{ncolors} // (scalar(@$bounds) - 1),
        clip       => $opt{clip} // 0,
    }, $class;
    return $self;
}

sub call {
    my ($self, $val) = @_;
    my $bounds = $self->{boundaries};
    my $n      = scalar(@$bounds) - 1;
    for my $i (0..$n-1) {
        if ($val <= $bounds->[$i+1]) {
            return ($i + 0.5) / $n;
        }
    }
    return 1.0;
}

# ============================================================
package PDL::Graphics::Cairo::TwoSlopeNorm;

use strict;
use warnings;
our @ISA = ('PDL::Graphics::Cairo::Normalize');

# TwoSlopeNorm(vcenter=>0, vmin=>-10, vmax=>20)
# Maps vmin..vcenter to 0..0.5, vcenter..vmax to 0.5..1
sub new {
    my ($class, %opt) = @_;
    return bless {
        vmin    => $opt{vmin}    // -1,
        vcenter => $opt{vcenter} // 0,
        vmax    => $opt{vmax}    // 1,
    }, $class;
}

sub call {
    my ($self, $val) = @_;
    my ($vmin, $vc, $vmax) = ($self->{vmin}, $self->{vcenter}, $self->{vmax});
    if ($val <= $vc) {
        return 0.5 * ($val - $vmin) / ($vc - $vmin);
    } else {
        return 0.5 + 0.5 * ($val - $vc) / ($vmax - $vc);
    }
}

sub vmin    { $_[0]->{vmin} }
sub vmax    { $_[0]->{vmax} }
sub vcenter { $_[0]->{vcenter} }

1;
