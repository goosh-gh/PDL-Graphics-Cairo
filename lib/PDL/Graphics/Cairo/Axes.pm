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
use PDL::Graphics::Cairo::TextLayout qw(ml_layout ml_max_width);
# PDL exports hist; override with our method
no warnings "redefine";
# List::Util  min/max  PDL 
sub _min { my $m = shift; for (@_) { $m = $_ if $_ < $m } $m }
sub _max { my $m = shift; for (@_) { $m = $_ if $_ > $m } $m }

# log スケール軸向けの range padding。
# 線形の nice_range(min,max,ratio) は span*ratio を引く/足すだけなので、
# 正の log データに適用すると min が容易に <=0 になってしまう
# (例: x=[1,1e5] で 0.03*99999 ≈ 3000 を引くと負になる)。
# log軸では「桁(decade)」を単位にパディングし、min は必ず正に保つ。
sub _nice_log_range {
    my ($min, $max) = @_;
    $min = 1e-300 if !defined($min) || $min <= 0;
    $max = $min * 10 if !defined($max) || $max <= $min;

    my $lo = floor(log($min) / log(10));
    my $hi = ceil( log($max) / log(10));
    $hi = $lo + 1 if $hi <= $lo;

    return (10 ** $lo, 10 ** $hi);
}

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
use PDL::Graphics::Cairo::Tick qw(nice_ticks nice_range minor_ticks nice_date_ticks fmt_date_tick);
use PDL::Graphics::Cairo::ColorMap;
use PDL::Graphics::Cairo::ListedColormap;

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
has title           => (is => 'rw', default => sub { '' });
has xlabel          => (is => 'rw', default => sub { '' });
has ylabel          => (is => 'rw', default => sub { '' });
has ylabel_rotation => (is => 'rw', default => sub { 90 });  # 0=横書き 90=縦書き（デフォルト）

# ------------------------------------------------------------------
# 'linear' / 'log'
# ------------------------------------------------------------------
has xscale => (is => 'rw', default => sub { 'linear' });
has _xaxis_is_date => (is => 'rw', default => sub { 0 });
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
has colorbar_label    => (is => 'rw', default => sub { '' });

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

has _figure      => (is => 'rw');
has _is_twin     => (is => 'rw', default => sub { 0 });
has _twin_of     => (is => 'rw', default => sub { undef });
has _twin_type   => (is => 'rw', default => sub { undef });
has _twin_ax     => (is => 'rw', default => sub { undef });
# 1つの親Axesに対してtwinx()とtwiny()を両方呼んだ場合、両方のtwin
# オブジェクトをtight_layout/title描画から参照できるようにするための
# 配列。_twin_axは後方互換性のため残すが(twinx()が単一値として設定)、
# 複数twin対応のロジックは_twin_axesを使う。
has _twin_axes   => (is => 'rw', default => sub { [] });
has _inset_axes  => (is => 'ro', default => sub { [] });
has _is_inset    => (is => 'rw', default => sub { 0 });

# uniform_margins => 1 のグリッド表示時にセットされるフラグ。
# title/xlabel/ylabel のフォントサイズと固定オフセットを少し縮小し、
# 多パネル時に「タイトルと直上パネルのxlabelの間が間延びして見える」
# 問題を緩和する。単一figure表示には影響しない。
has _compact_labels => (is => 'rw', default => sub { 0 });
# draw() が確定した plot 矩形キャッシュ（image_frac_to_data 用）
has _plot_ml     => (is => 'rw');   # プロット枠左端 (pixel, Figure座標)
has _plot_mr     => (is => 'rw');   # プロット枠右端
has _plot_mt     => (is => 'rw');   # プロット枠上端
has _plot_mb     => (is => 'rw');   # プロット枠下端
has _color_idx   => (is => 'rw', default => sub { 0 });
has _xformatter  => (is => 'rw', default => sub { undef });
has _yformatter  => (is => 'rw', default => sub { undef });
has _tick_params    => (is => 'rw', default => sub { {} });
has _minor_ticks_on => (is => 'rw', default => sub { 0 });
has _minor_n        => (is => 'rw', default => sub { 5 });
has _facecolor      => (is => 'rw', default => sub { undef });  # set_facecolor() 用

# _resolve_cmap($cmap_spec) -- accept string name or object
# Returns a ColorMap or ListedColormap object
sub _resolve_cmap {
    my ($self, $spec) = @_;
    $spec //= 'viridis';
    # Already a colormap object
    if (ref($spec) && (
        $spec->isa('PDL::Graphics::Cairo::ColorMap') ||
        $spec->isa('PDL::Graphics::Cairo::ListedColormap'))) {
        return $spec;
    }
    # String name
    return PDL::Graphics::Cairo::ColorMap->new($spec);
}

sub _next_color {
    my ($self) = @_;
    # rcParams に '_color_cycle' があればそれを優先（style.use() 連携）
    my $cycle = $PDL::Graphics::Cairo::_RCPARAMS{_color_cycle};
    my @cycle_colors;
    if ($cycle && ref($cycle) eq 'ARRAY' && @$cycle) {
        @cycle_colors = @$cycle;
    } else {
        @cycle_colors = @COLOR_CYCLE;
    }
    my $c = $cycle_colors[$self->_color_idx % scalar @cycle_colors];
    $self->_color_idx($self->_color_idx + 1);
    # 文字列カラー('#rrggbb')はparse、配列参照はそのまま
    return ref($c) ? $c : $self->_parse_color($c);
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
    # log スケールの軸には線形 margin_ratio を適用しない。
    # 線形パディングを log データ（例: x=[1, 1e5]）に適用すると
    # xmn が負になり、Scale::Log::nice_ticks が異常な桁範囲
    # （例: 10^-10 〜 10^6）を生成してしまうため。
    # log軸では桁（decade）単位で軽くパディングする。
    unless (defined $self->xmin && defined $self->xmax) {
        if ($self->xscale eq 'log') {
            ($xmn, $xmx) = _nice_log_range($xmn, $xmx);
        } else {
            ($xmn, $xmx) = nice_range($xmn, $xmx, 0.03);
        }
    }
    unless (defined $self->ymin && defined $self->ymax) {
        if ($self->yscale eq 'log') {
            ($ymn, $ymx) = _nice_log_range($ymn, $ymx);
        } else {
            ($ymn, $ymx) = nice_range($ymn, $ymx, 0.05);
        }
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
    $x = pdl($x) unless ref($x) eq 'PDL' || (ref($x) && eval { $x->isa('PDL') });
    $y = pdl($y) unless ref($y) eq 'PDL' || (ref($y) && eval { $y->isa('PDL') });

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
        marker    => $opt{marker}     // undef,  # 'o','s','^','d','+','x' or undef=no marker
        ms        => $opt{markersize} // $opt{ms} // 4,
        fill      => (($opt{fillstyle}//'full') eq 'none') ? 0 : 1,
    };
    $self->_expand_range($x, $y);
    if (defined $opt{label}) {
        push @{ $self->_legends }, { type=>'line', color=>$color, label=>$opt{label},
            lw=>$opt{linewidth}//1.5, ls=>$opt{linestyle}//'solid' };
    }
    return $self;
}

sub polyline; *polyline = \&line;
# matplotlib では plot() が正準名。P:G:C では plot/line 両方サポート。
# ドキュメント・examples の第一表記は plot() に揃える。
sub plot;     *plot     = \&line;

# ---- plot_date -----------------------------------------------------
# plot_date($x, $y, %opt) — X軸を日付/時刻軸として扱うline()のラッパー。
# matplotlibのAxes.plot_date()、gnuplotの`set xdata time`相当。
#
# $x は次のいずれかの形式を受け付ける:
#   - UNIX time(エポック秒)の数値配列またはPDL  (例: [1700000000, 1700003600, ...])
#   - Perl DateTime オブジェクトの配列ref        (例: [$dt1, $dt2, ...])
#   - 上記の混在も可(要素ごとに判定)
#
# 内部的にはすべてUNIX time(秒、UTC)の数値に変換してline()と同じ
# キュー形式に積み、Axesに「このAxesのX軸は日付軸である」という
# フラグ(_xaxis_is_date)を立てる。これにより_draw_frame()のX軸目盛り
# ラベル計算が nice_date_ticks/fmt_date_tick に切り替わる。
#
# 複数回呼んでも(twinx等を除き)Axes全体で1つのX軸を共有するため、
# 一度でもplot_date()を使えばそのAxesのX軸は日付軸として扱われる。
sub plot_date {
    my ($self, $x, $y, %opt) = @_;

    my @x_epoch;
    if (ref($x) eq 'ARRAY') {
        for my $v (@$x) {
            if (ref($v) && eval { $v->isa('DateTime') }) {
                push @x_epoch, $v->epoch;
            } else {
                push @x_epoch, $v;
            }
        }
    }
    elsif (ref($x) && eval { $x->isa('PDL') }) {
        @x_epoch = list($x);
    }
    else {
        # 単一のDateTimeまたは単一の数値が渡された場合(通常は配列を期待するが
        # 念のためフォールバック)
        if (ref($x) && eval { $x->isa('DateTime') }) {
            @x_epoch = ($x->epoch);
        } else {
            @x_epoch = ($x);
        }
    }

    $self->_xaxis_is_date(1);
    return $self->line(pdl(@x_epoch), $y, %opt);
}

# ---- scatter -----------------------------------------------------
# hexbin($x, $y, %opt) -- 2D hexagonal binning
# Options: gridsize (default 20), cmap, mincnt (default 1),
#          vmin, vmax, alpha, reduce_C_function (ignored, count only)
sub hexbin {
    my ($self, $x, $y, %opt) = @_;
    $x = pdl($x) unless ref($x) && $x->isa('PDL');
    $y = pdl($y) unless ref($y) && $y->isa('PDL');

    push @{ $self->_queue }, {
        type     => 'hexbin',
        x        => $x,
        y        => $y,
        gridsize => $opt{gridsize} // 20,
        cmap     => $opt{cmap}     // 'viridis',
        mincnt   => $opt{mincnt}   // 1,
        alpha    => $opt{alpha}    // 1.0,
        vmin     => $opt{vmin},
        vmax     => $opt{vmax},
        label    => $opt{label},
    };
    $self->_expand_range($x, $y);

    # Set up colorbar
    my $cmap_obj = $self->_resolve_cmap($opt{cmap});
    $self->_colorbar({ cmap => $cmap_obj,
                       vmin => $opt{vmin} // 0,
                       vmax => $opt{vmax} // 1 });
    return $self;
}

# specgram($x, %opt) -- Short-Time Fourier Transform spectrogram
# Options:
#   Fs       => sample rate in Hz (default 1)
#   NFFT     => FFT window size (default 256)
#   noverlap => overlap samples (default NFFT/2)
#   window   => 'hann' | 'hamming' | 'blackman' | 'none' (default 'hann')
#   cmap     => colormap name or object (default 'viridis')
#   vmin     => min power in dB (default auto)
#   vmax     => max power in dB (default auto)
#   sides    => 'onesided' | 'twosided' (default 'onesided')
#   scale    => 'dB' | 'linear' (default 'dB')
#   detrend  => 'none' | 'mean' (default 'none')
sub specgram {
    my ($self, $x, %opt) = @_;
    $x = pdl($x) unless ref($x) && $x->isa('PDL');
    $x = $x->flat;

    my $Fs       = $opt{Fs}       // 1;
    my $NFFT     = $opt{NFFT}     // 256;
    my $noverlap = $opt{noverlap} // int($NFFT / 2);
    my $wname    = $opt{window}   // 'hann';
    my $cmap     = $opt{cmap}     // 'viridis';
    my $sides    = $opt{sides}    // 'onesided';
    my $scale    = $opt{scale}    // 'dB';
    my $detrend  = $opt{detrend}  // 'none';

    my $step     = $NFFT - $noverlap;
    my $npts     = $x->nelem;
    my $nframes  = int(($npts - $NFFT) / $step) + 1;
    die "specgram: signal too short (need >= NFFT=$NFFT samples)" if $nframes < 1;

    # Build window function
    my $win;
    if ($wname eq 'hann' || $wname eq 'hanning') {
        $win = 0.5 * (1 - cos(2 * 3.14159265358979 * sequence($NFFT) / ($NFFT - 1)));
    } elsif ($wname eq 'hamming') {
        $win = 0.54 - 0.46 * cos(2 * 3.14159265358979 * sequence($NFFT) / ($NFFT - 1));
    } elsif ($wname eq 'blackman') {
        my $n = sequence($NFFT) / ($NFFT - 1);
        $win = 0.42 - 0.5 * cos(2 * 3.14159265358979 * $n)
                    + 0.08 * cos(4 * 3.14159265358979 * $n);
    } else {
        $win = ones($NFFT);
    }
    my $win_norm = ($win * $win)->sum->sqrt->at(0);
    $win_norm = 1 if $win_norm == 0;

    # STFT: compute power spectrum for each frame
    my $nfreqs = $sides eq 'onesided' ? int($NFFT/2) + 1 : $NFFT;

    # Build spectrogram matrix: [nfreqs x nframes]
    my $spec = zeroes($nfreqs, $nframes);

    for my $fi (0 .. $nframes - 1) {
        my $start = $fi * $step;
        my $seg   = $x->slice("$start:" . ($start + $NFFT - 1))->copy;

        # Detrend
        if ($detrend eq 'mean') {
            $seg -= $seg->avg;
        }

        # Apply window
        $seg *= $win;

        # FFT using PDL::FFT
        my $re = $seg->copy->double;
        my $im = zeroes($NFFT)->double;
        eval { require PDL::FFT; PDL::FFT::fft($re, $im) };
        if ($@) {
            # Fallback: DFT (slow but always available)
            my $re2 = zeroes($NFFT)->double;
            my $im2 = zeroes($NFFT)->double;
            for my $k (0 .. $NFFT-1) {
                for my $n (0 .. $NFFT-1) {
                    my $angle = -2 * 3.14159265358979 * $k * $n / $NFFT;
                    $re2->set($k, $re2->at($k) + $seg->at($n) * cos($angle));
                    $im2->set($k, $im2->at($k) + $seg->at($n) * sin($angle));
                }
            }
            $re = $re2; $im = $im2;
        }

        # Power spectrum
        my $power = ($re * $re + $im * $im) / ($win_norm * $win_norm);
        my $pslice = $power->slice("0:" . ($nfreqs - 1));

        # Double non-DC/Nyquist bins for onesided
        if ($sides eq 'onesided') {
            $pslice->slice("1:" . ($nfreqs - 2)) *= 2
                if $nfreqs > 2;
        }

        $spec->slice(":,$fi") .= $pslice;
    }

    # Convert to dB
    if ($scale eq 'dB') {
        $spec = 10 * log10($spec + 1e-300);
    }

    # Compute time and frequency axes
    my @times = map { ($_ * $step + $NFFT/2) / $Fs } 0..$nframes-1;
    my @freqs = $sides eq 'onesided'
        ? map { $_ * $Fs / $NFFT } 0..$nfreqs-1
        : map { (($_ <= $NFFT/2) ? $_ : $_ - $NFFT) * $Fs / $NFFT } 0..$nfreqs-1;

    my $vmin = $opt{vmin} // $spec->min->at(0);
    my $vmax = $opt{vmax} // $spec->max->at(0);

    push @{ $self->_queue }, {
        type  => 'specgram',
        spec  => $spec,       # [nfreqs x nframes]
        times => \@times,
        freqs => \@freqs,
        cmap  => $cmap,
        vmin  => $vmin,
        vmax  => $vmax,
    };

    # Set axis ranges
    $self->_expand_range(pdl($times[0], $times[-1]),
                         pdl($freqs[0], $freqs[-1]));

    # Colorbar
    my $cmap_obj = $self->_resolve_cmap($cmap);
    $self->_colorbar({ cmap => $cmap_obj, vmin => $vmin, vmax => $vmax });

    return $self;
}

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
        fill   => (($opt{fillstyle}//'full') eq 'none') ? 0 : 1,
        # c  PDL 
        cdata  => (ref($opt{c}) && $opt{c}->isa('PDL')) ? $opt{c} : undef,
        cmap   => $opt{cmap}   // 'viridis',
    };
    $self->_expand_range($x, $y);
    # cdata 
    if (ref($opt{c}) && $opt{c}->isa('PDL')) {
        my ($cdmin, $cdmax) = $opt{c}->minmax;
        my $cmap_obj = $self->_resolve_cmap($opt{cmap});
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

    # yerr: errorbar()と同じ慣習で対称(yerr=>5 or yerr=>[...])と
    # 非対称(yerr=>[\@lo, \@hi] or yerr_low=>.., yerr_high=>..)の
    # 両方をサポートする。
    my ($yerr_lo, $yerr_hi);
    if (exists $opt{yerr_low} || exists $opt{yerr_high}) {
        $yerr_lo = exists $opt{yerr_low}  ? pdl($opt{yerr_low})  : pdl(0);
        $yerr_hi = exists $opt{yerr_high} ? pdl($opt{yerr_high}) : pdl(0);
    }
    elsif (exists $opt{yerr}) {
        my $ye = $opt{yerr};
        if (ref($ye) eq 'ARRAY' && @$ye == 2 && (ref($ye->[0]) eq 'ARRAY' || (ref($ye->[0]) && $ye->[0]->isa('PDL')))) {
            # yerr=>[\@lo, \@hi] 形式（非対称）
            $yerr_lo = pdl($ye->[0]);
            $yerr_hi = pdl($ye->[1]);
        } else {
            # yerr=>5 または yerr=>[...]（対称）
            $yerr_lo = $yerr_hi = pdl($ye);
        }
    }

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
        yerr_lo => $yerr_lo,
        yerr_hi => $yerr_hi,
        capsize => $opt{capsize}  // 4,
    };
    #

    my $w_pdl = ref($width) && UNIVERSAL::isa($width,'PDL') ? $width : pdl($width);
    my $xmin = ($x - $w_pdl/2)->min;
    my $xmax = ($x + $w_pdl/2)->max;
    my $ymax_base = ($height + $bottom)->max;
    # yerrがある場合、誤差バー上端も描画範囲(_expand_range)に含める。
    my $ymax = defined($yerr_hi) ? ($height + $bottom + $yerr_hi)->max : $ymax_base;
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
        fill   => (($opt{fillstyle}//'full') eq 'none') ? 0 : 1,
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

    # where: PDL boolean マスク (1=塗りつぶす, 0=塗らない)
    # matplotlib の fill_between(x, y1, y2, where=y1>y2) に相当。
    # マスクが指定された場合は連続した True 区間ごとに個別 polygon を作る。
    my $mask = $opt{where};   # PDL or undef

    push @{ $self->_queue }, {
        type  => 'fill_between',
        x     => $x, y1 => $y1, y2 => $y2,
        color => $color,
        alpha => $opt{alpha} // 0.3,
        label => $opt{label} // undef,
        mask  => $mask,
    };
    if (defined $mask) {
        # マスクが True の点の y1/y2 範囲だけを expand_range に含める
        my $m = $mask->isa('PDL') ? $mask : pdl($mask);
        my $xi  = $x->where($m);
        my $y1i = $y1->where($m);
        my $y2i = $y2->where($m);
        $self->_expand_range($xi, $y1i->append($y2i)) if $xi->nelem > 0;
    } else {
        $self->_expand_range($x, $y1->append($y2));
    }
    if (defined $opt{label}) {
        push @{ $self->_legends }, {
            type  => 'fill',
            color => $color,
            alpha => $opt{alpha} // 0.3,
            label => $opt{label},
        };
    }
    return $self;
}

# ---- imshow ------------------------------------------------------
sub imshow {
    my ($self, $data, %opt) = @_;
    # $data  2D PDL (rows x cols)  3D (rows x cols x 3) RGB
    $data = pdl($data) unless ref($data) && $data->isa('PDL');

    my $cmap  = $self->_resolve_cmap($opt{cmap});
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
    # 水平/垂直そろえ: matplotlib 系 (ha/va) と本エコシステム由来 (halign/
    # valign) の両綴りを受ける。以前は ha/va しか読まず、halign/valign 指定は
    # 黙って default(left/bottom) に落ちていた（＝「halign に頼るな」の罠の実体）。
    my $ha = $opt{ha} // $opt{halign} // 'left';
    my $va = $opt{va} // $opt{valign} // 'bottom';
    # 'center' 正規化: 水平は 'center' のまま backend が解釈、垂直は 'middle'。
    $va = 'middle' if $va eq 'center';
    push @{ $self->_queue }, {
        type   => 'annot',
        x      => $x,  y   => $y,
        str    => $str,
        color  => $self->_parse_color($opt{color} // 'black'),
        size   => $opt{fontsize} // 11,
        align  => $ha,
        valign => $va,
        angle  => $opt{rotation} // 0,
        # 複数行 ("a\nb") 時の行送り倍率。matplotlib 既定と同じ 1.2。
        line_spacing => $opt{line_spacing} // 1.2,
    };
    return $self;
}

# ------------------------------------------------------------------
# 複数行テキスト描画ヘルパー (実体は TextLayout.pm、backend 非依存)
# ------------------------------------------------------------------
# _text_ml($b,$x,$y,$str,%opt): "a\nb" を行分割し、行送り・halign・valign
# 縦センタリング・回転を解決して backend text() へ流す薄いラッパ。
# レイアウト計算そのものは ml_layout() (PDL::Graphics::Cairo::TextLayout) に
# 委譲する。
#
# halign(right/center) は backend の align 実装に依存せず、ここで text_width を
# 実測して明示的な左アンカー座標に解決する(Xlib/giza-server は align=>'right'を
# honor しないため。2026-07-19)。よって最終的に backend へ渡す align は常に
# 'left'。左寄せは幅測定不要なのでスキップする。呼び出し側は set_font 済みで
# あること(幅測定のため)。
sub _text_ml {
    my ($self, $b, $x, $y, $str, %opt) = @_;
    my $align = $opt{align} // 'left';

    my $widths;
    if ($align ne 'left') {
        my @lines = split /\n/, (defined $str ? $str : ''), -1;
        $widths = [ map { eval { $b->text_width($_) } // 0 } @lines ];
    }

    for my $op (ml_layout($x, $y, $str, %opt, widths => $widths)) {
        my ($sx, $sy, $line, $al, $va, $ang) = @$op;
        $b->text($sx, $sy, $line, align => $al, valign => $va, angle => $ang);
    }
    return $self;
}

# _text_width_ml($b,$str): 複数行ラベルの「最長行」の幅(px)。
# tight_layout / ylabel 配置のマージン確保で最長行が切れないよう使う。
sub _text_width_ml {
    my ($self, $b, $str) = @_;
    return ml_max_width($str, sub { $b->text_width($_[0]) });
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

# matplotlib Axes-method 名のエイリアス（短縮形 xlim/ylim が正準実装）。
# set_ylim も lo>hi の Y軸反転則をそのまま継承する。
sub set_xlim { my $s = shift; $s->xlim(@_) }
sub set_ylim { my $s = shift; $s->ylim(@_) }

sub set_limits {
    my ($self, $xmin, $xmax, $ymin, $ymax) = @_;
    $self->xlim($xmin,$xmax)->ylim($ymin,$ymax);
}

sub xticks {
    my ($self, $ticks, $labels) = @_;
    # PDL ndarray / scalar → arrayref に正規化。
    # _xticks を boolean 判定する箇所で multielement ndarray エラーを防ぐ。
    if (defined $ticks) {
        # UNIVERSAL::isa を使う: unblessed ARRAY ref に ->isa() は呼べないため
        $ticks = UNIVERSAL::isa($ticks, 'PDL')
            ? [ PDL::list($ticks) ]
            : ref($ticks) eq 'ARRAY' ? $ticks : [$ticks];
    }
    $self->_xticks($ticks);
    $self->_xticklabels($labels) if defined $labels;
    return $self;
}


sub yticks {
    my ($self, $ticks, $labels) = @_;
    if (defined $ticks) {
        # UNIVERSAL::isa を使う: unblessed ARRAY ref に ->isa() は呼べないため
        $ticks = UNIVERSAL::isa($ticks, 'PDL')
            ? [ PDL::list($ticks) ]
            : ref($ticks) eq 'ARRAY' ? $ticks : [$ticks];
    }
    $self->_yticks($ticks);
    $self->_yticklabels($labels) if defined $labels;
    return $self;
}


# matplotlib Axes-method 名のエイリアス（xticks/yticks が正準実装）
sub set_xticks { my $s = shift; $s->xticks(@_) }
sub set_yticks { my $s = shift; $s->yticks(@_) }

sub legend {
    my ($self, %opt) = @_;
    $self->{_show_legend} = 1;
    $self->{_legend_loc}  = $opt{loc} // 'upper right';
    return $self;
}

sub set_title  { my ($s,$t,%o) = @_; $s->title($t);  return $s }
sub set_xlabel { my ($s,$t,%o) = @_; $s->xlabel($t); return $s }
sub set_ylabel { my ($s,$t,%o) = @_; $s->ylabel($t); $s->ylabel_rotation($o{rotation}) if exists $o{rotation}; return $s }

# set_facecolor($color) — matplotlib ax.set_facecolor() 相当
# 軸プロット領域の背景色を設定する。'white','#EAEAF2' 等を受け付ける。
# rcParams['axes.facecolor'] のデフォルト値を個別 Axes でオーバーライドする
# 用途。seaborn スタイルの薄グレー背景、dark_background 等と組み合わせて使う。
sub set_facecolor {
    my ($self, $color) = @_;
    $self->_facecolor($self->_parse_color($color));
    return $self;
}

# set_position([left, bottom, width, height]) — matplotlib ax.set_position() 相当
# Figure fraction 座標 (0-1) で Axes の位置・サイズを直接指定する。
# tight_layout() を呼ばずに細かい配置を制御したいときに使う。
# $pos は [left, bottom, width, height] の arrayref。
# (matplotlib の Bbox 形式: 原点が左下)
sub set_position {
    my ($self, $pos) = @_;
    die "set_position: need [left, bottom, width, height] arrayref\n"
        unless ref($pos) eq 'ARRAY' && @$pos == 4;

    my ($left, $bottom, $w_frac, $h_frac) = @$pos;
    # Figure サイズを取得 (Figure への参照があれば使う)
    my ($fw, $fh) = (800, 600);  # デフォルト
    if (my $fig = $self->_figure) {
        $fw = $fig->width;
        $fh = $fig->height;
    }
    # matplotlib は Y 原点=下端 (bottom)、P:G:C は Y 原点=上端 (fig_y=top)
    my $new_x = int($left   * $fw);
    my $new_y = int((1 - $bottom - $h_frac) * $fh);  # bottom → screen top
    my $new_w = int($w_frac * $fw);
    my $new_h = int($h_frac * $fh);

    $self->{fig_x}  = $new_x;
    $self->{fig_y}  = $new_y;
    $self->{width}  = $new_w;
    $self->{height} = $new_h;
    return $self;
}

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

    # ylabel位置調整用キャッシュ（_draw_grid内で実測してセットされる）を
    # draw毎にリセットする。再描画時に古いフォントサイズ/ラベル文字列に
    # 基づく幅が残ると ylabel がずれた位置に描かれるため。
    delete $self->{_y_ticklabel_maxw};

    # 再描画安全化: _finalize_range() は autoscale 解決値を xmin/xmax/ymin/ymax に
    # 書き戻すが、これらは xlim()/ylim() のユーザ指定値と枠を兼用している。
    # 書き戻したまま放置すると 2 回目以降の draw（再 to_inline / append 再描画）で
    # 旧フレームのレンジに固着する。ユーザ意図（未指定なら undef）を退避し、
    # 描画後に元へ戻すことで draw を冪等にする。
    my @user_lim = ($self->xmin, $self->xmax, $self->ymin, $self->ymax);

    $self->_finalize_range();

    # twinx / twiny: parent と軸・マージンを共有する
    if ($self->_is_twin && $self->_twin_of) {
        my $parent = $self->_twin_of;
        $parent->_finalize_range() unless defined $parent->xmin;

        if (($self->_twin_type // '') eq 'y') {
            # twiny: Y 軸を共有、X 軸は独立（上端に第2目盛り）
            $self->ymin($parent->ymin);
            $self->ymax($parent->ymax);
        } else {
            # twinx (デフォルト): X 軸を共有、Y 軸は独立（右端に第2目盛り）
            $self->xmin($parent->xmin);
            $self->xmax($parent->xmax);
        }
        # マージンは常に parent と揃える
        $self->margin_left(  $parent->margin_left);
        $self->margin_top(   $parent->margin_top);
        $self->margin_bottom($parent->margin_bottom);
        $self->margin_right( $parent->margin_right);
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

    # draw() が確定した plot 矩形を image_frac_to_data 用にキャッシュ
    $self->_plot_ml($ml);
    $self->_plot_mr($mr);
    $self->_plot_mt($mt);
    $self->_plot_mb($mb);

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
    # --- プロット領域背景 (facecolor) ---
    # set_facecolor() または rcParams['axes.facecolor'] に従って塗りつぶす。
    # デフォルト white は Cairo::ImageSurface の白背景と同じなので実質 no-op。
    # dark_background スタイルや seaborn スタイルで有効になる。
    if (!$self->{_axis_off}) {
        my $fc = $self->_facecolor;
        unless (defined $fc) {
            my $rcp_fc = $PDL::Graphics::Cairo::_RCPARAMS{'axes.facecolor'} // 'white';
            $fc = $self->_parse_color($rcp_fc) unless $rcp_fc eq 'white';
        }
        if (defined $fc) {
            $backend->set_color(@$fc, 1.0);
            $backend->rect_fill($ml, $mt, $mr - $ml, $mb - $mt);
            $backend->set_color(0, 0, 0, 1.0);  # 前景色を黒に戻す
        }
    }

    $self->_draw_grid($backend, $tr, $ml,$mt,$mr,$mb) if $self->grid && !$self->{_axis_off};

    # --- ---
    $backend->save;
    my $clip_w = $mr - $ml + 2;
    my $clip_h = $mb - $mt + 16;
    if ($clip_w > 0 && $clip_h > 0) {
        # :  + (14px)
        $backend->clip_rect($ml-1, $mt-15, $clip_w, $clip_h);
    }

    # ---  ---
    for my $cmd (@{ $self->_queue }) {
        $self->_render_cmd($backend, $tr, $cmd, $ml,$mt,$mr,$mb);
    }

    $backend->restore;

    # ---  ---
    if ($self->_is_twin) {
        if (($self->_twin_type // '') eq 'y') {
            # twiny: 上端に第2X軸目盛り
            $self->_draw_twin_xaxis($backend, $tr, $ml,$mt,$mr,$mb);
        } else {
            # twinx: 右端に第2Y軸目盛り
            $self->_draw_twin_yaxis($backend, $tr, $ml,$mt,$mr,$mb);
        }
    } else {


        my $has_plot = grep {
            $_->{type} =~ /^(line|scatter|bar|barh|hist|errorbar|
                              fill_between|step|stem|imshow|contourf|
                              pie|hline|vline|vspan|hspan|quiver|
                              boxplot_item|box_fliers|violin_item|
                              eventplot|annotate)$/x
        } @{ $self->_queue };
        my $has_content = $has_plot || $self->{_pgbox};

        warn sprintf("[DEBUG draw] title='%s' axis_off=%s has_plot=%s pgbox=%s has_content=%s queue_types=[%s]\n",
            $self->title, $self->{_axis_off}//'undef', $has_plot, $self->{_pgbox}//'undef', $has_content,
            join(',', map { $_->{type} } @{ $self->_queue }))
            if $ENV{PGC_DEBUG_LABELS};

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

    # ユーザ指定レンジ（または undef）を復元。次回 draw で autoscale を再解決させる。
    # ただし twin オブジェクト(twinx/twiny の戻り値)の場合はこの巻き戻しを
    # 行わない。twin は draw() の中で親から ymin/ymax(または xmin/xmax) を
    # コピーする設計であり、巻き戻すと draw() 完了後に呼び出し側が
    # $twin->ymin 等を読んだ際に undef が返ってしまう
    # (twinx/twiny の戻り値に対して直後に ymin/ymax を確認する、
    #  またはそれらの値を使って set_ylim 等を呼ぶようなコードが
    #  意図通り動かなくなる)。
    unless ($self->_is_twin) {
        $self->xmin($user_lim[0]); $self->xmax($user_lim[1]);
        $self->ymin($user_lim[2]); $self->ymax($user_lim[3]);
    }
    return $self;
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
        # marker: marker引数が指定されていれば各点にマーカーを描く
        if (defined $cmd->{marker}) {
            my $fill = $cmd->{fill} // 1;
            my $ms   = $cmd->{ms}   // 4;
            $b->set_linewidth(0.8);
            for my $i (0 .. $cmd->{x}->nelem - 1) {
                $b->marker($xd->at($i), $yd->at($i), $ms, $cmd->{marker}, $fill);
            }
            $b->set_linewidth(1.5);
        }
    }

    elsif ($type eq 'specgram') {
        my $spec   = $cmd->{spec};
        my $times  = $cmd->{times};
        my $freqs  = $cmd->{freqs};
        my $vmin   = $cmd->{vmin};
        my $vmax   = $cmd->{vmax};
        my $cmap   = $self->_resolve_cmap($cmd->{cmap});

        my $nframes = scalar @$times;
        my $nfreqs  = scalar @$freqs;

        # Draw each cell as a filled rectangle
        # Time runs left-right (x), Frequency runs bottom-top (y)
        for my $fi (0 .. $nframes - 1) {
            for my $fqi (0 .. $nfreqs - 1) {
                my $val = $spec->at($fqi, $fi);
                my $t   = ($vmax > $vmin)
                    ? ($val - $vmin) / ($vmax - $vmin) : 0.5;
                $t = 0 if $t < 0; $t = 1 if $t > 1;
                my @rgb = $cmap->rgb_at($t);
                $b->set_color(@rgb);

                # Pixel coordinates for this cell
                my $t0 = $times->[$fi];
                my $t1 = ($fi < $nframes - 1) ? $times->[$fi+1]
                       : $t0 + ($t0 - ($fi > 0 ? $times->[$fi-1] : $t0));
                my $f0 = $freqs->[$fqi];
                my $f1 = ($fqi < $nfreqs - 1) ? $freqs->[$fqi+1]
                       : $f0 + ($f0 - ($fqi > 0 ? $freqs->[$fqi-1] : $f0));

                my $px0 = $tr->x(pdl($t0))->at(0);
                my $px1 = $tr->x(pdl($t1))->at(0);
                my $py0 = $tr->y(pdl($f0))->at(0);
                my $py1 = $tr->y(pdl($f1))->at(0);

                # Ensure correct order (y increases downward in screen)
                my ($lx, $rx) = $px0 < $px1 ? ($px0,$px1) : ($px1,$px0);
                my ($ty, $by) = $py0 < $py1 ? ($py0,$py1) : ($py1,$py0);

                next if $rx < $ml || $lx > $mr;
                next if $by < $mt || $ty > $mb;

                $lx = $ml if $lx < $ml; $rx = $mr if $rx > $mr;
                $ty = $mt if $ty < $mt; $by = $mb if $by > $mb;

                $b->filled_rect($lx, $ty, $rx - $lx, $by - $ty);
            }
        }
    }

    elsif ($type eq 'hexbin') {
        my ($nx, $xmin, $xmax) = ($cmd->{gridsize},
            $self->xmin, $self->xmax);
        my ($ymin, $ymax) = ($self->ymin, $self->ymax);
        my $dx   = ($xmax - $xmin) / $nx;
        # hex geometry: width=dx, height=dx/cos(30deg) approx
        my $asp  = ($ymax - $ymin) / ($xmax - $xmin);
        my $ny   = int($nx * $asp * 0.8660) + 1;  # sqrt(3)/2
        my $dy   = ($ymax - $ymin) / $ny;

        # Count points per hexagon
        my %counts;
        my $xs = $cmd->{x};
        my $ys = $cmd->{y};
        for my $i (0 .. $xs->nelem - 1) {
            my ($xv, $yv) = ($xs->at($i), $ys->at($i));
            next if $xv < $xmin || $xv > $xmax;
            next if $yv < $ymin || $yv > $ymax;
            # offset rows for hex packing
            my $row  = int(($yv - $ymin) / $dy);
            my $xoff = ($row % 2) ? $dx * 0.5 : 0;
            my $col  = int(($xv - $xmin - $xoff) / $dx);
            $counts{"$row,$col"}++;
        }

        my $mincnt = $cmd->{mincnt};
        my @cnts   = grep { $_ >= $mincnt } values %counts;
        my $cmax   = $cmd->{vmax} // (@cnts ? do { my $m = $cnts[0]; for (@cnts) { $m = $_ if $_ > $m } $m } : 1);
        my $cmin   = $cmd->{vmin} // $mincnt;
        $self->_colorbar({ cmap => $self->_resolve_cmap($cmd->{cmap}),
                           vmin => $cmin, vmax => $cmax });

        my $cmap = $self->_resolve_cmap($cmd->{cmap});
        $b->set_alpha($cmd->{alpha});

        for my $key (keys %counts) {
            my $cnt = $counts{$key};
            next if $cnt < $mincnt;
            my ($row, $col) = split /,/, $key;
            my $xoff = ($row % 2) ? $dx * 0.5 : 0;
            my $cx   = $xmin + ($col + 0.5) * $dx + $xoff;
            my $cy   = $ymin + ($row + 0.5) * $dy;

            my $t    = ($cmax > $cmin) ? ($cnt - $cmin) / ($cmax - $cmin) : 1;
            $t = 0 if $t < 0; $t = 1 if $t > 1;
            my @col_rgb = $cmap->rgb_at($t);
            $b->set_color(@col_rgb);

            # Draw filled hexagon
            my $pxcx = $tr->x(pdl($cx))->at(0);
            my $pycy = $tr->y(pdl($cy))->at(0);
            my $rx   = abs($tr->x(pdl($cx + $dx*0.5))->at(0) - $pxcx);
            my $ry   = abs($tr->y(pdl($cy + $dy*0.5))->at(0) - $pycy);
            # 6 vertices of flat-top hexagon
            my @vx = map { $pxcx + $rx * cos($_ * 3.14159265/3) } 0..5;
            my @vy = map { $pycy + $ry * sin($_ * 3.14159265/3) } 0..5;
            $b->filled_polygon_xy(\@vx, \@vy);
        }
        $b->set_alpha(1.0);
    }

    elsif ($type eq 'scatter') {
        my $cmap  = defined($cmd->{cdata})
            ? $self->_resolve_cmap($cmd->{cmap}) : undef;
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
            # matplotlib s = area in pt^2, radius = sqrt(s/pi)
            my $radius = sqrt($cmd->{size} / 3.14159265) || 1;
            my $fill = $cmd->{fill} // 1;
            $b->marker($xp, $yp, $radius, $cmd->{marker}, $fill);
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

            # yerr: バー上端(bottom+height)を中心に誤差バーを描く。
            # errorbar()と同じ Driver::Cairo::errorbar_y() を再利用する。
            if (defined $cmd->{yerr_lo} && defined $cmd->{yerr_hi}) {
                my $ylo_v = $cmd->{yerr_lo}->nelem > 1 ? $cmd->{yerr_lo}->at($i) : $cmd->{yerr_lo}->at(0);
                my $yhi_v = $cmd->{yerr_hi}->nelem > 1 ? $cmd->{yerr_hi}->at($i) : $cmd->{yerr_hi}->at(0);
                # データ座標でのバー上端
                my $bar_top_data = $bo + $h;
                # 画面座標に変換した、上端・下端それぞれの誤差バー先端位置
                my $cx_screen = $tr->x(pdl($xc))->at(0);
                my $y_top_screen = $tr->y(pdl($bar_top_data))->at(0);
                my $y_lo_screen  = $tr->y(pdl($bar_top_data - $ylo_v))->at(0);
                my $y_hi_screen  = $tr->y(pdl($bar_top_data + $yhi_v))->at(0);
                # errorbar_y は (xp, yp, ye_lo, ye_hi, capw) を画面座標の
                # オフセット(px)として受け取るため、ここでpx差分に変換する。
                my $ye_lo_px = $y_lo_screen - $y_top_screen;  # 下方向（正値）
                my $ye_hi_px = $y_top_screen - $y_hi_screen;  # 上方向（正値）
                $b->set_color(0,0,0);
                $b->set_linewidth(1.5);
                $b->errorbar_y($cx_screen, $y_top_screen, $ye_lo_px, $ye_hi_px, $cmd->{capsize});
            }
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
            my $fill = $cmd->{fill} // 1;
            $b->marker($xd->at($i), $yd->at($i), $cmd->{ms}, $cmd->{marker}, $fill);
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
        #  xerr  yerr 

        if (defined $cmd->{xerr}) {
            $b->set_linewidth(1.0);
            for my $i (0 .. $cmd->{x}->nelem - 1) {
                my $xe = $xd->at($i);
                my $ye = $yd->at($i);
                my $xn = $cmd->{x}->nelem;
                my $en = $cmd->{xerr}->nelem;
                my $elo = $en == 1          ? $cmd->{xerr}->at(0)
                        : $en == 2 * $xn    ? $cmd->{xerr}->at($i)
                        :                     $cmd->{xerr}->at($i);
                my $ehi = $en == 1          ? $cmd->{xerr}->at(0)
                        : $en == 2 * $xn    ? $cmd->{xerr}->at($xn + $i)
                        :                     $cmd->{xerr}->at($i);
                my $x_lo = $tr->x(pdl($cmd->{x}->at($i) - $elo))->at(0);
                my $x_hi = $tr->x(pdl($cmd->{x}->at($i) + $ehi))->at(0);
                $b->errorbar_x($xe, $ye,
                    $xe - $x_lo,   # lo in screen
                    $x_hi - $xe,   # hi in screen
                    $cmd->{capsize});
            }
        }
    }

    elsif ($type eq 'fill_between') {
        #  →  → polygon
        # mask が指定されている場合: 連続した True 区間ごとに polygon を分割して描く。
        # mask なし: 従来通り全区間を1つの polygon で描く。
        my $x  = $cmd->{x};
        my $y1 = $cmd->{y1};
        my $y2 = $cmd->{y2};
        $b->set_color(@{$cmd->{color}}, $cmd->{alpha});

        if (defined $cmd->{mask}) {
            my $mask = $cmd->{mask};
            $mask = pdl($mask) unless $mask->isa('PDL');
            my $n = $x->nelem;
            # 連続した True 区間を抽出して、それぞれ polygon を描く
            my $in_seg = 0;
            my (@seg_x, @seg_y1, @seg_y2);
            for my $i (0 .. $n-1) {
                if ($mask->at($i)) {
                    push @seg_x,  $x->at($i);
                    push @seg_y1, $y1->at($i);
                    push @seg_y2, $y2->at($i);
                    $in_seg = 1;
                } else {
                    if ($in_seg && @seg_x) {
                        my $xs  = pdl(@seg_x);
                        my $ys1 = pdl(@seg_y1);
                        my $ys2 = pdl(@seg_y2);
                        my $xf  = $xs->append($xs->slice("-1:0:-1"));
                        my $yf  = $ys1->append($ys2->slice("-1:0:-1"));
                        $b->filled_polygon($tr->x($xf), $tr->y($yf));
                        @seg_x = @seg_y1 = @seg_y2 = ();
                    }
                    $in_seg = 0;
                }
            }
            # 末尾まで True だった区間
            if ($in_seg && @seg_x) {
                my $xs  = pdl(@seg_x);
                my $ys1 = pdl(@seg_y1);
                my $ys2 = pdl(@seg_y2);
                my $xf  = $xs->append($xs->slice("-1:0:-1"));
                my $yf  = $ys1->append($ys2->slice("-1:0:-1"));
                $b->filled_polygon($tr->x($xf), $tr->y($yf));
            }
        } else {
            # mask なし: 従来通り
            my $n  = $x->nelem;
            my $xf = $x->append($x->slice("-1:0:-1"));
            my $yf = $y1->append($y2->slice("-1:0:-1"));
            my $xd = $tr->x($xf);
            my $yd = $tr->y($yf);
            $b->filled_polygon($xd, $yd);
        }
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
        # 複数行対応: "a\nb" は _text_ml が行分割・行送り・valign 縦センタリング
        # まで面倒を見る。単一行はそのまま backend text() に素通し(後方互換)。
        $self->_text_ml($b, $xd, $yd, $cmd->{str},
            align        => $cmd->{align},
            valign       => $cmd->{valign},
            angle        => $cmd->{angle},
            size         => $cmd->{size},
            line_spacing => $cmd->{line_spacing});
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

        # テキストと矢印の重なりを避けるため、テキストの少し外側
        # (xy から離れる方向) にマージンを置き、矢印はそこから始める。
        # 矢印の先端側も xy にぴったり着けず、矢じり分だけ手前で止める。
        my $dx_full = $axp - $txp;
        my $dy_full = $ayp - $typ;
        my $dist    = sqrt($dx_full**2 + $dy_full**2) || 1;
        my $ux      = $dx_full / $dist;
        my $uy      = $dy_full / $dist;

        my $text_gap  = 6;    # テキスト基準点と矢印開始点の隙間(px)
        my $arrow_gap = 10;   # 矢印先端とデータ点の隙間(px、矢じり分)

        my $arrow_start_x = $txp + $ux * $text_gap;
        my $arrow_start_y = $typ + $uy * $text_gap;
        my $arrow_end_x   = $axp - $ux * $arrow_gap;
        my $arrow_end_y   = $ayp - $uy * $arrow_gap;

        #

        if ($cmd->{arrow}) {
            $b->set_color(@{$cmd->{color}});
            $b->set_linewidth(1.0);
            $b->line_seg($arrow_start_x, $arrow_start_y, $arrow_end_x, $arrow_end_y);
            #

            my $pi  = 3.14159265358979;
            my $ang = atan2($arrow_end_y - $arrow_start_y, $arrow_end_x - $arrow_start_x);
            my $hs  = 8;
            my $ha  = 0.4;
            my @hx  = ($arrow_end_x,
                        $arrow_end_x - $hs*cos($ang-$ha),
                        $arrow_end_x - $hs*cos($ang+$ha));
            my @hy  = ($arrow_end_y,
                        $arrow_end_y - $hs*sin($ang-$ha),
                        $arrow_end_y - $hs*sin($ang+$ha));
            $b->set_color(@{$cmd->{color}});
            $b->filled_polygon(pdl(@hx), pdl(@hy));
        }

        #

        $b->set_color(@{$cmd->{color}});
        $b->set_font(size => $cmd->{size});
        $b->text($txp, $typ, $cmd->{text}, align=>'left', valign=>'bottom');
    }

    elsif ($type eq 'contour') {
        my @xs      = list($cmd->{x});
        my @ys      = list($cmd->{y});
        my $z       = $cmd->{z};
        my $nr      = scalar @ys;
        my $nc      = scalar @xs;
        my @levels  = @{ $cmd->{levels} };
        my $colors  = $cmd->{colors};
        my $lws     = $cmd->{linewidths};
        my $lss     = $cmd->{linestyles};

        for my $li (0 .. $#levels) {
            my $level = $levels[$li];

            my @lc;
            if (ref($colors) eq 'ARRAY') {
                @lc = @{ $self->_parse_color($colors->[$li % scalar(@$colors)]) };
            } else {
                @lc = @{ $self->_parse_color($colors) };
            }
            my $lw = ref($lws) eq 'ARRAY' ? $lws->[$li % scalar(@$lws)] : $lws;
            my $ls = ref($lss) eq 'ARRAY' ? $lss->[$li % scalar(@$lss)] : $lss;

            $b->set_color(@lc, $cmd->{alpha});
            $b->set_linewidth($lw);
            $b->set_linestyle($ls);

            for my $r (0 .. $nr - 2) {
                for my $c (0 .. $nc - 2) {
                    my $v00 = $z->at($r,   $c);
                    my $v01 = $z->at($r,   $c+1);
                    my $v10 = $z->at($r+1, $c);
                    my $v11 = $z->at($r+1, $c+1);

                    my $case = (($v00 >= $level) ? 8 : 0)
                             | (($v01 >= $level) ? 4 : 0)
                             | (($v11 >= $level) ? 2 : 0)
                             | (($v10 >= $level) ? 1 : 0);
                    next if $case == 0 || $case == 15;

                    my $x0d = $xs[$c];   my $x1d = $xs[$c+1];
                    my $y0d = $ys[$r];   my $y1d = $ys[$r+1];

                    # Linear interp on each edge
                    # A=bottom(y0) B=right(x1) C=top(y1) D=left(x0)
                    my $tA = ($v01!=$v00) ? ($level-$v00)/($v01-$v00) : 0.5;
                    my ($xA,$yA) = ($x0d+$tA*($x1d-$x0d), $y0d);
                    my $tB = ($v11!=$v01) ? ($level-$v01)/($v11-$v01) : 0.5;
                    my ($xB,$yB) = ($x1d, $y0d+$tB*($y1d-$y0d));
                    my $tC = ($v11!=$v10) ? ($level-$v10)/($v11-$v10) : 0.5;
                    my ($xC,$yC) = ($x0d+$tC*($x1d-$x0d), $y1d);
                    my $tD = ($v10!=$v00) ? ($level-$v00)/($v10-$v00) : 0.5;
                    my ($xD,$yD) = ($x0d, $y0d+$tD*($y1d-$y0d));

                    my ($pxA,$pyA) = ($tr->x(pdl($xA))->at(0), $tr->y(pdl($yA))->at(0));
                    my ($pxB,$pyB) = ($tr->x(pdl($xB))->at(0), $tr->y(pdl($yB))->at(0));
                    my ($pxC,$pyC) = ($tr->x(pdl($xC))->at(0), $tr->y(pdl($yC))->at(0));
                    my ($pxD,$pyD) = ($tr->x(pdl($xD))->at(0), $tr->y(pdl($yD))->at(0));

                    # Marching Squares line segments
                    # bits: 8=BL(v00) 4=BR(v01) 2=TR(v11) 1=TL(v10)
                    if    ($case==1||$case==14) { $b->line_seg($pxC,$pyC,$pxD,$pyD) }
                    elsif ($case==2||$case==13) { $b->line_seg($pxB,$pyB,$pxC,$pyC) }
                    elsif ($case==3||$case==12) { $b->line_seg($pxB,$pyB,$pxD,$pyD) }
                    elsif ($case==4||$case==11) { $b->line_seg($pxA,$pyA,$pxB,$pyB) }
                    elsif ($case==5           ) { $b->line_seg($pxA,$pyA,$pxB,$pyB);
                                                  $b->line_seg($pxC,$pyC,$pxD,$pyD) }
                    elsif ($case==6||$case==9 ) { $b->line_seg($pxA,$pyA,$pxC,$pyC) }
                    elsif ($case==7||$case==8 ) { $b->line_seg($pxA,$pyA,$pxD,$pyD) }
                    elsif ($case==10          ) { $b->line_seg($pxA,$pyA,$pxB,$pyB);
                                                  $b->line_seg($pxC,$pyC,$pxD,$pyD) }
                }
            }
        }
        $b->set_linestyle('solid');
        $b->set_linewidth(1.5);
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

    elsif ($type eq 'pcolormesh') {
        # 不均一グリッドの疑似カラー表示。$x/$y はセル境界座標(1次元)、
        # $z は各セルの値。contourf と異なり頂点の補間は行わず、
        # セルごとの単一値をそのまま塗る(matplotlib pcolormesh と同じ
        # 挙動)。
        my @xs = list($cmd->{x});
        my @ys = list($cmd->{y});
        my $z  = $cmd->{z};
        my $vmin = $cmd->{vmin};
        my $vmax = $cmd->{vmax};

        my $nx_edges = scalar @xs;
        my $ny_edges = scalar @ys;
        my $n_cols   = $nx_edges - 1;  # セル数(X方向)
        my $n_rows   = $ny_edges - 1;  # セル数(Y方向)

        # PDLのdims()は[列,行]の順(列優先)を返す。$zの形状チェック自体は
        # 行わず、$z->at($r,$c)が範囲外ならPDL自体がエラーを出すため、
        # 形状不一致は自然に検出される。

        # 利便性のため、$z が (n_rows, n_cols) のセル値そのものでも
        # (ny_edges, nx_edges) の境界点と同じ形状(imshow/contourf流の
        # 簡易指定)でも受け付ける。後者の場合、$z->at($r,$c) は
        # (0..n_rows-1, 0..n_cols-1) の範囲でアクセスすれば自然に
        # 先頭の(n_rows, n_cols)個だけを使うことになり、最後の行・列
        # (本来は使われない余剰データ)を無視した形になる。

        for my $r (0 .. $n_rows - 1) {
            for my $c (0 .. $n_cols - 1) {
                my $v = $z->at($r, $c);
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
# ------------------------------------------------------------------
# _draw_twin_xaxis — twiny 用: 上端に第2X軸目盛りを描画
# ------------------------------------------------------------------
sub _draw_twin_xaxis {
    my ($self, $b, $tr, $ml,$mt,$mr,$mb) = @_;

    warn sprintf("[DEBUG _draw_twin_xaxis] mt=%s xlabel='%s'\n",
        $mt, $self->xlabel) if $ENV{PGC_DEBUG_LABELS};

    $b->set_color(0,0,0);
    $b->set_linewidth(1.0);
    $b->set_linestyle('solid');

    # 上端ライン
    $b->line_seg($ml, $mt, $mr, $mt);

    # X 目盛り計算
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

    $b->set_font(size => 10);
    my $prev_xp_right = -9999;  # 直前に描いたラベルの右端(px)
    for my $i (0 .. $#xtks) {
        my $v   = $xtks[$i];
        my $eps = ($self->xmax - $self->xmin) * 0.001 + 0.001;
        next if $v < $self->xmin - $eps || $v > $self->xmax + $eps;
        my $xp = $tr->x(pdl($v))->at(0);
        next if $xp < $ml - 1 || $xp > $mr + 1;

        # ラベル幅に基づく重なり判定。 [PGC10-ROUND3-XTICK-FIX]
        # 固定24px間隔ではなく、実際の文字列幅(text_width)から
        # 「中心からの半幅+左右余白」を計算し、直前ラベルの右端と
        # 比較する。log軸では桁が増えるほど文字数が増える
        # (例: "100000" は "1" より明らかに幅が広い) ため、
        # 固定幅判定だと長いラベルが重なって判読不能になる。
        my $label_w   = eval { $b->text_width($xlbs[$i]) } // 16;
        my $half_w    = $label_w / 2;
        my $label_pad = 4;   # ラベル間の最小余白(px)
        my $xp_left   = $xp - $half_w;
        next if $xp_left < $prev_xp_right + $label_pad;

        # 上向き tick (mt から外側へ)
        $b->line_seg($xp, $mt, $xp, $mt - 4);
        $b->set_color(_fg());
        $b->text($xp, $mt - 6, $xlbs[$i], align=>'center', valign=>'bottom');
        $prev_xp_right = $xp + $half_w;
    }

    # 上X軸ラベル
    if ($self->xlabel ne '') {
        $b->set_font(size => 11);
        $b->text(($ml+$mr)/2, $mt - 28, $self->xlabel,
            align=>'center', valign=>'bottom');
    }
}

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
    my @ylbs;
    if ($self->_yticklabels) {
        @ylbs = @{ $self->_yticklabels };
    } elsif ($self->_yformatter) {
        my $fmt = $self->_yformatter;
        @ylbs = map { $fmt->($ytks[$_], $_) } 0..$#ytks;
    } elsif ($self->yscale eq 'log') {
        my $sc = PDL::Graphics::Cairo::Scale::Log->new;
        @ylbs = map { $sc->fmt_tick($_) } @ytks;
    } else {
        @ylbs = map { _fmt_tick($_) } @ytks;
    }

    my $min_ygap = 14;
    my ($ylo, $yhi) = ($self->ymin, $self->ymax);
    my $prev_yp = $self->{_y_reversed} ? -9999 : 9999;
    $b->set_font(size => 10);
    for my $i (0 .. $#ytks) {
        my $v   = $ytks[$i];
        my $eps = ($yhi - $ylo) * 0.001 + 0.001;
        next if $v < $ylo - $eps || $v > $yhi + $eps;
        my $yp = $tr->y(pdl($v))->at(0);
        next if $yp < $mt - 1 || $yp > $mb + 1;

        $b->set_color(_fg());
        $b->line_seg($mr, $yp, $mr+4, $yp);

        # label overlap guard (same logic as _draw_frame Y section)
        # abs() で正順・逆順どちらの yticks 配列にも対応
        next if abs($yp - $prev_yp) < $min_ygap;
        $b->text($mr+6, $yp, $ylbs[$i], align=>'left', valign=>'middle');
        $prev_yp = $yp;
    }

    # Y
    # angle=>90(正)を使う。-90だと文字が上から下に読む向きになり、
    # 通常のylabel(_draw_labels内、angle=>$rot、デフォルト90)と
    # 反転して見えてしまう(ユーザー指摘により発覚)。
    if ($self->ylabel ne '') {
        $b->set_font(size => 11);
        $b->text($mr + 42, ($mt+$mb)/2, $self->ylabel,
            align=>'center', valign=>'bottom', angle=>90);
    }
    if (exists $self->{_right_ylabel} && $self->{_right_ylabel} ne '') {
        $b->set_font(size => 11);
        $b->text($mr + 20, ($mt+$mb)/2, $self->{_right_ylabel},
            align=>'center', valign=>'bottom', angle=>90);
    }
}

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
sub _draw_frame {
    my ($self, $b, $tr, $ml,$mt,$mr,$mb) = @_;

    # セルが極端に小さくなったとき mt>=mb / ml>=mr になり Cairo が壊れた矩形を
    # 描いて全面塗りつぶし（"真っ青"等）になるのを防ぐ
    return if $mt >= $mb - 4 || $ml >= $mr - 4;

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
    my $date_step;  # 日付軸の場合のみ使用(fmt_date_tickに渡す目盛り間隔)
    if ($self->_xticks) {
        @xtks = @{ $self->_xticks };
    } elsif ($self->_xaxis_is_date) {
        @xtks = nice_date_ticks($self->xmin, $self->xmax, 6);
        $date_step = (@xtks >= 2) ? ($xtks[1] - $xtks[0]) : 86400;
    } elsif ($self->xscale eq 'log') {
        my $sc = PDL::Graphics::Cairo::Scale::Log->new;
        @xtks = $sc->nice_ticks($self->xmin, $self->xmax);
    } else {
        @xtks = nice_ticks($self->xmin, $self->xmax, 6);
    }
    my @xlbs;
    if ($self->_xticklabels) {
        @xlbs = @{ $self->_xticklabels };
    } elsif ($self->_xformatter) {
        my $fmt = $self->_xformatter;
        @xlbs = map { $fmt->($xtks[$_], $_) } 0..$#xtks;
    } elsif ($self->_xaxis_is_date) {
        @xlbs = map { fmt_date_tick($_, $date_step) } @xtks;
    } elsif ($self->xscale eq 'log') {
        my $sc = PDL::Graphics::Cairo::Scale::Log->new;
        @xlbs = map { $sc->fmt_tick($_) } @xtks;
    } else {
        @xlbs = map { _fmt_tick($_) } @xtks;
    }

    my ($xlo, $xhi) = ($self->xmin, $self->xmax);
    my $prev_xp_right = -9999;  # 直前に描いたラベルの右端(px)。固定24px間隔ではなく
                                 # 実測文字幅に基づく重なり判定に使う（下記参照）。

    for my $i (0 .. $#xtks) {
        my $v    = $xtks[$i];
        my $xeps = ($self->xmax - $self->xmin) * 0.001 + 0.001;
        next if $v < $self->xmin - $xeps || $v > $self->xmax + $xeps;
        my $xp = $tr->x(pdl($v))->at(0);
        next if $xp < $ml - 1 || $xp > $mr + 1;

        # ラベル幅に基づく重なり判定。
        # 固定24px間隔ではなく、実際の文字列幅(text_width)から
        # 「中心からの半幅+左右余白」を計算し、直前ラベルの右端と比較する。
        # log軸では桁が増えるほど文字数が増える(例:"100000"は"1"より明らかに
        # 幅が広い)ため、固定幅判定だと長いラベルが重なって判読不能になる。
        my $label_w   = eval { $b->text_width($xlbs[$i]) } // 16;
        my $half_w    = $label_w / 2;
        my $label_pad = 4;   # ラベル間の最小余白(px)
        my $xp_left   = $xp - $half_w;
        my $overlaps  = $xp_left < $prev_xp_right + $label_pad;

        # T/S: ticks  y=0
        if ($xopt =~ /[TS]/) {
            my $tp     = $self->_tick_params;
            my $tlen   = $tp->{x_length}    // (($xopt =~ /T/) ? 5 : 3);
            my $twid   = $tp->{x_width}     // 1.0;
            my $tdir   = $tp->{x_direction} // 'out';
            my $show_b = $tp->{x_bottom}    // 1;
            my $show_t = $tp->{x_top}       // 0;
            my @tc     = defined($tp->{x_color})
                ? @{ $self->_parse_color($tp->{x_color}) }
                : @fc;
            $b->set_color(@tc);
            $b->set_linewidth($twid);
            my $ya = ($y0p >= $mt && $y0p <= $mb) ? $y0p : $mb;
            if ($show_b) {
                my ($y1,$y2) = $tdir eq 'in'    ? ($ya, $ya - $tlen)
                             : $tdir eq 'inout'  ? ($ya - $tlen/2, $ya + $tlen/2)
                             :                     ($ya, $ya + $tlen);
                $b->line_seg($xp, $y1, $xp, $y2);
            }
            if ($show_t) {
                my $yt = $mt;
                my ($y1,$y2) = $tdir eq 'in'    ? ($yt, $yt + $tlen)
                             : $tdir eq 'inout'  ? ($yt - $tlen/2, $yt + $tlen/2)
                             :                     ($yt, $yt - $tlen);
                $b->line_seg($xp, $y1, $xp, $y2);
            }
            $b->set_linewidth(1.5);
        }

        # N: (mb)
        next if $overlaps;
        if ($xopt =~ /N/) {
            my $tp       = $self->_tick_params;
            my $lsize    = $tp->{x_labelsize}     // 10;
            my $lshow    = $tp->{x_labelbottom}   // 1;
            my $lshow_t  = $tp->{x_labeltop}      // 0;
            # pad: 目盛り線の先端からラベルまでの隙間(px)。
            # matplotlibのデフォルト(xtick.major.pad=3.5pt≈4-5px)相当に
            # 合わせる。以前は16→10だったが、Driver::Cairo::text()の
            # valign='top'実装バグ(2026-06-19修正)により、修正前は
            # ラベルが意図せず上にせり出して詰まって見えていた。
            # バグ修正後は計算式通りの位置に描かれるようになったため、
            # 同じ見た目の隙間を保つには pad 自体を縮める必要がある。
            my $pad      = $tp->{x_pad}           // 4;
            my $rot      = $tp->{x_labelrotation} // $self->{_xtick_rot} // 0;
            my @lc       = defined($tp->{x_labelcolor})
                ? @{ $self->_parse_color($tp->{x_labelcolor}) }
                : @fc;
            my $tlen_eff = $tp->{x_length} // (($xopt =~ /T/) ? 5 : 3);
            my $tdir     = $tp->{x_direction} // 'out';
            my $tick_ext = $tdir eq 'out' ? $tlen_eff
                         : $tdir eq 'inout' ? $tlen_eff/2 : 0;
            if ($lshow) {
                $b->set_color(@lc);
                $b->set_font(size => $lsize);
                $self->_text_ml($b, $xp, $mb + $tick_ext + $pad + 2, $xlbs[$i],
                    align=>'center', valign=>'top', angle=>$rot, size=>$lsize);
            }
            if ($lshow_t) {
                $b->set_color(@lc);
                $b->set_font(size => $lsize);
                $self->_text_ml($b, $xp, $mt - $tick_ext - $pad - 2, $xlbs[$i],
                    align=>'center', valign=>'bottom', angle=>$rot, size=>$lsize);
            }
        }
        $prev_xp_right = $xp + $half_w;
    }

    # ============================================================
    # X minor ticks
    # ============================================================
    if ($self->_minor_ticks_on && $xopt =~ /[TS]/) {
        my $tp     = $self->_tick_params;
        my $tdir   = $tp->{x_direction}    // 'out';
        my $show_b = $tp->{x_bottom}        // 1;
        my $show_t = $tp->{x_top}            // 0;
        my @tc     = defined($tp->{x_color})
            ? @{ $self->_parse_color($tp->{x_color}) } : @fc;
        my $tlen   = $tp->{x_minor_length}
                  // ($tp->{x_length} ? $tp->{x_length} * 0.5 : 2);
        my $twid   = $tp->{x_minor_width}
                  // ($tp->{x_width}  ? $tp->{x_width}  * 0.6 : 0.6);
        my @xminors;

        if ($self->xscale eq 'log') {
            my $lo = POSIX::floor(log(($xlo > 0 ? $xlo : 1e-10))/log(10));
            my $hi = POSIX::floor(log($xhi > 0 ? $xhi : 1)/log(10)) + 1;
            for my $e ($lo .. $hi) {
                for my $m (2..9) {
                    my $v = $m * (10 ** $e);
                    push @xminors, $v
                        if $v > $xlo * 1.001 && $v < $xhi * 0.999;
                }
            }
        } else {
            @xminors = minor_ticks($xlo, $xhi, $self->_minor_n, @xtks);
        }

        $b->set_linewidth($twid);
        $b->set_color(@tc);
        for my $v (@xminors) {
            my $xp = $tr->x(pdl($v))->at(0);
            next if $xp < $ml || $xp > $mr;
            my $ya = ($y0p >= $mt && $y0p <= $mb) ? $y0p : $mb;
            if ($show_b) {
                my ($y1,$y2) = $tdir eq 'in'   ? ($ya, $ya - $tlen)
                             : $tdir eq 'inout' ? ($ya - $tlen/2, $ya + $tlen/2)
                             :                    ($ya, $ya + $tlen);
                $b->line_seg($xp, $y1, $xp, $y2);
            }
            if ($show_t) {
                my $yt = $mt;
                my ($y1,$y2) = $tdir eq 'in'   ? ($yt, $yt + $tlen)
                             : $tdir eq 'inout' ? ($yt - $tlen/2, $yt + $tlen/2)
                             :                    ($yt, $yt - $tlen);
                $b->line_seg($xp, $y1, $xp, $y2);
            }
        }
        $b->set_linewidth(1.5);
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

        # T/S: ticks  x=0
        if ($yopt =~ /[TS]/) {
            my $tp     = $self->_tick_params;
            my $tlen   = $tp->{y_length}    // (($yopt =~ /T/) ? 5 : 3);
            my $twid   = $tp->{y_width}     // 1.0;
            my $tdir   = $tp->{y_direction} // 'out';
            my $show_l = $tp->{y_left}      // 1;
            my $show_r = $tp->{y_right}     // 0;
            my @tc     = defined($tp->{y_color})
                ? @{ $self->_parse_color($tp->{y_color}) }
                : @fc;
            $b->set_color(@tc);
            $b->set_linewidth($twid);
            my $xa = ($x0p >= $ml && $x0p <= $mr) ? $x0p : $ml;
            if ($show_l) {
                my ($x1,$x2) = $tdir eq 'in'    ? ($xa, $xa + $tlen)
                             : $tdir eq 'inout'  ? ($xa - $tlen/2, $xa + $tlen/2)
                             :                     ($xa, $xa - $tlen);
                $b->line_seg($x1, $yp, $x2, $yp);
            }
            if ($show_r) {
                my $xr = $mr;
                my ($x1,$x2) = $tdir eq 'in'    ? ($xr, $xr - $tlen)
                             : $tdir eq 'inout'  ? ($xr - $tlen/2, $xr + $tlen/2)
                             :                     ($xr, $xr + $tlen);
                $b->line_seg($x1, $yp, $x2, $yp);
            }
            $b->set_linewidth(1.5);
        }

        # N: (ml)
        # abs() で正順・逆順どちらの yticks 配列にも対応
        next if abs($yp - $prev_yp) < $min_ygap;
        if ($yopt =~ /N/) {
            my $tp      = $self->_tick_params;
            my $lsize   = $tp->{y_labelsize}     // 10;
            my $lshow_l = $tp->{y_labelleft}     // 1;
            my $lshow_r = $tp->{y_labelright}    // 0;
            my $pad     = $tp->{y_pad}           // 10;
            my $rot     = $tp->{y_labelrotation} // $self->{_ytick_rot} // 0;
            my @lc      = defined($tp->{y_labelcolor})
                ? @{ $self->_parse_color($tp->{y_labelcolor}) }
                : @fc;
            my $tlen_eff = $tp->{y_length} // (($yopt =~ /T/) ? 5 : 3);
            my $tdir     = $tp->{y_direction} // 'out';
            my $tick_ext = $tdir eq 'out' ? $tlen_eff
                         : $tdir eq 'inout' ? $tlen_eff/2 : 0;
            my $txt_y    = $yp;
            if ($lshow_l) {
                $b->set_color(@lc);
                $b->set_font(size => $lsize);
                $self->_text_ml($b, $ml - $tick_ext - $pad - 2, $txt_y, $ylbs[$i],
                    align=>'right', valign=>'middle', angle=>$rot, size=>$lsize);
                # ylabel 配置時の重なり防止用に、回転なしラベルの最大幅を記録する。
                # 複数行 ("name\n(scale)") では最長行の幅を採る (_text_width_ml)。
                # rot!=0（縦書き等）の場合は左方向の占有幅が変わるため対象外とする。
                if ($rot == 0) {
                    my $w = $self->_text_width_ml($b, $ylbs[$i]);
                    $self->{_y_ticklabel_maxw} = $w
                        if !defined($self->{_y_ticklabel_maxw})
                        || $w > $self->{_y_ticklabel_maxw};
                }
            }
            if ($lshow_r) {
                $b->set_color(@lc);
                $b->set_font(size => $lsize);
                $self->_text_ml($b, $mr + $tick_ext + $pad + 2, $txt_y, $ylbs[$i],
                    align=>'left', valign=>'middle', angle=>$rot, size=>$lsize);
            }
        }
        $prev_yp = $yp;
    }
    # ============================================================
    # Y minor ticks
    # ============================================================
    if ($self->_minor_ticks_on && $yopt =~ /[TS]/) {
        my $tp     = $self->_tick_params;
        my $tdir   = $tp->{y_direction}   // 'out';
        my $show_l = $tp->{y_left}         // 1;
        my $show_r = $tp->{y_right}         // 0;
        my @tc     = defined($tp->{y_color})
            ? @{ $self->_parse_color($tp->{y_color}) } : @fc;
        my $tlen   = $tp->{y_minor_length}
                  // ($tp->{y_length} ? $tp->{y_length} * 0.5 : 2);
        my $twid   = $tp->{y_minor_width}
                  // ($tp->{y_width}  ? $tp->{y_width}  * 0.6 : 0.6);
        my @yminors;

        if ($self->yscale eq 'log') {

            my $lo = POSIX::floor(log(($ylo > 0 ? $ylo : 1e-10))/log(10));
            my $hi = POSIX::floor(log( $yhi > 0 ? $yhi : 1  )/log(10)) + 1;

            for my $e ($lo .. $hi) {
                for my $m (2..9) {
                    my $v = $m * (10 ** $e);
                    push @yminors, $v
                        if $v > $ylo * 1.001 && $v < $yhi * 0.999;
                }
            }



        } else {
            @yminors = minor_ticks($self->ymin, $self->ymax, $self->_minor_n, @ytks);
        }
        $b->set_linewidth($twid);
        $b->set_color(@tc);
        for my $v (@yminors) {
            my $yp = $tr->y(pdl($v))->at(0);
            next if $yp < $mt || $yp > $mb;
            my $xa = ($x0p >= $ml && $x0p <= $mr) ? $x0p : $ml;
            if ($show_l) {
                my ($x1,$x2) = $tdir eq 'in'   ? ($xa, $xa + $tlen)
                             : $tdir eq 'inout' ? ($xa - $tlen/2, $xa + $tlen/2)
                             :                    ($xa, $xa - $tlen);
                $b->line_seg($x1, $yp, $x2, $yp);
            }
            if ($show_r) {
                my $xr = $mr;
                my ($x1,$x2) = $tdir eq 'in'   ? ($xr, $xr - $tlen)
                             : $tdir eq 'inout' ? ($xr - $tlen/2, $xr + $tlen/2)
                             :                    ($xr, $xr + $tlen);
                $b->line_seg($x1, $yp, $x2, $yp);
            }
        }
        $b->set_linewidth(1.5);
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

    warn sprintf("[DEBUG _draw_labels] title='%s' xlabel='%s' compact=%s mt=%s mb=%s ml=%s mr=%s\n",
        $self->title, $self->xlabel, $self->_compact_labels // 'undef', $mt, $mb, $ml, $mr)
        if $ENV{PGC_DEBUG_LABELS};

    # PGPLOT互換層は背景色(_PDLCAIRO_PGBG、デフォルトwhite)を
    # 黒に設定できる(cpgopenの bg=>'black' 等)。その場合、軸線や
    # 数値ラベルは _ci_to_rgb 経由で白に切り替わるが、title/xlabel/ylabel
    # はこれまで固定で黒(0,0,0)に描いていたため、黒背景時に文字が
    # 完全に見えなくなっていた(背景=文字色で同化)。
    # ここでも同じ背景判定を使い、黒背景なら白、それ以外は黒で描く。
    my $bg_black = (lc($ENV{_PDLCAIRO_PGBG} // 'white') eq 'black');
    my @label_fg = $bg_black ? (1,1,1) : (0,0,0);

    $b->set_color(@label_fg);

    # _compact_labels: 0=通常(単一figure), 1=compact(matplotlib風tight_layout
    # のuniform_margins), 2=pgplot(PGPLOT互換層、mb/mt自体が約半分の固定値
    # しかないため、compactよりさらに詰めたオフセット/フォントが必要)。
    my $level = $self->_compact_labels || 0;

    #

    if ($self->title ne '') {
        # level1: フォント13pt→11pt、オフセット-14→-11px。
        # level2(pgplot): フォント13pt→9pt、オフセット-14→-8px。
        my $fsize = $level == 2 ? 9  : $level == 1 ? 11 : 13;
        my $toff  = $level == 2 ? 8  : $level == 1 ? 11 : 14;
        # colorbar_location=>'top' の場合、mt自体がcolorbar用に拡張
        # されており、colorbar本体は mt-pad-cw 付近に描かれる。titleを
        # 通常の mt-toff のままにすると、colorbarの帯に埋もれて見えなく
        # なるため、colorbarの外側（さらに上）にtitleを配置する。
        my $title_y = $mt - $toff;
        if ($self->_colorbar && ($self->colorbar_location // '') eq 'top') {
            my $cb_pad = $self->colorbar_pad;
            my $cb_w   = $self->colorbar_width;
            my $cb_has_label = ($self->colorbar_label // '') ne '';
            # colorbar本体の上端(外側)は mt-pad-cw。さらにlabelがあれば
            # その分(横書きで上方向に約16px)も避ける必要がある。
            # _draw_colorbar側の cb_label_y 計算
            # (top配置: label_y(=cy-14) - 16 = cy-30 = mt-pad-cw-30)
            # と正確に対応させ、さらにtitle用のフォント分の余白(18px)を
            # 追加で確保する。
            my $cb_outer = $mt - $cb_pad - $cb_w - ($cb_has_label ? 30 + 18 : 0);
            $title_y = $cb_outer - $toff;
        }
        elsif (my @twins = grep { ($_->_twin_type // '') eq 'y' } @{ $self->_twin_axes }) {
            # twiny() が呼ばれている場合、上に第2X軸の目盛り・ラベルが
            # 描かれる(_draw_twin_xaxis)。titleをその外側(さらに上)に
            # 配置しないと、第2X軸のラベルとtitleが重なってしまう。
            # _twin_axes には twinx()/twiny() 両方のtwinが入りうるため、
            # twin_type='y'(twiny)のものだけを抜き出す。
            my $twin = $twins[0];
            # _draw_twin_xaxis の描画位置: 上向きtick(mt-4) +
            # 数値ラベル(mt-6から上、フォント10pt相当で約12px) +
            # xlabelがあれば追加で mt-28 から上にフォント11pt分。
            my $twin_outer = ($twin->xlabel ne '') ? ($mt - 28 - 14) : ($mt - 18);
            $title_y = $twin_outer - $toff;
            warn sprintf("[DEBUG title twiny] mt=%s twin_outer=%s title_y=%s\n",
                $mt, $twin_outer, $title_y) if $ENV{PGC_DEBUG_LABELS};
        }
        $b->set_font(size => $fsize, weight => 'bold');
        $b->text(($ml+$mr)/2, $title_y, $self->title,
            align=>'center', valign=>'bottom');
    }

    # X 
    # twiny() が作った twin オブジェクト(_is_twin かつ _twin_type='y')の
    # xlabel は、_draw_twin_xaxis() がすでに上端の専用位置に描画して
    # いるため、ここで通常の下軸ラベル位置(mb+xoff)に重複して描かない
    # ようにする。以前はこのガードが無く、上軸ラベルと下軸ラベルの
    # テキストが同じ場所(下)に二重描画されて重なって見える不具合が
    # あった。
    if ($self->xlabel ne '' && !($self->_is_twin && ($self->_twin_type // '') eq 'y')) {
        # level1: フォント11pt→9pt、オフセット+40→+38px。
        # level2(pgplot): フォント11pt→8pt、PGPLOTのmb(26px程度)に収まる
        # よう数値ラベル直下にぴったり詰めたオフセット+22pxを使う。
        my $fsize = $level == 2 ? 8  : $level == 1 ? 9  : 11;
        my $xoff  = $level == 2 ? 23 : $level == 1 ? 38 : 40;
        $b->set_font(size => $fsize);
        $b->text(($ml+$mr)/2, $mb + $xoff, $self->xlabel,
            align=>'center', valign=>'top');
    }

    # Y ラベル（ylabel_rotation=90で縦書き、0で横書き）
    # twinx() が作った twin オブジェクト(_is_twin かつ _twin_type が
    # 'y'以外、すなわちtwinx扱い)の ylabel は、_draw_twin_yaxis() が
    # すでに右端の専用位置に描画しているため、ここで通常の左軸ラベル
    # 位置(ml-gap)に重複して描かないようにする。xlabelで起きたのと
    # 同じ種類の二重描画バグで、左Y軸ラベルと右Y軸ラベルのテキストが
    # 同じ場所(左)に重なって見える不具合があった。
    if ($self->ylabel ne '' && !($self->_is_twin && ($self->_twin_type // '') ne 'y')) {
        # title/xlabelと同様、PGPLOT(level2)の極小margin_left(22-30px程度)
        # に合わせてフォント・gapを縮小する。以前はylabelだけlevel別調整が
        # 欠けていたため、PGPLOT経路でylabel('uV'等)がmargin_left範囲を
        # 超えてプロット枠の内側に描かれてしまっていた(枠内にラベルが
        # 侵入して見える不具合)。
        my $ysize = $level == 2 ? 8 : 11;
        $b->set_font(size => $ysize);
        my $rot = $self->ylabel_rotation // 90;
        # tick数値ラベルは $ml - tick_ext - pad - 2 を右端にして左へ伸びる。
        # その実測最大幅 (_y_ticklabel_maxw) より内側に ylabel が来ないよう
        # 固定オフセットへ動的なマージンを上乗せする。
        my $tick_w = $self->{_y_ticklabel_maxw} // 0;
        if ($rot == 0) {
            # 横書き: 枠左端から少し左、縦中央、右寄せ
            my $gap = $level == 2 ? (9 + $tick_w) : (8 + $tick_w);
            warn sprintf("[DEBUG ylabel] rot=0 ml=%s gap=%s text_x=%s text_y=%s\n",
                $ml, $gap, $ml-$gap, ($mt+$mb)/2) if $ENV{PGC_DEBUG_LABELS};
            $b->text($ml - $gap, ($mt+$mb)/2, $self->ylabel,
                align=>'right', valign=>'center', angle=>0);
        } else {
            # 縦書き（デフォルト動作を維持）
            # 縦書きテキストの幅は概ねフォントサイズ分(11px)なので
            # tick数値ラベル幅 + 余白(8px) + 縦書き文字幅(約14px) を確保する。
            # level2: 数値ラベル自体(pad6+tick_ext3+2=11px)+その文字幅
            # (8pt数値2-3文字≈6px)+ylabel文字幅(8pt≈10px)+安全余白(2px)
            # ≈ 19px。以前の14pxでは数値ラベルとylabelの文字が重なって
            # 見える(差がわずか3pxしかなかった)不具合があったため調整。
            my $gap = $level == 2 ? (19 + $tick_w) : (14 + 8 + $tick_w);
            warn sprintf("[DEBUG ylabel] rot=%s ml=%s gap=%s tick_w=%s text_x=%s text_y=%s\n",
                $rot, $ml, $gap, $tick_w, $ml-$gap, ($mt+$mb)/2) if $ENV{PGC_DEBUG_LABELS};
            $b->text($ml - $gap, ($mt+$mb)/2, $self->ylabel,
                align=>'center', valign=>'bottom', angle=>$rot);
        }
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
        elsif ($lg->{type} eq 'fill') {
            # fill_between の凡例: 半透明の塗りパッチ
            $b->set_color(@{$lg->{color}}, $lg->{alpha} // 0.3);
            $b->rect_fill($x0, $y0-6, $pw, 12);
            $b->set_color(@{$lg->{color}}, 1.0);
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

    # colorbar(label=>'...') で設定されたラベルを _colorbar ハッシュに
    # 反映する。_colorbar 自体は imshow/scatter(c=>...) 等の描画コマンドが
    # cmap/vmin/vmax を保存する場所であり、colorbar() メソッドの label
    # オプションとは別経路でセットされるため、ここで合成する。
    $cb->{label} = $self->colorbar_label if ($self->colorbar_label // '') ne '';

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
            # 以前は cx = ml - pad - cw としていたが、これは ml の内側
            # （プロット領域）に直接めり込む計算だった。left配置のcolorbar
            # はY軸数値ラベル(おおよそ ml-21 の位置から左に20px程度の
            # 文字幅で伸びる)よりさらに外側(左)に置く必要があるため、
            # 固定オフセット47pxを追加で確保する。
            # （tight_layout側でも colorbar_location=>'left' 指定時に
            #   margin_left を+68px拡張しているので、この47pxはその
            #   拡張分の範囲内に収まる設計になっている）
            $cx         = $ml - 47 - $pad - $cw;
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

        # colorbar全体のラベル（例: 'intensity'）。ティックラベルとは別に、
        # カラーバー本体の外側に縦書きで配置する。ティックラベルの最大幅を
        # 考慮しないため固定オフセットだが、ティックラベルとの重なりは
        # 通常のフォントサイズ・ティック数値の桁数では起きにくい。
        # angle=>90(正)を使う。-90だと文字が上から下に読む向きになり、
        # 通常のylabelと反転して見えてしまう(ユーザー指摘により発覚)。
        if ($cb->{label} // '' ne '') {
            $b->set_font(size => 10);
            my $cb_label_x = ($loc eq 'right')
                ? $cx + $cw + 40
                : $cx - 40;
            warn sprintf("[DEBUG colorbar] loc=%s ml=%s mr=%s cx=%s cw=%s cb_label_x=%s\n",
                $loc, $ml, $mr, $cx, $cw, $cb_label_x) if $ENV{PGC_DEBUG_LABELS};
            $b->text($cb_label_x, $y0 + $h/2, $cb->{label},
                align=>'center', valign=>'middle', angle=>90);
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

        # colorbar全体のラベル（例: 'intensity'）。top/bottom配置時は
        # ティックラベルのさらに外側に横書きで配置する。
        if ($cb->{label} // '' ne '') {
            $b->set_font(size => 10);
            my $cb_label_y = ($loc eq 'bottom')
                ? $label_y + 16
                : $label_y - 16;
            my $cb_label_valign = ($loc eq 'bottom') ? 'top' : 'bottom';
            $b->text($x0 + $w/2, $cb_label_y, $cb->{label},
                align=>'center', valign=>$cb_label_valign);
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
    my $cmap   = $self->_resolve_cmap($opt{cmap});
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
# pcolormesh($x, $y, $z, %opt) — matplotlib pcolormesh() 相当
# 不均一グリッドの疑似カラー表示。imshow()は均一グリッド(等間隔の
# ピクセル)専用なのに対し、pcolormesh()は$x/$yに任意の(不等間隔な)
# セル境界座標を渡せる。
#
# $x: 長さ nx のセル境界のX座標(1次元)。セル数は nx-1。
# $y: 長さ ny のセル境界のY座標(1次元)。セル数は ny-1。
# $z: 各セルの値。形状は (ny-1, nx-1) を期待するが、利便性のため
#     (ny, nx)(imshow/contourf と同じ慣習でセル中心相当の値を渡す
#     簡易指定)も許容し、その場合は最後の行・列を無視して
#     (ny-1, nx-1) として扱う。
#
# pcolor() は matplotlib では不均一な四辺形セルや個別マスク等にも
# 対応する低速版だが、P:G:Cでは現状pcolormeshと同一実装の別名と
# する(将来的に四辺形対応が必要になれば分離する)。
# ==================================================================
sub pcolormesh {
    my ($self, $x, $y, $z, %opt) = @_;
    $x = pdl($x) unless ref($x) && $x->isa('PDL');
    $y = pdl($y) unless ref($y) && $y->isa('PDL');
    $z = pdl($z) unless ref($z) && $z->isa('PDL');

    my $cmap = $self->_resolve_cmap($opt{cmap});
    my $vmin = $opt{vmin} // $z->min;
    my $vmax = $opt{vmax} // $z->max;

    push @{ $self->_queue }, {
        type  => 'pcolormesh',
        x     => $x, y => $y, z => $z,
        cmap  => $cmap,
        vmin  => $vmin,
        vmax  => $vmax,
        alpha => $opt{alpha} // 1.0,
    };

    $self->_expand_range($x, $y);
    $self->_colorbar({ cmap => $cmap, vmin => $vmin, vmax => $vmax });
    return $self;
}

sub pcolor; *pcolor = \&pcolormesh;

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
    $self->colorbar_label($opt{label}    // '');
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
    $self->{_ytick_rot} = $opt{rotation} // 0;
    return $self;
}

# ==================================================================
# tight_layout Figure
# ==================================================================
sub set_tight_layout {
    warn "PDL::Graphics::Cairo: set_tight_layout() on an Axes object has no effect.\n"
       . "  Call \$fig->tight_layout() on the Figure object instead.\n";
    return $_[0];
}


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
    $twin->_is_twin(1);
    $twin->_twin_of($self);

    # X  self draw
    $self->_twin_ax($twin);
    push @{ $self->_twin_axes }, $twin;

    # Figure の axes_list に twin を登録する。以前はここでの登録処理が
    # 欠落していたため、twin オブジェクトの draw() が一度も呼ばれず
    # (Figure::_render_to は axes_list をループするだけなので)、
    # twinx() で作った第2Y軸が常に描画されない不具合があった。
    if (my $fig = $self->_figure) {
        $fig->add_axes($twin);
        $twin->_figure($fig);
    }
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

# clear() — cla() の別名（matplotlib では Axes.clear == Axes.cla）。
sub clear { goto &cla }

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

    my $levels   = $opt{levels}     // 8;
    my $colors   = $opt{colors}     // $opt{color} // 'black';
    my $lws      = $opt{linewidths} // $opt{linewidth} // $opt{lw} // 1.0;
    my $lss      = $opt{linestyles} // $opt{linestyle} // 'solid';
    my $vmin     = $opt{vmin}       // $z->min->at(0);
    my $vmax     = $opt{vmax}       // $z->max->at(0);

    my @level_vals;
    if (ref($levels) eq 'ARRAY') {
        @level_vals = @$levels;
    } else {
        my $n    = $levels;
        my $step = ($vmax - $vmin) / ($n + 1);
        @level_vals = map { $vmin + $_ * $step } 1..$n;
    }

    push @{ $self->_queue }, {
        type       => 'contour',
        x          => $x, y => $y, z => $z,
        levels     => \@level_vals,
        colors     => $colors,
        linewidths => $lws,
        linestyles => $lss,
        alpha      => $opt{alpha} // 1.0,
    };

    $self->_expand_range($x, $y);
    return $self;
}

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

    my $cmap   = $self->_resolve_cmap($opt{cmap});
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

    # オプション指定は2つの形式をサポートする:
    #   (A) 末尾にハッシュリファレンス1個:  stackplot($x,$y1,$y2,{labels=>[...]})
    #   (B) フラットなキーワード引数:        stackplot($x,$y1,$y2,labels=>[...])
    # (B) は他メソッド(errorbar/fill_between等)と同じ呼び方なので、
    # 末尾からキー名(文字列)+値のペアを既知キー一覧と照合して剥がし取る。
    # PDLデータ系列の値そのもの(PDLオブジェクトや数値配列ref)と取り違えないよう、
    # 「文字列であり、かつ既知のオプションキー名である」場合のみ剥がす。
    my %opt;
    if (@ys_and_opts && ref($ys_and_opts[-1]) eq 'HASH') {
        %opt = %{ pop @ys_and_opts };
    } else {
        my %known_keys = map { $_ => 1 } qw(labels colors alpha);
        while (@ys_and_opts >= 2
            && !ref($ys_and_opts[-2])
            && $known_keys{ $ys_and_opts[-2] }) {
            my $val = pop @ys_and_opts;
            my $key = pop @ys_and_opts;
            $opt{$key} = $val;
        }
    }

    $x = pdl($x) unless ref($x) && $x->isa('PDL');

    my @ys  = map {
        if (ref($_) eq 'ARRAY') {
            die "stackplot: pass y-series as separate arguments, not an arrayref.\n" .
                "  Wrong: \$ax->stackplot(\$x, [\$y1,\$y2,\$y3])\n" .
                "  Right: \$ax->stackplot(\$x, \$y1, \$y2, \$y3)\n";
        }
        ref($_) && $_->isa('PDL') ? $_ : pdl($_)
    } @ys_and_opts;
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

# ==================================================================
# matplotlib compatibility aliases and small missing methods
# ==================================================================
#
# Alias policy:
#   matplotlib name  ←→  P:G:C primary name
#   plot                  line          (both documented; plot is matplotlib-canonical)
#   hist                  histogram
#   scatter               scatter       (identical — no alias needed)
#   bar / barh / step / stem / imshow / contourf / contour / pie /
#   boxplot / violin / quiver / fill_between / errorbar / annotate /
#   text / axhline / axvline / axhspan / axvspan   (identical — no alias needed)
#   set_xlim / set_ylim   already alias xlim/ylim
#   set_xticks / set_yticks / set_xticklabels / set_yticklabels  — already present
#   set_xscale / set_yscale   — already present
#   invert_xaxis / invert_yaxis  — already present
#   twinx / cla / clear / set_aspect / axis  — already present

# grid(bool, %opt) — matplotlib: ax.grid(True) or ax.grid(True, color='.9')
# P:G:C had only set_grid(); now grid() as direct alias matches matplotlib calling convention.

# sub grid {
#     my ($self, @args) = @_;
#     if (@args) {
#         # grid(1), grid(0), grid(True/False), grid(color=>...)
#         my $on = (!ref $args[0] && $args[0] =~ /^\d+$/) ? shift @args : 1;
#         return $self->set_grid($on, @args);
#     }
#     # no args: toggle (matplotlib: ax.grid() toggles)
#     return $self->set_grid( $self->grid ? 0 : 1 );
# }

# get_xlim / get_ylim — return (lo, hi) after finalize (or current setting)
sub get_xlim {
    my ($self) = @_;
    return (defined $self->xmin ? $self->xmin : 0,
            defined $self->xmax ? $self->xmax : 1);
}
sub get_ylim {
    my ($self) = @_;
    return (defined $self->ymin ? $self->ymin : 0,
            defined $self->ymax ? $self->ymax : 1);
}

# image_frac_to_data($fx, $fy) — 画像分率（0..1）→ データ座標
# draw() または tight_layout() → to_png/to_inline の後に呼ぶこと。
# $fx: Figure全体の横方向分率 (0=左端, 1=右端)
# $fy: Figure全体の縦方向分率 (0=上端, 1=下端)  ← giza-serverのCURSOR/PICK送出値と同方向
# 返値: ($x_data, $y_data)。プロット枠外なら undef, undef を返す。
sub image_frac_to_data {
    my ($self, $fx, $fy) = @_;
    my $fig = $self->_figure
        or die "image_frac_to_data: Axes が Figure に属していません\n";
    my ($ml, $mr, $mt, $mb) =
        ($self->_plot_ml, $self->_plot_mr, $self->_plot_mt, $self->_plot_mb);
    unless (defined $ml) {
        die "image_frac_to_data: draw() / tight_layout() の前に呼ばれました\n";
    }
    # 画像全体ピクセル座標に変換
    my $px = $fx * $fig->width;
    my $py = $fy * $fig->height;
    # プロット枠外なら undef
    if ($px < $ml || $px > $mr || $py < $mt || $py > $mb) {
        return (undef, undef);
    }
    my ($xmin, $xmax) = ($self->xmin // 0, $self->xmax // 1);
    my ($ymin, $ymax) = ($self->ymin // 0, $self->ymax // 1);
    # X座標: 左→右
    my $x_data = $xmin + ($px - $ml) / ($mr - $ml) * ($xmax - $xmin);
    # Y座標: Cairo は上→下 (py増加=下)、データ座標は下→上が普通
    # _y_reversed(negative-up, ERP/PGPLOT流) の場合は ymin/ymax が逆転している
    my $y_data;
    if ($self->{_y_reversed}) {
        # ymin < ymax だが表示は上がマイナス: py小さい=上=ymax方向
        $y_data = $ymin + ($py - $mt) / ($mb - $mt) * ($ymax - $ymin);
    } else {
        # 通常: py小さい=上=ymax方向
        $y_data = $ymax - ($py - $mt) / ($mb - $mt) * ($ymax - $ymin);
    }
    return ($x_data, $y_data);
}

# data_to_image_frac($x, $y) — データ座標 → 画像分率  (image_frac_to_data の逆)
sub data_to_image_frac {
    my ($self, $x, $y) = @_;
    my $fig = $self->_figure
        or die "data_to_image_frac: Axes が Figure に属していません\n";
    my ($ml, $mr, $mt, $mb) =
        ($self->_plot_ml, $self->_plot_mr, $self->_plot_mt, $self->_plot_mb);
    unless (defined $ml) {
        die "data_to_image_frac: draw() / tight_layout() の前に呼ばれました\n";
    }
    my ($xmin, $xmax) = ($self->xmin // 0, $self->xmax // 1);
    my ($ymin, $ymax) = ($self->ymin // 0, $self->ymax // 1);
    my $px = $ml + ($x - $xmin) / ($xmax - $xmin) * ($mr - $ml);
    my $py;
    if ($self->{_y_reversed}) {
        $py = $mt + ($y - $ymin) / ($ymax - $ymin) * ($mb - $mt);
    } else {
        $py = $mb - ($y - $ymin) / ($ymax - $ymin) * ($mb - $mt);
    }
    return ($px / $fig->width, $py / $fig->height);
}


# hlines(y, xmin, xmax, %opt)  — matplotlib ax.hlines()
# y can be scalar or PDL/arrayref of y positions
sub hlines {
    my ($self, $y, $xmin, $xmax, %opt) = @_;
    my @ys = ref($y) ? (ref($y) eq 'ARRAY' ? @$y : list($y)) : ($y);
    for my $yv (@ys) {
        $self->axhline($yv, xmin => $xmin, xmax => $xmax, %opt);
    }
    return $self;
}

# vlines(x, ymin, ymax, %opt)  — matplotlib ax.vlines()
sub vlines {
    my ($self, $x, $ymin, $ymax, %opt) = @_;
    my @xs = ref($x) ? (ref($x) eq 'ARRAY' ? @$x : list($x)) : ($x);
    for my $xv (@xs) {
        $self->axvline($xv, ymin => $ymin, ymax => $ymax, %opt);
    }
    return $self;
}

# fill(x, y, %opt)  — matplotlib ax.fill(): filled polygon
# Implemented as fill_between with y2=0 when a single y series is given,
# or as fill_between(x, y1, y2) when called with three data args.
sub fill {
    my ($self, $x, $y, @rest) = @_;
    if (@rest && ref($rest[0])) {
        my $y2 = shift @rest;
        return $self->fill_between($x, $y, $y2, @rest);
    }
        # y2=scalar PDL だと fill_between の append でサイズ不一致になるため同長ゼロに展開
    return $self->fill_between($x, $y, zeroes($x->nelem), @rest);
}

# xaxis_formatter($coderef) -- set custom X tick label formatter
# $coderef receives (value, index) and returns a string
# Example: $ax->xaxis_formatter(sub { sprintf '%.1f%%', $_[0]*100 })
sub xaxis_formatter {
    my ($self, $fmt) = @_;
    $self->_xformatter($fmt);
    return $self;
}

# yaxis_formatter($coderef) -- set custom Y tick label formatter
sub yaxis_formatter {
    my ($self, $fmt) = @_;
    $self->_yformatter($fmt);
    return $self;
}

# set_major_formatter($axis, $coderef) -- matplotlib Axes.xaxis.set_major_formatter compat
# Usage: $ax->set_major_formatter('x', sub { ... })
#        $ax->set_major_formatter('y', sub { ... })
sub set_major_formatter {
    my ($self, $axis, $fmt) = @_;
    if ($axis eq 'x') { return $self->xaxis_formatter($fmt) }
    if ($axis eq 'y') { return $self->yaxis_formatter($fmt) }
    return $self;
}

# inset_axes([$x0,$y0,$w,$h], %opt) -- create inset axes
# $x0,$y0,$w,$h are fractions of the parent axes bounding box (0..1)
# x0,y0 = lower-left corner; w,h = width/height fraction
# Options: transform ('axes' default)
sub inset_axes {
    my ($self, $bounds, %opt) = @_;
    $bounds //= [0.6, 0.6, 0.35, 0.35];
    my ($bx0, $by0, $bw, $bh) = @$bounds;

    # Compute pixel coordinates from parent axes layout
    # These are fractions of the axes *data* area (inside margins)
    # We use the full axes bounding box (fig_x,fig_y,width,height)
    my $px = $self->fig_x;
    my $py = $self->fig_y;
    my $pw = $self->width;
    my $ph = $self->height;

    # Convert fractions to pixels
    # y0 is from bottom in matplotlib, but Cairo y increases downward
    my $ix = int($px + $bx0 * $pw);
    my $iy = int($py + (1 - $by0 - $bh) * $ph);  # flip y
    my $iw = int($bw * $pw);
    my $ih = int($bh * $ph);

    # Create new Axes with computed pixel position
    my $ax_in = PDL::Graphics::Cairo::Axes->new(
        fig_x    => $ix,
        fig_y    => $iy,
        width    => $iw,
        height   => $ih,
        _is_inset => 1,
    );

    # Register in parent and figure
    push @{ $self->_inset_axes }, $ax_in;
    if ($self->_figure) {
        push @{ $self->_figure->axes_list }, $ax_in;
    }
    return $ax_in;
}

sub minorticks_on  { $_[0]->_minor_ticks_on(1); $_[0] }
sub minorticks_off { $_[0]->_minor_ticks_on(0); $_[0] }

sub set_minor_locator {
    my ($self, $n) = @_;
    $self->_minor_n($n);
    $self->_minor_ticks_on(1);
    return $self;
}

# tick_params(%opt)  — matplotlib ax.tick_params()
# Minimal: handles labelsize, labelcolor, width, length, direction (stubs others silently).
# Actual rendering of custom tick style is future work; this prevents die() on mpl-ported code.
# tick_params(%opt)  — matplotlib ax.tick_params() 完全実装
# 対応キー: axis, which, direction, length, width, color, colors,
#           labelsize, labelcolor, labelrotation, pad,
#           bottom, top, left, right, labelbottom, labeltop, labelleft, labelright
sub tick_params {
    my ($self, %opt) = @_;

    my $tp = $self->_tick_params;

    # 'colors' は tick 線色とラベル色の両方を一括指定 (matplotlib互换)
    if (defined $opt{colors}) {
        $opt{color}      //= $opt{colors};
        $opt{labelcolor} //= $opt{colors};
    }

    # 'axis' キーで x/y/both を仕分け
    my $axis = delete $opt{axis} // 'both';

    my $which_val = $opt{which} // 'major';
    for my $k (keys %opt) {
        next if $k eq 'which';
        my $pfx = ($which_val eq 'minor') ? 'minor_' : '';
        if ($axis eq 'both') {
            $tp->{"x_${pfx}$k"} = $opt{$k};
            $tp->{"y_${pfx}$k"} = $opt{$k};
        } elsif ($axis eq 'x') {
            $tp->{"x_${pfx}$k"} = $opt{$k};
        } elsif ($axis eq 'y') {
            $tp->{"y_${pfx}$k"} = $opt{$k};
        }
    }

    $self->_tick_params($tp);

    if (defined $opt{which}) {
        $self->_minor_ticks_on(1) if $opt{which} =~ /minor|both/;
    }
    return $self;
}

# twiny()  — share X axis, independent Y axis (mirror of twinx)
# Like twinx but transposes the role of axes.
sub twiny {
    my ($self, %opt) = @_;
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
    $twin->_is_twin(1);
    $twin->_twin_of($self);
    $twin->_twin_type('y');   # 'y' = Y軸を共有、X軸独立（上端に第2X軸）
    # 親側からこのtwinを参照できるようにする。twinx()と異なりこれまで
    # 一切登録されておらず、tight_layout側でtwinyの第2X軸用マージンを
    # 確保する処理(_twin_axes経由)が常に空振りしていた。
    push @{ $self->_twin_axes }, $twin;
    # X軸範囲(xmin/xmax)はdraw()内で親と独立に確定される。
    # Y軸範囲(ymin/ymax)はdraw()内で親と共有される(twinxがX軸を
    # 共有するのと対称のロジック)。
    #
    # 以前は $self->{_figure} という生のハッシュキーでFigure参照を
    # 取得しようとしていたが、Axes.pmはMooを使っており、属性への
    # アクセスは生ハッシュキーではなくアクセサメソッド経由が安全
    # (Mooの内部ストレージ実装に依存しないため)。このバグにより
    # add_axesが一度も呼ばれず、twinオブジェクトがFigureのaxes_list
    # に追加されない=描画されない、という不具合があった。
    if (my $fig = $self->_figure) {
        $fig->add_axes($twin);
        $twin->_figure($fig);
    }
    return $twin;
}

# margins(%opt or scalar)  — matplotlib ax.margins()
# Sets auto-scale margin fraction. P:G:C doesn't yet have a per-axis margin fraction,
# so this is a documented no-op that prevents die() on ported code.
sub margins {
    my ($self, @args) = @_;
    # TODO: plumb margin_fraction into nice_range calls
    return $self;
}

1;
