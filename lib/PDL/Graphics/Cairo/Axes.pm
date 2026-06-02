package PDL::Graphics::Cairo::Axes;

# =============================================================
# Axes — matplotlib  Axes 
#
# :
#   line / scatter / bar / barh / hist / errorbar
#   fill_between / imshow / contourf / step / stem
#
# :
#   xlabel / ylabel / title / legend
#   xlim / ylim / set_aspect / grid
#   xscale / yscale (linear log  TODO)
#   xticks / yticks
# =============================================================

use strict;
use warnings;
use Moo;
use PDL;
# PDL exports hist; override with our method
no warnings "redefine";
# List::Util  min/max  PDL 
sub _min { my $m = shift; for (@_) { $m = $_ if $_ < $m } $m }
sub _max { my $m = shift; for (@_) { $m = $_ if $_ > $m } $m }

# Foreground color: depends on background set by PGPLOT layer.
# Cairo API always uses black foreground (white background).
# PGPLOT layer sets _PDLCAIRO_PGBG=black via cpgopen/cpgend.
sub _fg {
    return (lc($ENV{_PDLCAIRO_PGBG} // 'white') eq 'black')
        ? (1,1,1) : (0,0,0);
}
use POSIX qw(floor ceil);

use PDL::Graphics::Cairo::Transform::Linear;
use PDL::Graphics::Cairo::Transform::Log;
use PDL::Graphics::Cairo::Scale::Log;
use PDL::Graphics::Cairo::Tick qw(nice_ticks nice_range);
use PDL::Graphics::Cairo::ColorMap;

# PDL::Stats::Basic  optional
my $_has_pdl_stats = eval { require PDL::Stats::Basic; 1 } // 0;


# ------------------------------------------------------------------
# Figure subplot 
# ------------------------------------------------------------------
has width    => (is => 'rw', required => 1);
has height   => (is => 'rw', required => 1);
has fig_x    => (is => 'rw', default  => sub { 0 });
has fig_y    => (is => 'rw', default  => sub { 0 });

# ------------------------------------------------------------------
#  px
# ------------------------------------------------------------------
has margin_left   => (is => 'rw', default => sub { 72 });
has margin_right  => (is => 'rw', default => sub { 24 });
has margin_top    => (is => 'rw', default => sub { 40 });
has margin_bottom => (is => 'rw', default => sub { 56 });

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
has title  => (is => 'rw', default => sub { '' });
has xlabel => (is => 'rw', default => sub { '' });
has ylabel => (is => 'rw', default => sub { '' });

# ------------------------------------------------------------------
# 'linear' / 'log'
# ------------------------------------------------------------------
has xscale => (is => 'rw', default => sub { 'linear' });
has yscale => (is => 'rw', default => sub { 'linear' });

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
has grid        => (is => 'rw', default => sub { 0 });
has grid_color  => (is => 'rw', default => sub { [0.60, 0.60, 0.60] });

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
has xmin => (is => 'rw');
has xmax => (is => 'rw');
has ymin => (is => 'rw');
has ymax => (is => 'rw');

has _xmin_auto => (is => 'rw');
has _xmax_auto => (is => 'rw');
has _ymin_auto => (is => 'rw');
has _ymax_auto => (is => 'rw');

# ------------------------------------------------------------------
#  tick
# ------------------------------------------------------------------
has _xticks => (is => 'rw');
has _yticks => (is => 'rw');
has _xticklabels => (is => 'rw');
has _yticklabels => (is => 'rw');

# ------------------------------------------------------------------
# Render
# ------------------------------------------------------------------
has _queue   => (is => 'ro', default => sub { [] });
has _legends => (is => 'ro', default => sub { [] });

# ------------------------------------------------------------------
# imshow/contourf 
# ------------------------------------------------------------------
has _colorbar => (is => 'rw');

#

has colorbar_location => (is => 'rw', default => sub { 'right' });
has colorbar_width    => (is => 'rw', default => sub { 16 });
has colorbar_pad      => (is => 'rw', default => sub { 10 });
has colorbar_length   => (is => 'rw', default => sub { 1.0 });

# ==================================================================
# matplotlib tab10 
# ==================================================================
my @COLOR_CYCLE = (
    [0.122, 0.467, 0.706],  # blue
    [1.000, 0.498, 0.055],  # orange
    [0.173, 0.627, 0.173],  # green
    [0.839, 0.153, 0.157],  # red
    [0.580, 0.404, 0.741],  # purple
    [0.549, 0.337, 0.294],  # brown
    [0.890, 0.467, 0.761],  # pink
    [0.498, 0.498, 0.498],  # gray
    [0.737, 0.741, 0.133],  # olive
    [0.090, 0.745, 0.812],  # cyan
);

has _color_idx => (is => 'rw', default => sub { 0 });

sub _next_color {
    my ($self) = @_;
    my $c = $COLOR_CYCLE[$self->_color_idx % scalar @COLOR_CYCLE];
    $self->_color_idx($self->_color_idx + 1);
    return $c;
}

# : 'red' / '#rrggbb' / [r,g,b]
sub _parse_color {
    my ($self, $c) = @_;
    return $c if ref($c) eq 'ARRAY';
    if ($c =~ /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i) {
        return [hex($1)/255, hex($2)/255, hex($3)/255];
    }
    my %named = (
        aqua                   => [0.000, 1.000, 1.000],
        b                      => [0.000, 0.000, 1.000],
        black                  => [0.000, 0.000, 0.000],
        blue                   => [0.000, 0.000, 1.000],
        blueviolet             => [0.541, 0.169, 0.886],
        brown                  => [0.647, 0.165, 0.165],
        burlywood              => [0.871, 0.722, 0.529],
        c                      => [0.000, 0.749, 0.749],
        cadetblue              => [0.373, 0.620, 0.627],
        chocolate              => [0.824, 0.412, 0.118],
        coral                  => [1.000, 0.498, 0.314],
        cornflowerblue         => [0.392, 0.584, 0.929],
        crimson                => [0.863, 0.078, 0.235],
        cyan                   => [0.000, 1.000, 1.000],
        darkblue               => [0.000, 0.000, 0.545],
        darkcyan               => [0.000, 0.545, 0.545],
        darkgray               => [0.663, 0.663, 0.663],
        darkgreen              => [0.000, 0.392, 0.000],
        darkkhaki              => [0.741, 0.718, 0.420],
        darkolivegreen         => [0.333, 0.420, 0.184],
        darkorange             => [1.000, 0.549, 0.000],
        darkred                => [0.545, 0.000, 0.000],
        darksalmon             => [0.914, 0.588, 0.478],
        darkslateblue          => [0.282, 0.239, 0.545],
        darkslategray          => [0.184, 0.310, 0.310],
        darkturquoise          => [0.000, 0.808, 0.820],
        darkviolet             => [0.580, 0.000, 0.827],
        deeppink               => [1.000, 0.078, 0.576],
        deepskyblue            => [0.000, 0.749, 1.000],
        dimgray                => [0.412, 0.412, 0.412],
        dodgerblue             => [0.118, 0.565, 1.000],
        firebrick              => [0.698, 0.133, 0.133],
        forestgreen            => [0.133, 0.545, 0.133],
        fuchsia                => [1.000, 0.000, 1.000],
        g                      => [0.000, 0.502, 0.000],
        gold                   => [1.000, 0.843, 0.000],
        gray                   => [0.502, 0.502, 0.502],
        green                  => [0.000, 0.502, 0.000],
        grey                   => [0.502, 0.502, 0.502],
        hotpink                => [1.000, 0.412, 0.706],
        indianred              => [0.804, 0.361, 0.361],
        ivory                  => [1.000, 1.000, 0.941],
        k                      => [0.000, 0.000, 0.000],
        khaki                  => [0.941, 0.902, 0.549],
        lavender               => [0.902, 0.902, 0.980],
        lightblue              => [0.678, 0.847, 0.902],
        lightcoral             => [0.941, 0.502, 0.502],
        lightcyan              => [0.878, 1.000, 1.000],
        lightgray              => [0.827, 0.827, 0.827],
        lightpink              => [1.000, 0.714, 0.757],
        lightsalmon            => [1.000, 0.627, 0.478],
        lightskyblue           => [0.529, 0.808, 0.980],
        lightyellow            => [1.000, 1.000, 0.878],
        lime                   => [0.000, 1.000, 0.000],
        limegreen              => [0.196, 0.804, 0.196],
        m                      => [0.749, 0.000, 0.749],
        magenta                => [1.000, 0.000, 1.000],
        maroon                 => [0.502, 0.000, 0.000],
        mediumblue             => [0.000, 0.000, 0.804],
        mediumpurple           => [0.576, 0.439, 0.859],
        mediumseagreen         => [0.235, 0.702, 0.443],
        mediumslateblue        => [0.482, 0.408, 0.933],
        mediumturquoise        => [0.282, 0.820, 0.800],
        midnightblue           => [0.098, 0.098, 0.439],
        navy                   => [0.000, 0.000, 0.502],
        olive                  => [0.502, 0.502, 0.000],
        olivedrab              => [0.420, 0.557, 0.137],
        orange                 => [1.000, 0.647, 0.000],
        orangered              => [1.000, 0.271, 0.000],
        orchid                 => [0.855, 0.439, 0.839],
        peru                   => [0.804, 0.522, 0.247],
        pink                   => [1.000, 0.753, 0.796],
        plum                   => [0.867, 0.627, 0.867],
        purple                 => [0.502, 0.000, 0.502],
        r                      => [1.000, 0.000, 0.000],
        red                    => [1.000, 0.000, 0.000],
        royalblue              => [0.255, 0.412, 0.882],
        saddlebrown            => [0.545, 0.271, 0.075],
        salmon                 => [0.980, 0.502, 0.447],
        sandybrown             => [0.957, 0.643, 0.376],
        seagreen               => [0.180, 0.545, 0.341],
        sienna                 => [0.627, 0.322, 0.176],
        silver                 => [0.753, 0.753, 0.753],
        skyblue                => [0.529, 0.808, 0.922],
        slateblue              => [0.416, 0.353, 0.804],
        slategray              => [0.439, 0.502, 0.565],
        snow                   => [1.000, 0.980, 0.980],
        springgreen            => [0.000, 1.000, 0.502],
        steelblue              => [0.275, 0.510, 0.706],
        tan                    => [0.824, 0.706, 0.549],
        teal                   => [0.000, 0.502, 0.502],
        thistle                => [0.847, 0.749, 0.847],
        tomato                 => [1.000, 0.388, 0.278],
        turquoise              => [0.251, 0.878, 0.816],
        violet                 => [0.933, 0.510, 0.933],
        w                      => [1.000, 1.000, 1.000],
        wheat                  => [0.961, 0.871, 0.702],
        white                  => [1.000, 1.000, 1.000],
        y                      => [0.749, 0.749, 0.000],
        yellow                 => [1.000, 1.000, 0.000],
    );
    return $named{lc($c)} if exists $named{lc($c)};
    return [0,0,0];
}

# ==================================================================
# autoscale 
# ==================================================================
sub _expand_range {
    my ($self, $xs, $ys) = @_;
    # $xs, $ys  PDL piddle

    my ($lx,$hx) = $xs->minmax;
    my ($ly,$hy) = $ys->minmax;

    $self->_xmin_auto(defined $self->_xmin_auto
        ? PDL::Graphics::Cairo::Axes::_min($self->_xmin_auto, $lx) : $lx);
    $self->_xmax_auto(defined $self->_xmax_auto
        ? PDL::Graphics::Cairo::Axes::_max($self->_xmax_auto, $hx) : $hx);
    $self->_ymin_auto(defined $self->_ymin_auto
        ? PDL::Graphics::Cairo::Axes::_min($self->_ymin_auto, $ly) : $ly);
    $self->_ymax_auto(defined $self->_ymax_auto
        ? PDL::Graphics::Cairo::Axes::_max($self->_ymax_auto, $hy) : $hy);
}

sub _finalize_range {
    my ($self) = @_;

    #

    my $xmn = $self->xmin // $self->_xmin_auto // 0;
    my $xmx = $self->xmax // $self->_xmax_auto // 1;
    my $ymn = $self->ymin // $self->_ymin_auto // 0;
    my $ymx = $self->ymax // $self->_ymax_auto // 1;

    # nice margin
    unless (defined $self->xmin && defined $self->xmax) {
        ($xmn, $xmx) = nice_range($xmn, $xmx, 0.03);
    }
    unless (defined $self->ymin && defined $self->ymax) {
        ($ymn, $ymx) = nice_range($ymn, $ymx, 0.05);
    }

    #

    $xmx = $xmn + 1 if $xmn == $xmx;
    $ymx = $ymn + 1 if $ymn == $ymx;

    $self->xmin($xmn);
    $self->xmax($xmx);
    $self->ymin($ymn);
    $self->ymax($ymx);
}

# ==================================================================
#  API — 
# ==================================================================

# ---- line --------------------------------------------------------
sub line {
    my ($self, $x, $y, %opt) = @_;
    $x = pdl($x) unless ref($x) && $x->isa('PDL');
    $y = pdl($y) unless ref($y) && $y->isa('PDL');

    my $color = exists $opt{color}
        ? $self->_parse_color($opt{color})
        : $self->_next_color();

    push @{ $self->_queue }, {
        type      => 'line',
        x         => $x, y => $y,
        color     => $color,
        lw        => $opt{linewidth}  // $opt{lw} // 1.5,
        linestyle => $opt{linestyle}  // $opt{ls} // 'solid',
        alpha     => $opt{alpha}      // 1.0,
        label     => $opt{label}      // undef,
    };
    $self->_expand_range($x, $y);
    if (defined $opt{label}) {
        push @{ $self->_legends }, { type=>'line', color=>$color, label=>$opt{label},
            lw=>$opt{linewidth}//1.5, ls=>$opt{linestyle}//'solid' };
    }
    return $self;
}

*polyline = \&line;

# ---- scatter -----------------------------------------------------
sub scatter {
    my ($self, $x, $y, %opt) = @_;
    $x = pdl($x) unless ref($x) && $x->isa('PDL');
    $y = pdl($y) unless ref($y) && $y->isa('PDL');

    my $color = exists $opt{color} || exists $opt{c}
        ? $self->_parse_color($opt{color} // $opt{c})
        : $self->_next_color();

    push @{ $self->_queue }, {
        type   => 'scatter',
        x      => $x, y => $y,
        color  => $color,
        size   => $opt{s}      // $opt{size}   // 4,
        marker => $opt{marker} // 'o',
        alpha  => $opt{alpha}  // 0.8,
        label  => $opt{label}  // undef,
        # c  PDL 
        cdata  => (ref($opt{c}) && $opt{c}->isa('PDL')) ? $opt{c} : undef,
        cmap   => $opt{cmap}   // 'viridis',
    };
    $self->_expand_range($x, $y);
    # cdata 
    if (ref($opt{c}) && $opt{c}->isa('PDL')) {
        my ($cdmin, $cdmax) = $opt{c}->minmax;
        my $cmap_obj = PDL::Graphics::Cairo::ColorMap->new($opt{cmap} // 'viridis');
        $self->_colorbar({ cmap => $cmap_obj, vmin => $cdmin, vmax => $cdmax });
    }
    if (defined $opt{label}) {
        push @{ $self->_legends }, { type=>'marker', color=>$color,
            label=>$opt{label}, marker=>$opt{marker}//'o' };
    }
    return $self;
}

# ---- bar ---------------------------------------------------------
sub bar {
    my ($self, $x, $height, %opt) = @_;
    $x      = pdl($x)      unless ref($x)      && $x->isa('PDL');
    $height = pdl($height)  unless ref($height) && $height->isa('PDL');

    my $width  = $opt{width}  // 0.8;
    my $bottom = $opt{bottom} // 0;
    my $color  = exists $opt{color}
        ? $self->_parse_color($opt{color}) : $self->_next_color();

    push @{ $self->_queue }, {
        type   => 'bar',
        x      => $x,
        height => $height,
        width  => $width,
        bottom => $bottom,
        color  => $color,
        edge   => $opt{edgecolor} // [0,0,0],
        alpha  => $opt{alpha}     // 1.0,
        label  => $opt{label}     // undef,
    };
    #

    my $w_pdl = ref($width) && UNIVERSAL::isa($width,'PDL') ? $width : pdl($width);
    my $xmin = ($x - $w_pdl/2)->min;
    my $xmax = ($x + $w_pdl/2)->max;
    my $ymax = ($height + $bottom)->max;
    $self->_expand_range(pdl($xmin,$xmax), pdl($bottom,$ymax));

    if (defined $opt{label}) {
        push @{ $self->_legends }, { type=>'rect', color=>$color, label=>$opt{label} };
    }
    return $self;
}

# ---- barh --------------------------------------------------------
sub barh {
    my ($self, $y, $width, %opt) = @_;
    $y     = pdl($y)     unless ref($y)     && $y->isa('PDL');
    $width = pdl($width) unless ref($width) && $width->isa('PDL');

    my $height = $opt{height} // 0.8;
    my $left   = $opt{left}   // 0;
    my $color  = exists $opt{color}
        ? $self->_parse_color($opt{color}) : $self->_next_color();

    push @{ $self->_queue }, {
        type   => 'barh',
        y      => $y,
        width  => $width,
        height => $height,
        left   => $left,
        color  => $color,
        edge   => $opt{edgecolor} // [0,0,0],
        alpha  => $opt{alpha}     // 1.0,
        label  => $opt{label}     // undef,
    };
    my $ymin = ($y - $height/2)->min;
    my $ymax = ($y + $height/2)->max;
    my $xmax = ($width + $left)->max;
    $self->_expand_range(pdl($left, $xmax), pdl($ymin,$ymax));
    return $self;
}

# ---- hist --------------------------------------------------------
sub histogram {
    my ($self, $data, %opt) = @_;
    $data = pdl($data) unless ref($data) && $data->isa('PDL');

    my $bins    = $opt{bins}  // 10;
    my $dmin    = $data->min;
    my $dmax    = $data->max;
    my $bw      = ($dmax - $dmin) / $bins;
    $bw = 1 if $bw == 0;

    #

    my @counts = (0) x $bins;
    my @vals = list($data);
    for my $v (@vals) {
        my $b = int(($v - $dmin) / $bw);
        $b = $bins - 1 if $b >= $bins;
        $b = 0 if $b < 0;
        $counts[$b]++;
    }

    my $density = $opt{density} // 0;
    if ($density) {
        my $total = scalar @vals;
        @counts = map { $_ / ($total * $bw) } @counts;
    }

    my $color = exists $opt{color}
        ? $self->_parse_color($opt{color}) : $self->_next_color();

    my @xs = map { $dmin + $_ * $bw } 0..$bins;
    push @{ $self->_queue }, {
        type    => 'hist',
        edges   => pdl(@xs),
        counts  => pdl(@counts),
        color   => $color,
        alpha   => $opt{alpha} // 0.8,
        label   => $opt{label} // undef,
    };
    $self->_expand_range(pdl($dmin,$dmax), pdl(0, PDL::Graphics::Cairo::Axes::_max(@counts)));
    if (defined $opt{label}) {
        push @{ $self->_legends }, { type=>'rect', color=>$color, label=>$opt{label} };
    }
    return $self;
}

# ---- errorbar ----------------------------------------------------
sub errorbar {
    my ($self, $x, $y, %opt) = @_;
    $x = pdl($x) unless ref($x) && $x->isa('PDL');
    $y = pdl($y) unless ref($y) && $y->isa('PDL');

    my $yerr = exists $opt{yerr} ? pdl($opt{yerr}) : undef;
    my $xerr = exists $opt{xerr} ? pdl($opt{xerr}) : undef;

    my $color = exists $opt{color}
        ? $self->_parse_color($opt{color}) : $self->_next_color();

    push @{ $self->_queue }, {
        type   => 'errorbar',
        x      => $x, y => $y,
        yerr   => $yerr, xerr => $xerr,
        color  => $color,
        lw     => $opt{linewidth} // 1.5,
        capsize=> $opt{capsize}   // 4,
        marker => $opt{marker}    // 'o',
        ms     => $opt{markersize}// 4,
        label  => $opt{label}     // undef,
    };
    my $ylo = defined($yerr) ? ($y - $yerr)->min : $y->min;
    my $yhi = defined($yerr) ? ($y + $yerr)->max : $y->max;
    $self->_expand_range($x, pdl($ylo,$yhi));
    if (defined $opt{label}) {
        push @{ $self->_legends }, { type=>'line', color=>$color, label=>$opt{label}, lw=>1.5 };
    }
    return $self;
}

# ---- fill_between ------------------------------------------------
sub fill_between {
    my ($self, $x, $y1, $y2, %opt) = @_;
    $x  = pdl($x)  unless ref($x)  && $x->isa('PDL');
    $y1 = pdl($y1) unless ref($y1) && $y1->isa('PDL');
    $y2 = pdl($y2) unless ref($y2) && $y2->isa('PDL');

    my $color = exists $opt{color}
        ? $self->_parse_color($opt{color}) : $self->_next_color();

    push @{ $self->_queue }, {
        type  => 'fill_between',
        x     => $x, y1 => $y1, y2 => $y2,
        color => $color,
        alpha => $opt{alpha} // 0.3,
        label => $opt{label} // undef,
    };
    $self->_expand_range($x, $y1->append($y2));
    return $self;
}

# ---- imshow ------------------------------------------------------
sub imshow {
    my ($self, $data, %opt) = @_;
    # $data  2D PDL (rows x cols)  3D (rows x cols x 3) RGB
    $data = pdl($data) unless ref($data) && $data->isa('PDL');

    my $cmap  = PDL::Graphics::Cairo::ColorMap->new($opt{cmap} // 'viridis');
    my $vmin  = $opt{vmin} // $data->min;
    my $vmax  = $opt{vmax} // $data->max;

    push @{ $self->_queue }, {
        type  => 'imshow',
        data  => $data,
        cmap  => $cmap,
        vmin  => $vmin,
        vmax  => $vmax,
        alpha => $opt{alpha} // 1.0,
        origin => $opt{origin} // 'upper',
    };

    # axes  shape 
    my @dims = $data->dims;
    my ($rows, $cols) = @dims;
    $self->xmin(0); $self->xmax($cols);
    $self->ymin(0); $self->ymax($rows);

    # RGB画像（3次元）はカラーバー不要
    unless (scalar @dims == 3 && $dims[2] == 3) {
        $self->_colorbar({ cmap => $cmap, vmin => $vmin, vmax => $vmax });
    }

    return $self;
}

# ---- step --------------------------------------------------------
sub step {
    my ($self, $x, $y, %opt) = @_;
    $x = pdl($x) unless ref($x) && $x->isa('PDL');
    $y = pdl($y) unless ref($y) && $y->isa('PDL');

    my $color = exists $opt{color}
        ? $self->_parse_color($opt{color}) : $self->_next_color();
    push @{ $self->_queue }, {
        type      => 'step',
        x         => $x, y => $y,
        color     => $color,
        lw        => $opt{linewidth} // 1.5,
        linestyle => $opt{linestyle} // 'solid',
        where     => $opt{where}     // 'pre',
        label     => $opt{label}     // undef,
    };
    $self->_expand_range($x, $y);
    if (defined $opt{label}) {
        push @{ $self->_legends }, { type=>'line', color=>$color, label=>$opt{label}, lw=>1.5 };
    }
    return $self;
}

# ---- stem --------------------------------------------------------
sub stem {
    my ($self, $x, $y, %opt) = @_;
    $x = pdl($x) unless ref($x) && $x->isa('PDL');
    $y = pdl($y) unless ref($y) && $y->isa('PDL');

    my $color = exists $opt{color}
        ? $self->_parse_color($opt{color}) : $self->_next_color();
    push @{ $self->_queue }, {
        type   => 'stem',
        x      => $x, y => $y,
        color  => $color,
        lw     => $opt{linewidth} // 1.0,
        ms     => $opt{markersize}// 4,
        label  => $opt{label}     // undef,
    };
    $self->_expand_range($x, $y->append(pdl(0)));
    return $self;
}

# ---- errorbar_stats -----------------------------------------------
# PDL::Stats::Basic 
# data: arrayref of PDL1 2D PDL (obs x groups)
# type: 'sem'(default) / 'sd' / 'ci95' / 'iqr'
sub errorbar_stats {
    my ($self, $data, %opt) = @_;

    die "errorbar_stats requires PDL::Stats::Basic\n  cpan PDL::Stats\n"
        unless $_has_pdl_stats;

    my @groups = _normalize_groups($data);
    my $n      = scalar @groups;
    my $x      = exists $opt{x} ? pdl($opt{x}) : sequence($n);
    my $type   = $opt{type} // 'sem';

    my @means = map { $_->average } @groups;
    my @errs  = do {
        if    ($type eq 'sem')  { map { $_->se          } @groups }
        elsif ($type eq 'sd')   { map { $_->stdv        } @groups }
        elsif ($type eq 'ci95') { map { $_->se * 1.96   } @groups }
        elsif ($type eq 'iqr')  { map { ($_->pct(0.75) - $_->pct(0.25))/2 } @groups }
        else  { die "errorbar_stats: unknown type '$type'\n" }
    };

    return $self->errorbar($x, pdl(@means),
        yerr       => pdl(@errs),
        color      => $opt{color}      // undef,
        capsize    => $opt{capsize}    // 5,
        marker     => $opt{marker}     // 'o',
        markersize => $opt{markersize} // 4,
        lw         => $opt{lw}         // 0,
        label      => $opt{label}      // undef,
    );
}

# ---- boxplot ------------------------------------------------------
# Tukey 
# data: arrayref of PDL  2D PDL (obs x groups)
sub boxplot {
    my ($self, $data, %opt) = @_;

    die "boxplot requires PDL::Stats::Basic\n  cpan PDL::Stats\n"
        unless $_has_pdl_stats;

    my @groups  = _normalize_groups($data);
    my $n       = scalar @groups;
    my @xs      = exists $opt{positions} ? @{$opt{positions}} : (0..$n-1);
    my $width   = $opt{width}      // 0.5;
    my $showmean= $opt{showmeans}  // 0;
    my $showcaps= $opt{showcaps}   // 1;
    my $showfli = $opt{showfliers} // 1;

    my $fc = exists $opt{color}
        ? $self->_parse_color($opt{color})
        : [0.70, 0.85, 0.95];
    my $ec = $self->_parse_color($opt{edgecolor} // 'black');

    my (@ymins, @ymaxs);
    for my $i (0..$n-1) {
        my $g   = $groups[$i];
        my $xc  = $xs[$i];
        my $hw  = $width / 2;

        my $med = $g->median;
        my $q1  = $g->pct(0.25);
        my $q3  = $g->pct(0.75);
        my $iqr = $q3 - $q1;
        my $mn  = $g->average;
        my $wlo = $q1 - 1.5 * $iqr;
        my $whi = $q3 + 1.5 * $iqr;

        #  = /
        my $s       = $g->qsort;
        my $wlo_val = $s->where($s >= $wlo)->min;
        my $whi_val = $s->where($s <= $whi)->max;

        push @ymins, $wlo_val;
        push @ymaxs, $whi_val;

        #

        if ($showfli) {
            my $out = $g->where(($g < $wlo_val) | ($g > $whi_val));
            if ($out->nelem > 0) {
                push @{ $self->_queue }, {
                    type => 'box_fliers',
                    xc   => $xc, data => $out, color => $ec,
                };
            }
        }

        push @{ $self->_queue }, {
            type      => 'boxplot_item',
            xc        => $xc, hw => $hw,
            q1        => $q1, q3 => $q3, med => $med, mean => $mn,
            wlo       => $wlo_val, whi => $whi_val,
            facecolor => $fc, edgecolor => $ec,
            showmean  => $showmean, showcaps => $showcaps,
        };
    }

    $self->_expand_range(
        pdl(map { ($xs[$_]-$width/2, $xs[$_]+$width/2) } 0..$n-1),
        pdl(@ymins, @ymaxs),
    );

    #

    if (defined $opt{label}) {
        push @{ $self->_legends }, {
            type  => 'rect',
            color => $fc,
            label => $opt{label},
        };
    }
    return $self;
}

# ---- violinplot --------------------------------------------------
# Gaussian KDE 
sub violinplot {
    my ($self, $data, %opt) = @_;

    die "violinplot requires PDL::Stats::Basic\n  cpan PDL::Stats\n"
        unless $_has_pdl_stats;

    my @groups  = _normalize_groups($data);
    my $n       = scalar @groups;
    my @xs      = exists $opt{positions} ? @{$opt{positions}} : (0..$n-1);
    my $width   = $opt{width}       // 0.7;
    my $showmed = $opt{showmedians} // 1;
    my $showmean= $opt{showmeans}   // 0;
    my $showbox = $opt{showbox}     // 1;
    my $pts     = $opt{points}      // 100;

    my (@ymins, @ymaxs);
    for my $i (0..$n-1) {
        my $g   = $groups[$i];
        my $xc  = $xs[$i];
        my $hw  = $width / 2;

        my ($gmin, $gmax) = ($g->min, $g->max);
        push @ymins, $gmin; push @ymaxs, $gmax;

        # Silverman bandwidth
        my $std = $g->stdv || ($gmax - $gmin) * 0.1 || 1;
        my $h   = 1.06 * $std * ($g->nelem ** (-0.2));

        my $ys  = $gmin + sequence($pts) * ($gmax - $gmin) / ($pts - 1);
        my $kde = zeroes($pts);
        my $c   = 1.0 / (sqrt(2*3.14159265358979) * $h * $g->nelem);
        for my $j (0..$g->nelem-1) {
            my $u = ($ys - $g->at($j)) / $h;
            $kde += $c * exp(-0.5 * $u * $u);
        }

        my $kmax = $kde->max;
        my $knorm = $kmax > 0 ? $kde * ($hw / $kmax) : $kde;

        # colors:  / color: 
        my $color;
        if (exists $opt{colors} && ref($opt{colors}) eq 'ARRAY') {
            my $ci = $i % scalar @{$opt{colors}};
            $color = $self->_parse_color($opt{colors}[$ci]);
        } elsif (exists $opt{color}) {
            $color = $self->_parse_color($opt{color});
        } else {
            $color = $self->_next_color();
        }

        push @{ $self->_queue }, {
            type     => 'violin_item',
            xc       => $xc, ys => $ys, kde => $knorm,
            color    => $color,
            showmed  => $showmed, showmean => $showmean, showbox => $showbox,
            median   => $g->median, mean => $g->average,
            q1       => $g->pct(0.25), q3 => $g->pct(0.75),
        };
    }

    $self->_expand_range(
        pdl(map { ($xs[$_]-$width/2, $xs[$_]+$width/2) } 0..$n-1),
        pdl(@ymins, @ymaxs),
    );

    # colors→1color→→
    if (defined $opt{label}) {
        my $lc;
        if    (exists $opt{colors} && ref($opt{colors}) eq 'ARRAY') {
            $lc = $self->_parse_color($opt{colors}[0]);
        } elsif (exists $opt{color}) {
            $lc = $self->_parse_color($opt{color});
        } else {
            $lc = [0.5, 0.7, 0.9];
        }
        push @{ $self->_legends }, {
            type  => 'rect',
            color => $lc,
            label => $opt{label},
        };
    }
    return $self;
}


# ---- qqplot -------------------------------------------------------
# Q-Q 
# $data: 1D PDL 
# dist: 'normal'
sub qqplot {
    my ($self, $data, %opt) = @_;
    $data = pdl($data) unless ref($data) && $data->isa('PDL');

    my $n      = $data->nelem;
    my $sorted = $data->qsort;
    my $dist   = $opt{dist} // 'normal';

    #

    my $probs = (sequence($n) + 0.5) / $n;
    my $theoretical;

    if ($dist eq 'normal') {
        # Beasley-Springer-Moro 
        $theoretical = _qnorm_pdl($probs);
    } else {
        die "qqplot: unsupported dist '$dist' (only 'normal' supported)
";
    }

    my $color = $self->_parse_color($opt{color} // 'steelblue');

    # Q-Q 
    $self->scatter($theoretical, $sorted,
        color  => $color,
        s      => $opt{s} // $opt{size} // 4,
        marker => $opt{marker} // 'o',
        alpha  => $opt{alpha}  // 0.7,
        label  => $opt{label}  // 'data',
    );

    #

    my $qmin = $theoretical->min;
    my $qmax = $theoretical->max;
    my $dmin = $sorted->min;
    my $dmax = $sorted->max;
    # 45: y = mean + std * x
    my $dmean = $sorted->average;
    my $dstd  = $sorted->stdv;
    my $xl = pdl($qmin, $qmax);
    my $yl = $dmean + $dstd * $xl;
    $self->line($xl, $yl,
        color => $self->_parse_color($opt{line_color} // 'red'),
        lw    => $opt{lw} // 1.2,
        ls    => 'dashed',
        label => $opt{line_label} // 'normal',
    );

    #

    $self->xlabel("Theoretical quantiles") unless $self->xlabel ne '';
    $self->ylabel("Sample quantiles")      unless $self->ylabel ne '';

    return $self;
}

# Beasley-Springer-Moro — PDL piddle 
sub _qnorm_pdl {
    my ($p) = @_;
    $p = pdl($p) unless ref($p) && $p->isa('PDL');
    my $p2   = $p->copy;
    my $flip = ($p > 0.5)->double;
    $p2      = $flip * (1 - $p2) + (1 - $flip) * $p2;

    my $t    = sqrt(-2 * log($p2));
    my $a0   = 2.515517; my $a1 = 0.802853; my $a2 = 0.010328;
    my $b1   = 1.432788; my $b2 = 0.189269; my $b3 = 0.001308;
    my $num  = $a0 + $a1*$t + $a2*$t**2;
    my $den  = 1  + $b1*$t + $b2*$t**2 + $b3*$t**3;
    my $z    = $t - $num / $den;
    return (1 - 2*$flip) * $z;
}

# ---- hist_kde -------------------------------------------------------
#  + KDE 
# $data: 1D PDL
sub hist_kde {
    my ($self, $data, %opt) = @_;
    $data = pdl($data) unless ref($data) && $data->isa('PDL');

    my $bins    = $opt{bins}    // 25;
    my $density = $opt{density} // 1;
    my $color   = $self->_parse_color($opt{color} // 'steelblue');
    my $kcolor  = $self->_parse_color($opt{kde_color} // 'red');
    my $label   = $opt{label}   // undef;
    my $klabel  = $opt{kde_label} // 'KDE';

    #

    $self->hist($data,
        bins    => $bins,
        density => $density,
        color   => $color,
        alpha   => $opt{alpha} // 0.65,
        label   => $label,
    );

    # KDE
    my $n    = $data->nelem;
    my $std  = $data->stdv || 1;
    my $h    = 1.06 * $std * ($n ** (-0.2));   # Silverman

    my $dmin = $data->min - $std;
    my $dmax = $data->max + $std;
    my $pts  = $opt{kde_points} // 200;
    my $xs   = $dmin + sequence($pts) * ($dmax - $dmin) / ($pts - 1);

    my $kde  = zeroes($pts);
    my $c    = 1.0 / (sqrt(2*3.14159265358979) * $h * $n);
    for my $j (0..$n-1) {
        my $u = ($xs - $data->at($j)) / $h;
        $kde += $c * exp(-0.5 * $u**2);
    }

    $self->line($xs, $kde,
        color => $kcolor,
        lw    => $opt{kde_lw} // 2.0,
        label => $klabel,
    );

    return $self;
}

#  @PDL 
sub _normalize_groups {
    my ($data) = @_;
    if (ref($data) eq 'ARRAY') {
        return map { ref($_) && $_->isa('PDL') ? $_ : pdl($_) } @$data;
    }
    elsif (ref($data) && $data->isa('PDL') && $data->ndims == 2) {
        return map { $data->slice(":,$_") } 0..$data->dim(1)-1;
    }
    die "data must be arrayref of PDL or 2D PDL (obs x groups)\n";
}

# ---- text --------------------------------------------------------
sub text {
    my ($self, $x, $y, $str, %opt) = @_;
    push @{ $self->_queue }, {
        type   => 'annot',
        x      => $x,  y   => $y,
        str    => $str,
        color  => $self->_parse_color($opt{color} // 'black'),
        size   => $opt{fontsize} // 11,
        align  => $opt{ha}       // 'left',
        valign => $opt{va}       // 'bottom',
        angle  => $opt{rotation} // 0,
    };
    return $self;
}

# ---- hline / vline -----------------------------------------------
sub axhline {
    my ($self, $y, %opt) = @_;
    my $color = $self->_parse_color($opt{color} // 'gray');
    push @{ $self->_queue }, {
        type   => 'hline',
        y      => $y,
        color  => $color,
        lw     => $opt{lw} // $opt{linewidth} // 1.0,
        ls     => $opt{ls} // $opt{linestyle} // 'solid',
    };
    return $self;
}

sub axvline {
    my ($self, $x, %opt) = @_;
    my $color = $self->_parse_color($opt{color} // 'gray');
    push @{ $self->_queue }, {
        type   => 'vline',
        x      => $x,
        color  => $color,
        lw     => $opt{lw} // $opt{linewidth} // 1.0,
        ls     => $opt{ls} // $opt{linestyle} // 'solid',
    };
    return $self;
}

# ==================================================================
#  API — 
# ==================================================================

sub xlim {
    my ($self, $lo, $hi) = @_;
    $self->xmin($lo); $self->xmax($hi);
    return $self;
}


sub ylim {
    my ($self, $lo, $hi) = @_;
    if ($lo > $hi) {
        # negative up: ymin > ymax → Y軸反転
        $self->{_y_reversed} = 1;
        $self->ymin($hi); $self->ymax($lo);
    } else {
        $self->{_y_reversed} = 0;
        $self->ymin($lo); $self->ymax($hi);
    }
    return $self;
}



#sub ylim {
#    my ($self, $lo, $hi) = @_;
#    $self->ymin($lo); $self->ymax($hi);
#    return $self;
#}

sub set_limits {
    my ($self, $xmin, $xmax, $ymin, $ymax) = @_;
    $self->xlim($xmin,$xmax)->ylim($ymin,$ymax);
}

sub xticks {
    my ($self, $ticks, $labels) = @_;
    $self->_xticks($ticks);
    $self->_xticklabels($labels) if defined $labels;
    return $self;
}

sub yticks {
    my ($self, $ticks, $labels) = @_;
    $self->_yticks($ticks);
    $self->_yticklabels($labels) if defined $labels;
    return $self;
}

sub legend {
    my ($self, %opt) = @_;
    $self->{_show_legend} = 1;
    $self->{_legend_loc}  = $opt{loc} // 'upper right';
    return $self;
}

sub set_title  { my ($s,$t,%o) = @_; $s->title($t);  return $s }
sub set_xlabel { my ($s,$t,%o) = @_; $s->xlabel($t); return $s }
sub set_ylabel { my ($s,$t,%o) = @_; $s->ylabel($t); return $s }

sub set_grid {
    my ($self, $on, %opt) = @_;
    $self->grid($on // 1);
    $self->grid_color($self->_parse_color($opt{color})) if exists $opt{color};
    return $self;
}

# ==================================================================
# draw($backend) — Figure::save() 
# ==================================================================
sub draw {
    my ($self, $backend) = @_;

    $self->_finalize_range();

    # twinx  X  Axes 
    if ($self->{_is_twin} && $self->{_twin_of}) {
        my $parent = $self->{_twin_of};
        #  finalize  finalize 
        $parent->_finalize_range() unless defined $parent->xmin;
        # X 
        $self->xmin($parent->xmin);
        $self->xmax($parent->xmax);
        # margin_left/top/bottom 
        $self->margin_left(  $parent->margin_left);
        $self->margin_top(   $parent->margin_top);
        $self->margin_bottom($parent->margin_bottom);
        # margin_right 
        # Y margin_right 
        $self->margin_right($parent->margin_right);
    }

    #
    my $ml = $self->fig_x + $self->margin_left;
    my $mt = $self->fig_y + $self->margin_top;
    my $mr = $self->fig_x + $self->width  - $self->margin_right;
    my $mb = $self->fig_y + $self->height - $self->margin_bottom;

# set_aspect('equal') — データ座標の縦横比を保つ
    if (defined $self->{_aspect} && $self->{_aspect} eq 'equal') {
        my $data_w = $self->xmax - $self->xmin;
        my $data_h = $self->ymax - $self->ymin;
        my $pix_w  = $mr - $ml;
        my $pix_h  = $mb - $mt;
        # データ座標1単位あたりのピクセル数を揃える
        my $scale_x = $pix_w / $data_w;
        my $scale_y = $pix_h / $data_h;
        if ($scale_x > $scale_y) {
            # x方向が広すぎる → 左右マージンを増やして縮める
            my $new_pix_w = $pix_h * $data_w / $data_h;
            my $diff = ($pix_w - $new_pix_w) / 2;
            $ml += $diff;
            $mr -= $diff;
        } else {
            # y方向が広すぎる → 上下マージンを増やして縮める
            my $new_pix_h = $pix_w * $data_h / $data_w;
            my $diff = ($pix_h - $new_pix_h) / 2;
            $mt += $diff;
            $mb -= $diff;
        }
    }

    # xscale/yscale  Transform 
    # _y_reversed PGPLOT  negative up: ymin>ymax
    my ($ymin_tr, $ymax_tr) = ($self->ymin, $self->ymax);
    if ($self->{_y_reversed}) {
        # y : bottom=ymin_tr, top=ymax_tr  swap
        ($ymin_tr, $ymax_tr) = ($ymax_tr, $ymin_tr);
    }
    my $tr;
    if ($self->xscale eq 'log' || $self->yscale eq 'log') {
        $tr = PDL::Graphics::Cairo::Transform::Log->new(
            xmin => $self->xmin, xmax => $self->xmax,
            ymin => $ymin_tr,    ymax => $ymax_tr,
            left => $ml, right => $mr, top => $mt, bottom => $mb,
            xscale => $self->xscale,
            yscale => $self->yscale,
        );
    } else {
        $tr = PDL::Graphics::Cairo::Transform::Linear->new(
            xmin => $self->xmin, xmax => $self->xmax,
            ymin => $ymin_tr,    ymax => $ymax_tr,
            left => $ml, right => $mr, top => $mt, bottom => $mb,
        );
    }

    # ---  ---
#    $self->_draw_grid($backend, $tr, $ml,$mt,$mr,$mb) if $self->grid;  # change 2026/5/25 for Axis(off)
    $self->_draw_grid($backend, $tr, $ml,$mt,$mr,$mb) if $self->grid && !$self->{_axis_off};


    $self->_draw_grid($backend, $tr, $ml,$mt,$mr,$mb) if $self->grid;

    # --- ---
    $backend->save;
    # :  + (14px)
    $backend->clip_rect($ml-1, $mt-15, $mr-$ml+2, $mb-$mt+16);

    # ---  ---
    for my $cmd (@{ $self->_queue }) {
        $self->_render_cmd($backend, $tr, $cmd, $ml,$mt,$mr,$mb);
    }

    $backend->restore;

    # ---  ---
    if ($self->{_is_twin}) {
        # twinx: Y
        $self->_draw_twin_yaxis($backend, $tr, $ml,$mt,$mr,$mb);

    } else {


        my $has_plot = grep {
            $_->{type} =~ /^(line|scatter|bar|barh|hist|errorbar|
                              fill_between|step|stem|imshow|contourf|
                              pie|hline|vline|vspan|hspan|quiver|
                              boxplot_item|box_fliers|violin_item|
                              eventplot|annotate)$/x
        } @{ $self->_queue };
        my $has_content = $has_plot || $self->{_pgbox};

#        my $has_content = @{ $self->_queue } || $self->{_pgbox};
#        my $has_content = @{ $self->_queue } || $self->{_pgenv_called};
#        my $has_content = @{ $self->_queue } || $self->{_pgenv_called} || $self->{_pgbox};

        $self->_draw_frame($backend, $tr, $ml,$mt,$mr,$mb)
            unless $self->{_axis_off} || !$has_content;
        $self->_draw_labels($backend, $ml,$mt,$mr,$mb)
            unless $self->{_axis_off} || !$has_content;
    }


#    } else {
#        # pgenv  pgline 
#        $self->_draw_frame($backend, $tr, $ml,$mt,$mr,$mb); ## modified for Axis(off) 2026/5/25
#        $self->_draw_frame($backend, $tr, $ml,$mt,$mr,$mb) unless $self->{_axis_off};
#    }

    # ---  ---
#    $self->_draw_labels($backend, $ml,$mt,$mr,$mb); ## modified for Axis(off) 2026/5/25
     $self->_draw_labels($backend, $ml,$mt,$mr,$mb) unless $self->{_axis_off};

    # ---  ---
    $self->_draw_legend($backend, $ml,$mt,$mr,$mb)
        if $self->{_show_legend} && @{ $self->_legends } && !$self->{_axis_off};

    # ---  ---
    $self->_draw_colorbar($backend, $ml,$mr,$mt,$mb)
        if $self->_colorbar && !$self->{_axis_off};
}

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
sub _render_cmd {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $type = $cmd->{type};

    if ($type eq 'line') {
        my $xd = $tr->x($cmd->{x});
        my $yd = $tr->y($cmd->{y});
        $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
        $b->set_linewidth($cmd->{lw});
        $b->set_linestyle($cmd->{linestyle}, $cmd->{lw});
        $b->polyline($xd, $yd);
        $b->set_linestyle('solid');
    }

    elsif ($type eq 'scatter') {
        my $cmap  = defined($cmd->{cdata})
            ? PDL::Graphics::Cairo::ColorMap->new($cmd->{cmap}) : undef;
        my ($cdmin,$cdmax);
        if ($cmap) {
            ($cdmin,$cdmax) = $cmd->{cdata}->minmax;
        }
        for my $i (0 .. $cmd->{x}->nelem - 1) {
            my $xp = $tr->x(pdl($cmd->{x}->at($i)))->at(0);
            my $yp = $tr->y(pdl($cmd->{y}->at($i)))->at(0);
            my @c;
            if ($cmap) {
                @c = $cmap->rgb_norm($cmd->{cdata}->at($i), $cdmin, $cdmax);
            } else {
                @c = @{$cmd->{color}};
            }
            $b->set_color(@c, $cmd->{alpha});
            $b->set_linewidth(0.5);
            $b->marker($xp, $yp, $cmd->{size}, $cmd->{marker}, 1);
        }
    }

    elsif ($type eq 'bar') {
        my $n = $cmd->{x}->nelem;
        for my $i (0 .. $n-1) {
            my $xc = $cmd->{x}->at($i);
            my $h  = $cmd->{height}->at($i);
            my $w  = ref($cmd->{width}) ? $cmd->{width}->at($i) : $cmd->{width};
            my $bo = ref($cmd->{bottom})? $cmd->{bottom}->at($i): $cmd->{bottom};

            my $xp = $tr->x(pdl($xc - $w/2))->at(0);
            my $yp = $tr->y(pdl($bo + $h))->at(0);
            my $wp = $tr->x(pdl($xc + $w/2))->at(0) - $xp;
            my $hp = $tr->y(pdl($bo))->at(0)         - $yp;

            $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
            $b->rect_fill($xp, $yp, $wp, $hp);
            $b->set_color(@{$cmd->{edge}});
            $b->set_linewidth(0.5);
            $b->rect_stroke($xp, $yp, $wp, $hp);
        }
    }

    elsif ($type eq 'barh') {
        my $n = $cmd->{y}->nelem;
        for my $i (0 .. $n-1) {
            my $yc = $cmd->{y}->at($i);
            my $wv = $cmd->{width}->at($i);
            my $hv = ref($cmd->{height})? $cmd->{height}->at($i): $cmd->{height};
            my $lo = ref($cmd->{left})  ? $cmd->{left}->at($i)  : $cmd->{left};

            my $xp = $tr->x(pdl($lo))->at(0);
            my $yp = $tr->y(pdl($yc + $hv/2))->at(0);
            my $wp = $tr->x(pdl($lo + $wv))->at(0) - $xp;
            my $hp = $tr->y(pdl($yc - $hv/2))->at(0) - $yp;

            $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
            $b->rect_fill($xp, $yp, $wp, $hp);
            $b->set_color(@{$cmd->{edge}});
            $b->set_linewidth(0.5);
            $b->rect_stroke($xp, $yp, $wp, $hp);
        }
    }

    elsif ($type eq 'hist') {
        my $n = $cmd->{edges}->nelem - 1;
        for my $i (0 .. $n-1) {
            my $x0 = $tr->x(pdl($cmd->{edges}->at($i)))->at(0);
            my $x1 = $tr->x(pdl($cmd->{edges}->at($i+1)))->at(0);
            my $y0 = $tr->y(pdl(0))->at(0);
            my $y1 = $tr->y(pdl($cmd->{counts}->at($i)))->at(0);
            $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
            $b->rect_fill($x0, $y1, $x1-$x0, $y0-$y1);
            $b->set_color(0,0,0);
            $b->set_linewidth(0.5);
            $b->rect_stroke($x0, $y1, $x1-$x0, $y0-$y1);
        }
    }

    elsif ($type eq 'errorbar') {
        #

        my $xd = $tr->x($cmd->{x});
        my $yd = $tr->y($cmd->{y});
        $b->set_color(@{$cmd->{color}});
        $b->set_linewidth($cmd->{lw});
        $b->polyline($xd, $yd);
        #

        for my $i (0 .. $cmd->{x}->nelem - 1) {
            $b->marker($xd->at($i), $yd->at($i), $cmd->{ms}, $cmd->{marker}, 1);
        }
        #

        if (defined $cmd->{yerr}) {
            $b->set_linewidth(1.0);
            for my $i (0 .. $cmd->{x}->nelem - 1) {
                my $xe = $xd->at($i);
                my $ye = $yd->at($i);
                my $yn = $cmd->{x}->nelem;
                my $en = $cmd->{yerr}->nelem;
                # (nelem==1)broadcast2*nlo/hi
                my $elo = $en == 1          ? $cmd->{yerr}->at(0)
                        : $en == 2 * $yn    ? $cmd->{yerr}->at($i)
                        :                     $cmd->{yerr}->at($i);
                my $ehi = $en == 1          ? $cmd->{yerr}->at(0)
                        : $en == 2 * $yn    ? $cmd->{yerr}->at($yn + $i)
                        :                     $cmd->{yerr}->at($i);
                my $y_lo = $tr->y(pdl($cmd->{y}->at($i) + $ehi))->at(0);
                my $y_hi = $tr->y(pdl($cmd->{y}->at($i) - $elo))->at(0);
                $b->errorbar_y($xe, $ye,
                    $ye - $y_lo,   # lo in screen
                    $y_hi - $ye,   # hi in screen
                    $cmd->{capsize});
            }
        }
    }

    elsif ($type eq 'fill_between') {
        #  →  → polygon
        my $n  = $cmd->{x}->nelem;
        my $xf = $cmd->{x}->append($cmd->{x}->slice("-1:0:-1"));
        my $yf = $cmd->{y1}->append($cmd->{y2}->slice("-1:0:-1"));
        my $xd = $tr->x($xf);
        my $yd = $tr->y($yf);
        $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
        $b->filled_polygon($xd, $yd);
    }


    elsif ($type eq 'imshow') {
        my $data = $cmd->{data};
        my @dims = $data->dims;
        my $ndims = scalar @dims;
        my $pw = ($mr - $ml) / $dims[1];
        my $ph = ($mb - $mt) / $dims[0];
        my $upper  = ($cmd->{origin} // 'upper') eq 'upper';
        my $rows   = $dims[0];
        my $cols   = $dims[1];

        if ($ndims == 3 && $dims[2] == 3) {
            # RGB画像 [H, W, 3]
            for my $r (0 .. $rows-1) {
                my $rd = $upper ? $r : $rows-1-$r;
                for my $c (0 .. $cols-1) {
                    my $rv = $data->at($rd,$c,0);
                    my $gv = $data->at($rd,$c,1);
                    my $bv = $data->at($rd,$c,2);
                    $b->colored_rect(
                        $ml + $c*$pw, $mt + $r*$ph, $pw+0.5, $ph+0.5,
                        $rv, $gv, $bv, $cmd->{alpha}
                    );
                }
            }

        } else {
            # グレースケール [H, W]
            for my $r (0 .. $rows-1) {
                my $rd = $upper ? $r : $rows-1-$r;
                for my $c (0 .. $cols-1) {
                    my $v = $data->at($rd,$c);
                    my ($rv,$gv,$bv) = $cmd->{cmap}->rgb_norm($v, $cmd->{vmin}, $cmd->{vmax});
                    $b->colored_rect(
                        $ml + $c*$pw, $mt + $r*$ph, $pw+0.5, $ph+0.5,
                        $rv,$gv,$bv, $cmd->{alpha}
                    );
                }
            }
        }
    }

    elsif ($type eq 'step') {
        #

        my @xs = list($cmd->{x});
        my @ys = list($cmd->{y});
        my (@sx, @sy);
        if ($cmd->{where} eq 'pre') {
            for my $i (0 .. $#xs) {
                if ($i > 0) { push @sx, $xs[$i]; push @sy, $ys[$i-1]; }
                push @sx, $xs[$i]; push @sy, $ys[$i];
            }
        } else {  # post
            for my $i (0 .. $#xs) {
                push @sx, $xs[$i]; push @sy, $ys[$i];
                if ($i < $#xs) { push @sx, $xs[$i+1]; push @sy, $ys[$i]; }
            }
        }
        my $xd = $tr->x(pdl(@sx));
        my $yd = $tr->y(pdl(@sy));
        $b->set_color(@{$cmd->{color}}, 1.0);
        $b->set_linewidth($cmd->{lw});
        $b->set_linestyle($cmd->{linestyle}, $cmd->{lw});
        $b->polyline($xd, $yd);
        $b->set_linestyle('solid');
    }

    elsif ($type eq 'stem') {
        my $baseline_y = $tr->y(pdl(0))->at(0);
        $b->set_color(@{$cmd->{color}});
        $b->set_linewidth($cmd->{lw});
        for my $i (0 .. $cmd->{x}->nelem-1) {
            my $xp = $tr->x(pdl($cmd->{x}->at($i)))->at(0);
            my $yp = $tr->y(pdl($cmd->{y}->at($i)))->at(0);
            $b->line_seg($xp, $baseline_y, $xp, $yp);
            $b->marker($xp, $yp, $cmd->{ms}, 'o', 1);
        }
        #

        $b->set_linewidth(1.5);
        $b->line_seg($ml, $baseline_y, $mr, $baseline_y);
    }

    elsif ($type eq 'annot') {
        $b->set_color(@{$cmd->{color}});
        $b->set_font(size => $cmd->{size});
        my $xd = $tr->x(pdl($cmd->{x}))->at(0);
        my $yd = $tr->y(pdl($cmd->{y}))->at(0);
        $b->text($xd, $yd, $cmd->{str},
            align  => $cmd->{align},
            valign => $cmd->{valign},
            angle  => $cmd->{angle});
    }

    elsif ($type eq 'hline') {
        my $yp = $tr->y(pdl($cmd->{y}))->at(0);
        $b->set_color(@{$cmd->{color}});
        $b->set_linewidth($cmd->{lw});
        $b->set_linestyle($cmd->{ls}, $cmd->{lw});
        $b->line_seg($ml, $yp, $mr, $yp);
        $b->set_linestyle('solid');
    }

    elsif ($type eq 'vline') {
        my $xp = $tr->x(pdl($cmd->{x}))->at(0);
        $b->set_color(@{$cmd->{color}});
        $b->set_linewidth($cmd->{lw});
        $b->set_linestyle($cmd->{ls}, $cmd->{lw});
        $b->line_seg($xp, $mt, $xp, $mb);
        $b->set_linestyle('solid');
    }

    elsif ($type eq 'boxplot_item') {
        my $xc  = $cmd->{xc};
        my $hw  = $cmd->{hw};
        my $xl  = $tr->x(pdl($xc - $hw))->at(0);
        my $xr  = $tr->x(pdl($xc + $hw))->at(0);
        my $xcp = $tr->x(pdl($xc))->at(0);
        my $yq1 = $tr->y(pdl($cmd->{q1}))->at(0);
        my $yq3 = $tr->y(pdl($cmd->{q3}))->at(0);
        my $yme = $tr->y(pdl($cmd->{med}))->at(0);
        my $ymn = $tr->y(pdl($cmd->{mean}))->at(0);
        my $ylo = $tr->y(pdl($cmd->{wlo}))->at(0);
        my $yhi = $tr->y(pdl($cmd->{whi}))->at(0);

        #

        $b->set_color(@{$cmd->{facecolor}}, 0.8);
        $b->rect_fill($xl, $yq3, $xr - $xl, $yq1 - $yq3);

        #

        $b->set_color(@{$cmd->{edgecolor}});
        $b->set_linewidth(1.2);
        $b->line_seg($xcp, $yq3, $xcp, $yhi);
        #

        $b->line_seg($xcp, $yq1, $xcp, $ylo);

        #

        if ($cmd->{showcaps}) {
            my $cw = ($xr - $xl) * 0.4;
            $b->line_seg($xcp - $cw, $yhi, $xcp + $cw, $yhi);
            $b->line_seg($xcp - $cw, $ylo, $xcp + $cw, $ylo);
        }

        #

        $b->rect_stroke($xl, $yq3, $xr - $xl, $yq1 - $yq3);

        #

        $b->set_linewidth(2.0);
        $b->line_seg($xl, $yme, $xr, $yme);

        #

        if ($cmd->{showmean}) {
            $b->set_color(1, 0, 0);
            $b->marker($xcp, $ymn, 4, 'd', 1);
        }
    }

    elsif ($type eq 'box_fliers') {
        my $xcp = $tr->x(pdl($cmd->{xc}))->at(0);
        $b->set_color(@{$cmd->{color}});
        $b->set_linewidth(1.5);
        for my $j (0..$cmd->{data}->nelem-1) {
            my $yp = $tr->y(pdl($cmd->{data}->at($j)))->at(0);
            $b->marker($xcp, $yp, 3, 'o', 0);
        }
    }

    elsif ($type eq 'violin_item') {
        my $xc   = $cmd->{xc};
        my $ys   = $cmd->{ys};
        my $kde  = $cmd->{kde};
        my $n    = $ys->nelem;

        #  x,y
        my @rx = map { $tr->x(pdl($xc + $kde->at($_)))->at(0) } 0..$n-1;
        my @ry = map { $tr->y(pdl($ys->at($_)))->at(0)        } 0..$n-1;
        #

        my @lx = map { $tr->x(pdl($xc - $kde->at($_)))->at(0) } reverse 0..$n-1;
        my @ly = map { $tr->y(pdl($ys->at($_)))->at(0)        } reverse 0..$n-1;

        my $poly_x = pdl(@rx, @lx);
        my $poly_y = pdl(@ry, @ly);

        #

        $b->set_color(@{$cmd->{color}}, 0.5);
        $b->filled_polygon($poly_x, $poly_y);
        #

        $b->set_color(@{$cmd->{color}}, 0.9);
        $b->set_linewidth(1.2);
        $b->polyline(pdl(@rx, $lx[0]), pdl(@ry, $ly[0]));
        $b->polyline(pdl(@lx, $rx[0]), pdl(@ly, $ry[0]));

        # IQR 
        if ($cmd->{showbox}) {
            my $xl  = $tr->x(pdl($xc - $kde->max * 0.15))->at(0);
            my $xr  = $tr->x(pdl($xc + $kde->max * 0.15))->at(0);
            my $yq1 = $tr->y(pdl($cmd->{q1}))->at(0);
            my $yq3 = $tr->y(pdl($cmd->{q3}))->at(0);
            $b->set_color(0.3, 0.3, 0.3, 0.9);
            $b->set_linewidth(2.5);
            $b->line_seg($tr->x(pdl($xc))->at(0), $yq1,
                         $tr->x(pdl($xc))->at(0), $yq3);
        }

        #

        if ($cmd->{showmed}) {
            my $ymed = $tr->y(pdl($cmd->{median}))->at(0);
            my $xcp  = $tr->x(pdl($xc))->at(0);
            $b->set_color(1, 1, 1);
            $b->marker($xcp, $ymed, 4, 'o', 1);
            $b->set_color(0.2, 0.2, 0.2);
            $b->marker($xcp, $ymed, 4, 'o', 0);
        }

        #

        if ($cmd->{showmean}) {
            my $ymn = $tr->y(pdl($cmd->{mean}))->at(0);
            my $xcp = $tr->x(pdl($xc))->at(0);
            $b->set_color(1, 0.2, 0.2);
            $b->marker($xcp, $ymn, 4, 'd', 1);
        }
    }

    elsif ($type eq 'pie') {
        # pie  tr 
        my $cx = ($ml + $mr) / 2;
        my $cy = ($mt + $mb) / 2;
        my $r  = (PDL::Graphics::Cairo::Axes::_min($mr-$ml, $mb-$mt) / 2) * 0.85;

        my @colors = (
            [0.122,0.467,0.706],[1.000,0.498,0.055],[0.173,0.627,0.173],
            [0.839,0.153,0.157],[0.580,0.404,0.741],[0.549,0.337,0.294],
            [0.890,0.467,0.761],[0.498,0.498,0.498],[0.737,0.741,0.133],
            [0.090,0.745,0.812],
        );

        my $pi    = 3.14159265358979;
        my $angle = $cmd->{startangle} * $pi / 180;
        my $total = $cmd->{total};

        for my $i (0 .. $#{ $cmd->{sizes} }) {
            my $frac  = $cmd->{sizes}[$i] / $total;
            my $sweep = $frac * 2 * $pi;
            my $exp   = $cmd->{explode}[$i] // 0;
            my $mid   = $angle + $sweep / 2;
            my $ecx   = $cx + $exp * $r * cos($mid);
            my $ecy   = $cy - $exp * $r * sin($mid);

            my @c = @{ $colors[$i % scalar @colors] };
            $b->set_color(@c, 0.85);

            #

            my $n_seg = int($sweep / (2*$pi) * 60) + 3;
            $n_seg = 3 if $n_seg < 3;
            my @px = ($ecx);
            my @py = ($ecy);
            for my $k (0 .. $n_seg) {
                my $a = $angle + $k * $sweep / $n_seg;
                push @px, $ecx + $r * cos($a);
                push @py, $ecy - $r * sin($a);
            }
            push @px, $ecx; push @py, $ecy;
            $b->filled_polygon(pdl(@px), pdl(@py));

            #

            $b->set_color(1,1,1);
            $b->set_linewidth(1.5);
            my @bx = ($ecx);
            my @by = ($ecy);
            for my $k (0 .. $n_seg) {
                my $a = $angle + $k * $sweep / $n_seg;
                push @bx, $ecx + $r * cos($a);
                push @by, $ecy - $r * sin($a);
            }
            push @bx, $ecx; push @by, $ecy;
            $b->polyline(pdl(@bx), pdl(@by));

            #

            if ($cmd->{labels}[$i] ne '') {
                my $la = $angle + $sweep/2;
                my $lx = $ecx + ($r * 1.12) * cos($la);
                my $ly = $ecy - ($r * 1.12) * sin($la);
                my $ha = cos($la) > 0 ? 'left' : 'right';
                $b->set_color(0,0,0);
                $b->set_font(size => 10);
                $b->text($lx, $ly, $cmd->{labels}[$i],
                    align => $ha, valign => 'middle');
            }

            # autopct
            if ($cmd->{autopct} ne '') {
                my $pct_str = sprintf($cmd->{autopct}, $frac * 100);
                my $la  = $angle + $sweep/2;
                my $plx = $ecx + $r * 0.6 * cos($la);
                my $ply = $ecy - $r * 0.6 * sin($la);
                $b->set_color(1,1,1);
                $b->set_font(size => 9, weight => 'bold');
                $b->text($plx, $ply, $pct_str, align=>'center', valign=>'middle');
            }

            $angle += $sweep;
        }
    }

    elsif ($type eq 'vspan') {
        my $x1p = $tr->x(pdl($cmd->{x1}))->at(0);
        my $x2p = $tr->x(pdl($cmd->{x2}))->at(0);
        $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
        $b->rect_fill($x1p, $mt, $x2p - $x1p, $mb - $mt);
    }

    elsif ($type eq 'hspan') {
        my $y1p = $tr->y(pdl($cmd->{y2}))->at(0);
        my $y2p = $tr->y(pdl($cmd->{y1}))->at(0);
        $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
        $b->rect_fill($ml, $y1p, $mr - $ml, $y2p - $y1p);
    }

    elsif ($type eq 'pgmtxt') {
        # PGPLOT pgmtxt :
        # side: T=, B=, L=, R=
        # disp: =, =
        # coord:  0()1()
        # fjust:  0= coord , 0.5=, 1.0= coord 
        my $side  = $cmd->{side};
        my $coord = $cmd->{coord} // 0.5;
        my $fjust = $cmd->{fjust} // 0.5;
        my $disp  = $cmd->{disp} // 0;
        my $ch    = $cmd->{ch}   // 1.0;
        #

        # pgsch(1)=, pgsch(2)=, pgsch(4)=
        # 6x6 160px: ch=1→8px, ch=2→9px, ch=4→11px 
        my $pw_px = $mr - $ml;
        my $ph_px = $mb - $mt;
        my $panel_min = $pw_px < $ph_px ? $pw_px : $ph_px;
        # pgsch(ch) → 
        # ch=1: 8px, ch=2: 9px, ch=4: 11px 
        # (6x6)
        my $panel_scale = $panel_min > 150 ? 1.0 : $panel_min / 150.0;
        my $fs_base = 8;
        my $fs = int($fs_base + ($ch - 1) * $panel_scale * 1.0);
        $fs = 7  if $fs < 7;
        $fs = 10 if $fs > 10;

        # fjust → Cairo  align
        # fjust: 0=, 0.5=, 1=  coord 
        # → Cairo  align 
        my $align = $fjust < 0.25 ? 'left' : $fjust > 0.75 ? 'right' : 'center';

        my ($xp, $yp, $valign);
        my $pw = $mr - $ml;
        my $ph = $mb - $mt;

        if ($side eq 'T') {
            # PGPLOT: side=T 2:
            # 1) : pgmtxt("TR", -1, 0.1, 1.0, $ch)
            #    → coord=0.1(), fjust=1.0()
            # 2) : pgmtxt("T", -1/-2/-3/-4, 0, 0.0, text)
            #    → coord=0, fjust=0()
            #    → disp=-N  N
            # : fs + 3px
            my $line_h = $fs + 3;
            if ($fjust < 0.1 && $coord < 0.05) {
                # : disp 
                # disp=-1 → 1(), disp=-2 → 2...
                my $row = abs($disp) - 1;
                $xp     = $ml + 2;
                $align  = 'left';
                #  ()
                $yp     = $mt + $row * $line_h + 2;
                $valign = 'top';
            } else {
                # : 
                $xp     = $ml + 2;
                $align  = 'left';
                $yp     = $mt - 1;
                $valign = 'bottom';
            }
        } elsif ($side eq 'B') {
            $xp = $ml + $pw * $coord;
            $align  = $fjust < 0.25 ? 'left' : $fjust > 0.75 ? 'right' : 'center';
            $yp = $mb - abs($disp) * ($fs + 1);
            $valign = 'bottom';
        } elsif ($side eq 'L') {
            $yp = $mb - $ph * $coord;
            $xp = $ml + abs($disp) * ($fs + 1);
            $align  = $fjust < 0.25 ? 'left' : $fjust > 0.75 ? 'right' : 'center';
            $valign = 'middle';
        } elsif ($side eq 'R') {
            $yp = $mb - $ph * $coord;
            $xp = $mr - abs($disp) * ($fs + 1);
            $align  = $fjust < 0.25 ? 'right' : $fjust > 0.75 ? 'left' : 'center';
            $valign = 'middle';
        } else {
            $xp = ($ml+$mr)/2; $yp = ($mt+$mb)/2;
            $align = 'center'; $valign = 'middle';
        }
        $b->set_color(@{$cmd->{color}});
        $b->set_font(size => $fs);
        $b->text($xp, $yp, $cmd->{text},
            align  => $align,
            valign => $valign,
        );
    }
    elsif ($type eq 'annotate') {
        my $axp = $tr->x(pdl($cmd->{ax}))->at(0);
        my $ayp = $tr->y(pdl($cmd->{ay}))->at(0);
        my $txp = $tr->x(pdl($cmd->{tx}))->at(0);
        my $typ = $tr->y(pdl($cmd->{ty}))->at(0);

        #

        if ($cmd->{arrow}) {
            $b->set_color(@{$cmd->{color}});
            $b->set_linewidth(1.0);
            $b->line_seg($txp, $typ, $axp, $ayp);
            #

            my $pi  = 3.14159265358979;
            my $ang = atan2($ayp - $typ, $axp - $txp);
            my $hs  = 8;
            my $ha  = 0.4;
            my @hx  = ($axp,
                        $axp - $hs*cos($ang-$ha),
                        $axp - $hs*cos($ang+$ha));
            my @hy  = ($ayp,
                        $ayp - $hs*sin($ang-$ha),
                        $ayp - $hs*sin($ang+$ha));
            $b->set_color(@{$cmd->{color}});
            $b->filled_polygon(pdl(@hx), pdl(@hy));
        }

        #

        $b->set_color(@{$cmd->{color}});
        $b->set_font(size => $cmd->{size});
        $b->text($txp, $typ, $cmd->{text}, align=>'left', valign=>'bottom');
    }

    elsif ($type eq 'contourf') {
        # bilinear
        my @xs  = list($cmd->{x});
        my @ys  = list($cmd->{y});
        my $z   = $cmd->{z};
        my $nr  = scalar @ys;
        my $nc  = scalar @xs;
        my $vmin = $cmd->{vmin};
        my $vmax = $cmd->{vmax};

        for my $r (0 .. $nr - 2) {
            for my $c (0 .. $nc - 2) {
                my $v  = ($z->at($r,$c) + $z->at($r,$c+1)
                        + $z->at($r+1,$c) + $z->at($r+1,$c+1)) / 4;
                my ($rv,$gv,$bv) = $cmd->{cmap}->rgb_norm($v, $vmin, $vmax);
                my $x1p = $tr->x(pdl($xs[$c]))->at(0);
                my $x2p = $tr->x(pdl($xs[$c+1]))->at(0);
                my $y1p = $tr->y(pdl($ys[$r+1]))->at(0);
                my $y2p = $tr->y(pdl($ys[$r]))->at(0);
                $b->colored_rect($x1p, $y1p, $x2p-$x1p+0.5, $y2p-$y1p+0.5,
                    $rv, $gv, $bv, $cmd->{alpha});
            }
        }
    }

}

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
sub _draw_grid {
    my ($self, $b, $tr, $ml,$mt,$mr,$mb) = @_;
    my @xtks = $self->_xticks
        ? @{ $self->_xticks }
        : nice_ticks($self->xmin, $self->xmax, 6);
    my @ytks = $self->_yticks
        ? @{ $self->_yticks }
        : nice_ticks($self->ymin, $self->ymax, 6);

    for my $v (@xtks) {
        my $xp = $tr->x(pdl($v))->at(0);
        $b->grid_line_v($xp, $mt, $mb, $self->grid_color);
    }
    for my $v (@ytks) {
        my $yp = $tr->y(pdl($v))->at(0);
        $b->grid_line_h($ml, $mr, $yp, $self->grid_color);
    }
}


# ------------------------------------------------------------------
# _draw_twin_yaxis — twinx Y
# ------------------------------------------------------------------
sub _draw_twin_yaxis {
    my ($self, $b, $tr, $ml,$mt,$mr,$mb) = @_;

    $b->set_color(0,0,0);
    $b->set_linewidth(1.0);
    $b->set_linestyle('solid');

    #

    $b->line_seg($mr, $mt, $mr, $mb);

    # Y 
    my @ytks;
    if ($self->_yticks) {
        @ytks = @{ $self->_yticks };
    } elsif ($self->yscale eq 'log') {
        my $sc = PDL::Graphics::Cairo::Scale::Log->new;
        @ytks = $sc->nice_ticks($self->ymin, $self->ymax);
    } else {
        @ytks = nice_ticks($self->ymin, $self->ymax, 6);
    }
    my @ylbs = $self->_yticklabels ? @{ $self->_yticklabels }
        : ($self->yscale eq 'log')
            ? do { my $sc = PDL::Graphics::Cairo::Scale::Log->new;
                   map { $sc->fmt_tick($_) } @ytks }
            : map { _fmt_tick($_) } @ytks;

    $b->set_font(size => 10);
    for my $i (0 .. $#ytks) {
        my $v  = $ytks[$i];
        next if $v < $self->ymin * 0.9999 || $v > $self->ymax * 1.0001;
        my $yp = $tr->y(pdl($v))->at(0);
        next if $yp < $mt - 1 || $yp > $mb + 1;
        # (mb)x
        next if $yp > $mb - 2;
        #

        $b->line_seg($mr, $yp, $mr+4, $yp);
        $b->set_color(_fg());
        $b->text($mr+6, $yp, $ylbs[$i], align=>'left', valign=>'middle');
    }

    # Y
    if ($self->ylabel ne '') {
        $b->set_font(size => 11);
        $b->text($mr + 42, ($mt+$mb)/2, $self->ylabel,
            align=>'center', valign=>'bottom', angle=>-90);
    }
    if (exists $self->{_right_ylabel} && $self->{_right_ylabel} ne '') {
        $b->set_font(size => 11);
        $b->text($mr + 20, ($mt+$mb)/2, $self->{_right_ylabel},
            align=>'center', valign=>'bottom', angle=>-90);
    }
}

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
sub _draw_frame {
    my ($self, $b, $tr, $ml,$mt,$mr,$mb) = @_;

    # pgbox 
    my $pb   = $self->{_pgbox};
    my $xopt = $pb ? uc($pb->{xopt}) : 'BCNST';
    my $yopt = $pb ? uc($pb->{yopt}) : 'BCNST';
    my @fc   = ($pb && $pb->{color}) ? @{$pb->{color}} : (_fg());

    $b->set_linewidth(1.5);
    $b->set_linestyle('solid');

    # ============================================================
    # A: y=0 x=0 
    # ============================================================
    my ($x0p, $y0p);

    if ($xopt =~ /A/ && $self->ymin <= 0 && $self->ymax >= 0) {
        $y0p = $tr->y(pdl(0))->at(0);
        if ($y0p >= $mt - 1 && $y0p <= $mb + 1) {
            $b->set_color(@fc);
            $b->line_seg($ml, $y0p, $mr, $y0p);
        }
    }
    $y0p //= $mb;

    if ($yopt =~ /A/ && $self->xmin <= 0 && $self->xmax >= 0) {
        $x0p = $tr->x(pdl(0))->at(0);
        if ($x0p >= $ml - 1 && $x0p <= $mr + 1) {
            $b->set_color(@fc);
            # X(mb+2) mb-1 
            $b->line_seg($x0p, $mt, $x0p, $mb);
        }
    }
    $x0p //= $ml;

    # B/C: 
    if (!$pb || $xopt =~ /[BC]/ || $yopt =~ /[BC]/) {
        $b->set_color(@fc);
        $b->rect_stroke($ml, $mt, $mr-$ml, $mb-$mt);
    }

    # ============================================================
    # X 
    # ============================================================
    my @xtks;
    if ($self->_xticks) {
        @xtks = @{ $self->_xticks };
    } elsif ($self->xscale eq 'log') {
        my $sc = PDL::Graphics::Cairo::Scale::Log->new;
        @xtks = $sc->nice_ticks($self->xmin, $self->xmax);
    } else {
        @xtks = nice_ticks($self->xmin, $self->xmax, 6);
    }
    my @xlbs = $self->_xticklabels ? @{ $self->_xticklabels }
        : ($self->xscale eq 'log')
            ? do { my $sc = PDL::Graphics::Cairo::Scale::Log->new;
                   map { $sc->fmt_tick($_) } @xtks }
            : map { _fmt_tick($_) } @xtks;

    $b->set_font(size => 8);
    my $prev_xp = -9999;
    my $min_gap = 24;
    for my $i (0 .. $#xtks) {
        my $v    = $xtks[$i];
        my $xeps = ($self->xmax - $self->xmin) * 0.001 + 0.001;
        next if $v < $self->xmin - $xeps || $v > $self->xmax + $xeps;
        my $xp = $tr->x(pdl($v))->at(0);
        next if $xp < $ml - 1 || $xp > $mr + 1;

        # T/S: ticks  y=0 3px
        if ($xopt =~ /[TS]/) {
            $b->set_color(@fc);
            my $tl = ($xopt =~ /T/) ? 3 : 2;
            my $ya = ($y0p >= $mt && $y0p <= $mb) ? $y0p : $mb;
            $b->line_seg($xp, $ya - $tl, $xp, $ya + $tl);
        }

        # N: (mb)
        next if $xp - $prev_xp < $min_gap;
        if ($xopt =~ /N/) {
            $b->set_color(@fc);
            my $rot   = $self->{_xtick_rot} // 0;
            # X(mb)xp 
            # X(mb)
            # 8px + 2px = 10px → mb+10
            # $b->text($xp, $mb + 14, $xlbs[$i],
            $b->text($xp, $mb + 16, $xlbs[$i],
                align=>'center', valign=>'top', angle=>$rot);
        }
        $prev_xp = $xp;
    }

    # ============================================================
    # Y 
    # ============================================================
    my @ytks;
    if ($self->_yticks) {
        @ytks = @{ $self->_yticks };
    } elsif ($self->yscale eq 'log') {
        my $sc = PDL::Graphics::Cairo::Scale::Log->new;
        @ytks = $sc->nice_ticks($self->ymin, $self->ymax);
    } else {
        @ytks = nice_ticks($self->ymin, $self->ymax, 6);
    }
    my @ylbs = $self->_yticklabels ? @{ $self->_yticklabels }
        : ($self->yscale eq 'log')
            ? do { my $sc = PDL::Graphics::Cairo::Scale::Log->new;
                   map { $sc->fmt_tick($_) } @ytks }
            : map { _fmt_tick($_) } @ytks;

    my $min_ygap = 14;
    my ($ylo, $yhi) = ($self->ymin, $self->ymax);
    my $prev_yp = $self->{_y_reversed} ? -9999 : 9999;
    for my $i (0 .. $#ytks) {
        my $v   = $ytks[$i];
        my $eps = ($yhi - $ylo) * 0.001 + 0.001;
        next if $v < $ylo - $eps || $v > $yhi + $eps;
        my $yp = $tr->y(pdl($v))->at(0);
        next if $yp < $mt - 1 || $yp > $mb + 1;

        # T/S: ticks  x=0 3px
        if ($yopt =~ /[TS]/) {
            $b->set_color(@fc);
            my $tl  = ($yopt =~ /T/) ? 3 : 2;
            my $xa  = ($x0p >= $ml && $x0p <= $mr) ? $x0p : $ml;
            $b->line_seg($xa - $tl, $yp, $xa + $tl, $yp);
        }

        # N: (ml)
        my $gap = $self->{_y_reversed} ? $yp - $prev_yp : $prev_yp - $yp;
        next if $gap < $min_ygap;
        if ($yopt =~ /N/) {
            $b->set_color(@fc);
            # y=0 (y0p) x
            my $ya = ($x0p >= $ml && $x0p <= $mr) ? $x0p : $ml;
            my $txt_y = $yp;
            # y=0 : 
            if (abs($v) < ($yhi - $ylo) * 0.001 + 0.001) {
#                $txt_y = $yp - 2;
            }
            $b->text($ml - 2, $txt_y, $ylbs[$i],
                align=>'right', valign=>'middle');
        }
        $prev_yp = $yp;
    }
}

#

sub _fmt_tick {
    my ($v) = @_;
    return "0" if $v == 0;
    my $abs = abs($v);
    if ($abs >= 1e4 || ($abs > 0 && $abs < 1e-3)) {
        return sprintf("%.2e", $v);
    }
    #

    #

    my $rounded = $v >= 0 ? int($v + 0.5) : int($v - 0.5);
    if (abs($v - $rounded) < 0.001) {
        return sprintf("%d", $rounded);
    }
    # 1
    elsif ($abs >= 1) { return sprintf("%.1f", $v) }
    else              { return sprintf("%.2g", $v) }
}

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
sub _draw_labels {
    my ($self, $b, $ml,$mt,$mr,$mb) = @_;

    $b->set_color(0,0,0);

    #

    if ($self->title ne '') {
        $b->set_font(size => 13, weight => 'bold');
        $b->text(($ml+$mr)/2, $mt - 14, $self->title,
            align=>'center', valign=>'bottom');
    }

    # X 
    if ($self->xlabel ne '') {
        $b->set_font(size => 11);
        $b->text(($ml+$mr)/2, $mb + 40, $self->xlabel,
            align=>'center', valign=>'top');
    }

    # Y 90
    if ($self->ylabel ne '') {
        $b->set_font(size => 11);
        $b->text($ml - 30, ($mt+$mb)/2, $self->ylabel,
            align=>'center', valign=>'bottom', angle=>90);
    }
}

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
sub _draw_legend {
    my ($self, $b, $ml,$mt,$mr,$mb) = @_;
    my @legs = @{ $self->_legends };
    return unless @legs;

    my $fs   = 11;
    my $lh   = 20;
    my $pw   = 24;
    my $pad  = 8;

    $b->set_font(size => $fs);
    my $max_tw = 0;
    for my $lg (@legs) {
        my $tw = $b->text_width($lg->{label});
        $max_tw = $tw if $tw > $max_tw;
    }
    my $box_w = $pw + $pad*3 + $max_tw;
    my $box_h = $lh * scalar(@legs) + $pad;

    #

    my $loc = $self->{_legend_loc} // 'upper right';
    my ($lx,$ly);
    if    ($loc eq 'upper right')  { $lx = $mr - $box_w - 6; $ly = $mt + 6 }
    elsif ($loc eq 'upper left')   { $lx = $ml + 6;           $ly = $mt + 6 }
    elsif ($loc eq 'lower right')  { $lx = $mr - $box_w - 6; $ly = $mb - $box_h - 6 }
    elsif ($loc eq 'lower left')   { $lx = $ml + 6;           $ly = $mb - $box_h - 6 }
    else                           { $lx = $mr - $box_w - 6; $ly = $mt + 6 }

    #

    $b->set_color(1,1,1, 0.85);
    $b->rect_fill($lx, $ly, $box_w, $box_h);
    $b->set_color(0.6,0.6,0.6);
    $b->set_linewidth(1.5);
    $b->rect_stroke($lx, $ly, $box_w, $box_h);

    for my $i (0 .. $#legs) {
        my $lg  = $legs[$i];
        my $y0  = $ly + $pad/2 + $i * $lh + $lh/2;
        my $x0  = $lx + $pad;

        $b->set_color(@{$lg->{color}});

        if ($lg->{type} eq 'line') {
            $b->set_linewidth($lg->{lw} // 1.5);
            $b->line_seg($x0, $y0, $x0 + $pw, $y0);
        }
        elsif ($lg->{type} eq 'marker') {
            $b->marker($x0 + $pw/2, $y0, 4, $lg->{marker}//'o', 1);
        }
        elsif ($lg->{type} eq 'rect') {
            $b->rect_fill($x0, $y0-6, $pw, 12);
            $b->set_color(0,0,0);
            $b->set_linewidth(0.5);
            $b->rect_stroke($x0, $y0-6, $pw, 12);
        }

        $b->set_color(0,0,0);
        $b->set_font(size => $fs);
        $b->text($x0 + $pw + $pad, $y0, $lg->{label},
            align=>'left', valign=>'middle');
    }
}

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
sub _draw_colorbar {
    my ($self, $b, $ml, $mr, $mt, $mb) = @_;
    my $cb  = $self->_colorbar;
    return unless $cb;

    my $loc  = $self->colorbar_location;
    my $cw   = $self->colorbar_width;
    my $pad  = $self->colorbar_pad;
    my $frac = $self->colorbar_length;
    my $n    = 200;

    if ($loc eq 'right' || $loc eq 'left') {
        #

        my $full_h = $mb - $mt;
        my $h      = $full_h * $frac;
        my $y0     = $mt + ($full_h - $h) / 2;

        my ($cx, $label_x, $label_align, $tick_x0, $tick_x1);
        if ($loc eq 'right') {
            $cx         = $mr + $pad;
            $tick_x0    = $cx + $cw;
            $tick_x1    = $cx + $cw + 4;
            $label_x    = $cx + $cw + 7;
            $label_align = 'left';
        } else {  # left
            $cx         = $ml - $pad - $cw;
            $tick_x0    = $cx - 4;
            $tick_x1    = $cx;
            $label_x    = $cx - 7;
            $label_align = 'right';
        }

        #

        for my $i (0 .. $n-1) {
            my $v  = $i / ($n - 1);
            my ($r,$g,$bv) = $cb->{cmap}->rgb_at($v);
            my $yp = $y0 + $h - $v * $h;
            $b->colored_rect($cx, $yp - $h/$n, $cw, $h/$n + 1, $r, $g, $bv);
        }
        $b->set_color(0,0,0);
        $b->set_linewidth(1.5);
        $b->rect_stroke($cx, $y0, $cw, $h);

        #

        $b->set_font(size => 9);
        my @tks = nice_ticks($cb->{vmin}, $cb->{vmax}, 5);
        for my $v (@tks) {
            my $f  = ($v - $cb->{vmin}) / ($cb->{vmax} - $cb->{vmin});
            my $yp = $y0 + $h - $f * $h;
            $b->line_seg($tick_x0, $yp, $tick_x1, $yp);
            $b->text($label_x, $yp, _fmt_tick($v),
                align=>$label_align, valign=>'middle');
        }
    }
    else {
        #  (top / bottom)
        my $full_w = $mr - $ml;
        my $w      = $full_w * $frac;
        my $x0     = $ml + ($full_w - $w) / 2;

        my ($cy, $label_y, $label_valign, $tick_y0, $tick_y1);
        if ($loc eq 'bottom') {
            $cy          = $mb + $pad;
            $tick_y0     = $cy + $cw;
            $tick_y1     = $cy + $cw + 4;
            $label_y     = $cy + $cw + 14;
            $label_valign = 'top';
        } else {  # top
            $cy          = $mt - $pad - $cw;
            $tick_y0     = $cy - 4;
            $tick_y1     = $cy;
            $label_y     = $cy - 14;
            $label_valign = 'bottom';
        }

        #

        for my $i (0 .. $n-1) {
            my $v  = $i / ($n - 1);
            my ($r,$g,$bv) = $cb->{cmap}->rgb_at($v);
            my $xp = $x0 + $v * $w;
            $b->colored_rect($xp, $cy, $w/$n + 1, $cw, $r, $g, $bv);
        }
        $b->set_color(0,0,0);
        $b->set_linewidth(1.5);
        $b->rect_stroke($x0, $cy, $w, $cw);

        #

        $b->set_font(size => 9);
        my @tks = nice_ticks($cb->{vmin}, $cb->{vmax}, 5);
        for my $v (@tks) {
            my $f  = ($v - $cb->{vmin}) / ($cb->{vmax} - $cb->{vmin});
            my $xp = $x0 + $f * $w;
            $b->line_seg($xp, $tick_y0, $xp, $tick_y1);
            $b->text($xp, $label_y, _fmt_tick($v),
                align=>'center', valign=>$label_valign);
        }
    }
}


# ==================================================================
# pie() — 
# ==================================================================
sub pie {
    my ($self, $sizes, %opt) = @_;
    $sizes = pdl($sizes) unless ref($sizes) && $sizes->isa('PDL');

    my @s     = list($sizes);
    my $total = 0; $total += $_ for @s;
    my @labels = $opt{labels}     ? @{ $opt{labels}     } : map { '' }  @s;
    my @explode= $opt{explode}    ? @{ $opt{explode}    } : map { 0 }   @s;
    my $startangle = $opt{startangle} // 90;
    my $pct    = $opt{autopct}    // '';
    my $shadow = $opt{shadow}     // 0;

    push @{ $self->_queue }, {
        type      => 'pie',
        sizes     => \@s,
        total     => $total,
        labels    => \@labels,
        explode   => \@explode,
        startangle=> $startangle,
        autopct   => $pct,
        shadow    => $shadow,
    };

    # pie 
    $self->xmin(-1.4); $self->xmax(1.4);
    $self->ymin(-1.4); $self->ymax(1.4);
    return $self;
}

# ==================================================================
# vspan / hspan — xmin-xmax / ymin-ymax
# ==================================================================
sub axvspan {
    my ($self, $xlo, $xhi, %opt) = @_;
    my $color = $self->_parse_color($opt{color} // 'yellow');
    push @{ $self->_queue }, {
        type  => 'vspan',
        x1    => $xlo, x2 => $xhi,
        color => $color,
        alpha => $opt{alpha} // 0.2,
    };
    return $self;
}

sub axhspan {
    my ($self, $ylo, $yhi, %opt) = @_;
    my $color = $self->_parse_color($opt{color} // 'yellow');
    push @{ $self->_queue }, {
        type  => 'hspan',
        y1    => $ylo, y2 => $yhi,
        color => $color,
        alpha => $opt{alpha} // 0.2,
    };
    return $self;
}

# ==================================================================
# annotate() — 
# ==================================================================
sub annotate {
    my ($self, $text, %opt) = @_;
    # xy: , xytext: 
    my ($ax, $ay) = @{ $opt{xy}     // [0,0] };
    my ($tx, $ty) = @{ $opt{xytext} // [$ax+0.5, $ay+0.5] };
    my $color = $self->_parse_color($opt{color} // 'black');
    push @{ $self->_queue }, {
        type   => 'annotate',
        text   => $text,
        ax     => $ax, ay => $ay,
        tx     => $tx, ty => $ty,
        color  => $color,
        size   => $opt{fontsize} // 10,
        arrow  => $opt{arrowprops} // 1,
    };
    return $self;
}

# ==================================================================
# contourf() — 
#   $z  2D PDL (rows x cols)
# ==================================================================
sub contourf {
    my ($self, $x, $y, $z, %opt) = @_;
    $x = pdl($x) unless ref($x) && $x->isa('PDL');
    $y = pdl($y) unless ref($y) && $y->isa('PDL');
    $z = pdl($z) unless ref($z) && $z->isa('PDL');

    my $levels = $opt{levels} // 10;
    my $cmap   = PDL::Graphics::Cairo::ColorMap->new($opt{cmap} // 'viridis');
    my $vmin   = $opt{vmin} // $z->min;
    my $vmax   = $opt{vmax} // $z->max;

    push @{ $self->_queue }, {
        type   => 'contourf',
        x      => $x, y => $y, z => $z,
        levels => $levels,
        cmap   => $cmap,
        vmin   => $vmin,
        vmax   => $vmax,
        alpha  => $opt{alpha} // 1.0,
    };

    $self->_expand_range($x, $y);
    $self->_colorbar({ cmap => $cmap, vmin => $vmin, vmax => $vmax });
    return $self;
}

# ==================================================================
# set_aspect() — 'equal' or 
# ==================================================================
sub set_aspect {
    my ($self, $asp) = @_;
    $self->{_aspect} = $asp;
    return $self;
}

# colorbar location/width/pad/length 
sub colorbar {
    my ($self, %opt) = @_;
    $self->colorbar_location($opt{location} // $opt{loc} // 'right');
    $self->colorbar_width($opt{width}    // 16);
    $self->colorbar_pad($opt{pad}        // 10);
    $self->colorbar_length($opt{length}  // 1.0);
    # shrink  length 
    $self->colorbar_length($opt{shrink}) if exists $opt{shrink};
    return $self;
}

# ==================================================================
# invert_yaxis() / invert_xaxis()
# ==================================================================

# ==================================================================
# axis() — matplotlib axis('off') / axis('on')
# axis('off'): 枠・目盛り・ラベル・グリッドを全て非表示
# axis('on') : 通常表示に戻す
# ==================================================================
sub axis {
    my ($self, $arg) = @_;
    if (defined $arg) {
        $self->{_axis_off} = (lc($arg) eq 'off') ? 1 : 0;
    }
    return $self;
}


sub invert_yaxis {
    my ($self) = @_;
    $self->{_y_reversed} = 1;
    return $self;
}

sub invert_xaxis {
    my ($self) = @_;
    $self->{_invert_x} = 1;
    return $self;
}

# ==================================================================
# set_xticklabels / set_yticklabelsmatplotlib
# ==================================================================
sub set_xticklabels {
    my ($self, $labels, %opt) = @_;
    $self->_xticklabels($labels);
    $self->{_xtick_rot} = $opt{rotation} // 0;
    return $self;
}

sub set_yticklabels {
    my ($self, $labels, %opt) = @_;
    $self->_yticklabels($labels);
    return $self;
}

# ==================================================================
# tight_layout Figure
# ==================================================================
sub set_tight_layout { return $_[0] }


# ==================================================================
# set_xscale / set_yscale
# ==================================================================
sub set_xscale {
    my ($self, $scale) = @_;
    $self->xscale($scale);
    # log  ymin 
    if ($scale eq 'log' && defined $self->_xmin_auto && $self->_xmin_auto <= 0) {
        $self->_xmin_auto(1e-10);
    }
    return $self;
}

sub set_yscale {
    my ($self, $scale) = @_;
    $self->yscale($scale);
    if ($scale eq 'log' && defined $self->_ymin_auto && $self->_ymin_auto <= 0) {
        $self->_ymin_auto(1e-10);
    }
    return $self;
}

# loglog / semilogx / semilogy  (matplotlib)
sub loglog   { my $s = shift; $s->set_xscale('log'); $s->set_yscale('log'); $s->line(@_) }
sub semilogx { my $s = shift; $s->set_xscale('log'); $s->line(@_) }
sub semilogy { my $s = shift; $s->set_yscale('log'); $s->line(@_) }

# ==================================================================
# twinx — Y Axes 
#   : my $ax2 = $ax->twinx();
#           $ax2->line($x, $y2, color=>'red');
#   Figure::save() 
# ==================================================================
sub twinx {
    my ($self, %opt) = @_;

    #  fig_x/fig_y  Axes 
    my $twin = PDL::Graphics::Cairo::Axes->new(
        width         => $self->width,
        height        => $self->height,
        fig_x         => $self->fig_x,
        fig_y         => $self->fig_y,
        margin_left   => $self->margin_left,
        margin_right  => $self->margin_right,
        margin_top    => $self->margin_top,
        margin_bottom => $self->margin_bottom,
        grid          => 0,
    );

    # XselfdrawX
    $twin->{_is_twin}  = 1;
    $twin->{_twin_of}  = $self;

    # X  self draw
    $self->{_twin_ax}  = $twin;

    # Figure  axes_list  Figure::add_twin() 
    # axes_list pushFigure::save 
    return $twin;
}

# ==================================================================
# set_right_ylabel — twinx Y
# ==================================================================
sub set_right_ylabel {
    my ($self, $label, %opt) = @_;
    $self->{_right_ylabel} = $label;
    return $self;
}

# ==================================================================
# Figure::save
# ==================================================================
sub set_tight_layout { return $_[0] }

# ==================================================================
# savefig — Figure Axes  Figure 
# ==================================================================
# Figure::save() Axes savefig 

# ==================================================================
# cla() — Axes 
# ==================================================================
sub cla {
    my ($self) = @_;
    @{ $self->_queue   } = ();
    @{ $self->_legends } = ();
    $self->_color_idx(0);
    $self->xmin(undef); $self->xmax(undef);
    $self->ymin(undef); $self->ymax(undef);
    $self->_xmin_auto(undef); $self->_xmax_auto(undef);
    $self->_ymin_auto(undef); $self->_ymax_auto(undef);
    $self->_colorbar(undef);
    return $self;
}

# ==================================================================
# scatter scatter 
# ==================================================================
# scatter() 
# _colorbar  scatter 


# ==================================================================
# contour() — 
# ==================================================================
sub contour {
    my ($self, $x, $y, $z, %opt) = @_;
    $x = pdl($x) unless ref($x) && $x->isa('PDL');
    $y = pdl($y) unless ref($y) && $y->isa('PDL');
    $z = pdl($z) unless ref($z) && $z->isa('PDL');

    my $levels  = $opt{levels}  // 8;
    my $color   = $self->_parse_color($opt{color} // 'black');
    my $lw      = $opt{linewidth} // $opt{lw} // 1.0;
    my $vmin    = $opt{vmin} // $z->min;
    my $vmax    = $opt{vmax} // $z->max;

    push @{ $self->_queue }, {
        type   => 'contour',
        x => $x, y => $y, z => $z,
        levels => $levels,
        color  => $color,
        lw     => $lw,
        vmin   => $vmin,
        vmax   => $vmax,
    };
    $self->_expand_range($x, $y);
    return $self;
}

# ==================================================================
# violin() — 
# ==================================================================
sub violin {
    my ($self, $data, %opt) = @_;

    my @groups;
    if (ref($data) eq 'ARRAY') {
        @groups = @$data;
    } else {
        @groups = ($data);
    }

    my $positions = $opt{positions}
        ? pdl($opt{positions})
        : pdl(map { $_ + 1 } 0..$#groups);
    my $width  = $opt{widths}  // 0.4;
    my $color  = $self->_parse_color($opt{color} // 'steelblue');
    my $points = $opt{points} // 100;

    my @violins;
    for my $i (0..$#groups) {
        my $d   = $groups[$i]->flat;
        my $pos = $positions->at($i);
        my $mn  = $d->min;
        my $mx  = $d->max;
        my $std = $d->stddev + 1e-10;
        my $n   = $d->nelem;

        # Silverman 
        my $bw = 1.06 * $std * $n**(-0.2);

        # KDE 
        my $ys = $mn + sequence($points) * ($mx - $mn) / ($points - 1);
        my $ks = zeroes($points);
        for my $j (0 .. $n-1) {
            my $u = ($ys - $d->at($j)) / $bw;
            $ks  += exp(-0.5 * $u * $u);
        }
        $ks /= ($n * $bw * sqrt(2 * 3.14159265358979));

        #  = $width/2
        my $kmax = $ks->max;
        $ks *= ($width / 2) / $kmax if $kmax > 0;

        push @violins, {
            pos => $pos,
            ys  => $ys,
            ks  => $ks,
            med => $d->median,
            q1  => $d->pct(25),
            q3  => $d->pct(75),
        };
        $self->_expand_range(pdl($pos), $ys);
    }

    push @{ $self->_queue }, {
        type    => 'violin',
        violins => \@violins,
        color   => $color,
        alpha   => $opt{alpha} // 0.7,
        label   => $opt{label} // undef,
    };
    if (defined $opt{label}) {
        push @{ $self->_legends }, {
            type=>'rect', color=>$color, label=>$opt{label}
        };
    }
    return $self;
}

# ==================================================================
# quiver() — 
# ==================================================================
sub quiver {
    my ($self, $x, $y, $u, $v, %opt) = @_;
    $x = pdl($x) unless ref($x) && $x->isa('PDL');
    $y = pdl($y) unless ref($y) && $y->isa('PDL');
    $u = pdl($u) unless ref($u) && $u->isa('PDL');
    $v = pdl($v) unless ref($v) && $v->isa('PDL');

    my $scale  = $opt{scale}  // 1.0;
    my $color  = $self->_parse_color($opt{color} // 'black');
    my $width  = $opt{width}  // 1.0;

    push @{ $self->_queue }, {
        type  => 'quiver',
        x => $x, y => $y, u => $u, v => $v,
        scale => $scale,
        color => $color,
        lw    => $width,
    };
    $self->_expand_range($x, $y);
    return $self;
}

# ==================================================================
# heatmap() — 
#   $data: 2D PDL (rows x cols)
#   xticklabels / yticklabels 
# ==================================================================
sub heatmap {
    my ($self, $data, %opt) = @_;
    $data = pdl($data) unless ref($data) && $data->isa('PDL');

    my @dims   = $data->dims;
    my ($rows, $cols) = @dims;

    my $cmap   = PDL::Graphics::Cairo::ColorMap->new($opt{cmap} // 'viridis');
    my $vmin   = $opt{vmin} // $data->min;
    my $vmax   = $opt{vmax} // $data->max;
    my $annot  = $opt{annot} // 0;
    my $fmt    = $opt{fmt}   // '%.1f';

    my @xlabs  = $opt{xticklabels}
        ? @{ $opt{xticklabels} }
        : map { $_ } 0..$cols-1;
    my @ylabs  = $opt{yticklabels}
        ? @{ $opt{yticklabels} }
        : map { $_ } 0..$rows-1;

    push @{ $self->_queue }, {
        type   => 'heatmap',
        data   => $data,
        cmap   => $cmap,
        vmin   => $vmin,
        vmax   => $vmax,
        annot  => $annot,
        fmt    => $fmt,
        xlabs  => \@xlabs,
        ylabs  => \@ylabs,
    };

    #

    $self->xmin(-0.5); $self->xmax($cols - 0.5);
    $self->ymin(-0.5); $self->ymax($rows - 0.5);
    $self->_xticks([map { $_ } 0..$cols-1]);
    $self->_xticklabels(\@xlabs);
    $self->_yticks([map { $_ } 0..$rows-1]);
    $self->_yticklabels(\@ylabs);

    $self->_colorbar({ cmap => $cmap, vmin => $vmin, vmax => $vmax });
    return $self;
}

# ==================================================================
# stackplot() — 
# ==================================================================
sub stackplot {
    my ($self, $x, @ys_and_opts) = @_;

    #  hashref  opt
    my %opt;
    %opt = %{ pop @ys_and_opts } if ref($ys_and_opts[-1]) eq 'HASH';

    $x = pdl($x) unless ref($x) && $x->isa('PDL');

    my @ys  = map { ref($_) && $_->isa('PDL') ? $_ : pdl($_) } @ys_and_opts;
    my $labels = $opt{labels} // [];

    #

    my $base = zeroes($x->nelem);
    for my $i (0..$#ys) {
        my $top   = $base + $ys[$i];
        my $color = exists $opt{colors}
            ? $self->_parse_color($opt{colors}[$i])
            : $self->_next_color();
        my $label = $labels->[$i] // undef;

        push @{ $self->_queue }, {
            type  => 'fill_between',
            x     => $x,
            y1    => $base->copy,
            y2    => $top->copy,
            color => $color,
            alpha => $opt{alpha} // 0.85,
            label => $label,
        };
        if (defined $label) {
            push @{ $self->_legends }, {
                type=>'rect', color=>$color, label=>$label
            };
        }
        $self->_expand_range($x, $top);
        $base = $top;
    }
    return $self;
}

# ==================================================================
# eventplot() — 
# ==================================================================
sub eventplot {
    my ($self, $positions, %opt) = @_;

    # ArrayRef of arrays → 
    my @channels;
    if (ref($positions) eq 'ARRAY' && ref($positions->[0]) eq 'ARRAY') {
        @channels = map { pdl($_) } @$positions;
    } elsif (ref($positions) eq 'ARRAY') {
        @channels = (pdl($positions));
    } else {
        @channels = ($positions);
    }

    my $orientation = $opt{orientation} // 'horizontal';
    my $linelengths = $opt{linelengths} // 0.9;
    my $linewidths  = $opt{linewidths}  // 1.0;

    for my $i (0..$#channels) {
        my $ev    = $channels[$i];
        my $ypos  = $i + 1;
        my $color = $self->_next_color();

        push @{ $self->_queue }, {
            type        => 'eventplot',
            events      => $ev,
            ypos        => $ypos,
            linelengths => $linelengths,
            linewidths  => $linewidths,
            color       => $color,
            orientation => $orientation,
        };
        $self->_expand_range($ev, pdl($ypos - 0.5, $ypos + 0.5));
    }
    return $self;
}

*hist = \&histogram;
1;
