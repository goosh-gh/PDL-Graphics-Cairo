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

# 母標準偏差(N で割る。PDL::Stats::Basic の stdv と同じ定義)を Perl の数で返す。
# qqplot と hist_kde は PDL::Stats が無くても動くよう、こちらを使う。
sub _stdv_pop {
    my ($x) = @_;
    my $d = $x->double->flat;
    return 0 unless $d->nelem;
    return sqrt((($d - $d->avg) ** 2)->avg->sclr);
}


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
has colorbar_reserve  => (is => 'rw', default => sub { 1 });   # 0: no layout room, see colorbar()
has colorbar_tick_step => (is => 'rw', default => sub { undef });  # see colorbar()

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
# draw() が確定したデータ範囲 [xmin, xmax, ymin, ymax]。twin が共有軸の
# 範囲を親から受け取るのに使う(親の xmin 等は draw 後にユーザ指定値へ戻る)。
has _plot_range  => (is => 'rw');
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

    my $color = defined $opt{color}
        ? $self->_parse_color($opt{color})
        : $self->_next_color();

    # decimate => 'm4': 描画のときに、画素の列ごとに 最初・最小・最大・最後 の 4 点に間引く
    # (PDL::Graphics::Cairo::LTTB::m4_index_px)。'none' か未指定なら間引かない
    my $decimate = $opt{decimate} // 'none';
    die "line: decimate must be 'm4' or 'none' (got '$decimate')\n"
        unless $decimate eq 'm4' || $decimate eq 'none';

    push @{ $self->_queue }, {
        type      => 'line',
        x         => $x, y => $y,
        color     => $color,
        lw        => _opt_lw(\%opt, 1.5),
        linestyle => $opt{linestyle}  // $opt{ls} // 'solid',
        alpha     => $opt{alpha}      // 1.0,
        label     => $opt{label}      // undef,
        marker    => $opt{marker}     // undef,  # 'o','s','^','d','+','x' or undef=no marker
        ms        => $opt{markersize} // $opt{ms} // 4,
        fill      => (($opt{fillstyle}//'full') eq 'none') ? 0 : 1,
        decimate  => $decimate,
    };
    $self->_expand_range($x, $y);
    if (defined $opt{label}) {
        push @{ $self->_legends }, { type=>'line', color=>$color, label=>$opt{label},
            lw=>_opt_lw(\%opt, 1.5), ls=>$opt{linestyle}//$opt{ls}//'solid' };
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

    my $color = defined $opt{color} || defined $opt{c}
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
    my $color  = defined $opt{color}
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
    my $color  = defined $opt{color}
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

    my $color = defined $opt{color}
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

# _opt_lw(\%opt, $default): line width from either key, `linewidth` or `lw`
# (matplotlib accepts both). Every plot method reads it through here; up to
# 0.42 step/errorbar/stem read only linewidth and qqplot only lw, ignoring
# the other key without a word.
sub _opt_lw {
    my ($opt, $default) = @_;
    return $opt->{linewidth} // $opt->{lw} // $default;
}

# ---- errorbar ----------------------------------------------------
sub errorbar {
    my ($self, $x, $y, %opt) = @_;
    $x = pdl($x) unless ref($x) && $x->isa('PDL');
    $y = pdl($y) unless ref($y) && $y->isa('PDL');

    my $yerr = exists $opt{yerr} ? pdl($opt{yerr}) : undef;
    my $xerr = exists $opt{xerr} ? pdl($opt{xerr}) : undef;

    my $color = defined $opt{color}
        ? $self->_parse_color($opt{color}) : $self->_next_color();

    push @{ $self->_queue }, {
        type   => 'errorbar',
        x      => $x, y => $y,
        yerr   => $yerr, xerr => $xerr,
        color  => $color,
        lw     => _opt_lw(\%opt, 1.5),   # 0: points not joined
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
        my $lw = _opt_lw(\%opt, 1.5);
        push @{ $self->_legends }, $lw > 0
            ? { type=>'line', color=>$color, label=>$opt{label}, lw=>$lw }
            : { type=>'marker', color=>$color, label=>$opt{label},
                marker=>$opt{marker} // 'o' };
    }
    return $self;
}

# ---- fill_between ------------------------------------------------
sub fill_between {
    my ($self, $x, $y1, $y2, %opt) = @_;
    $x  = pdl($x)  unless ref($x)  && $x->isa('PDL');
    $y1 = pdl($y1) unless ref($y1) && $y1->isa('PDL');
    $y2 = pdl($y2) unless ref($y2) && $y2->isa('PDL');

    my $color = defined $opt{color}
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

    my $color = defined $opt{color}
        ? $self->_parse_color($opt{color}) : $self->_next_color();
    push @{ $self->_queue }, {
        type      => 'step',
        x         => $x, y => $y,
        color     => $color,
        lw        => _opt_lw(\%opt, 1.5),
        linestyle => $opt{linestyle} // 'solid',
        where     => $opt{where}     // 'pre',
        label     => $opt{label}     // undef,
    };
    $self->_expand_range($x, $y);
    if (defined $opt{label}) {
        push @{ $self->_legends }, { type=>'line', color=>$color, label=>$opt{label}, lw=>_opt_lw(\%opt, 1.5) };
    }
    return $self;
}

# ---- stem --------------------------------------------------------
sub stem {
    my ($self, $x, $y, %opt) = @_;
    $x = pdl($x) unless ref($x) && $x->isa('PDL');
    $y = pdl($y) unless ref($y) && $y->isa('PDL');

    my $color = defined $opt{color}
        ? $self->_parse_color($opt{color}) : $self->_next_color();
    push @{ $self->_queue }, {
        type   => 'stem',
        x      => $x, y => $y,
        color  => $color,
        lw     => _opt_lw(\%opt, 1.0),
        ms     => $opt{markersize}// 4,
        label  => $opt{label}     // undef,
    };
    $self->_expand_range($x, $y->append(pdl(0)));
    # stem の凡例は丸いマーカー(描画と同じ)。0.42 までは label を
    # 受け取っても凡例に積んでいなかった。
    push @{ $self->_legends }, { type => 'marker', color => $color,
        label => $opt{label}, marker => 'o' } if defined $opt{label};
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
        lw         => _opt_lw(\%opt, 0),   # 既定は点を結ばない(群の比較)
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

    my $fc = defined $opt{color}
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
    my $dstd  = _stdv_pop($sorted);
    my $xl = pdl($qmin, $qmax);
    my $yl = $dmean + $dstd * $xl;
    $self->line($xl, $yl,
        color => $self->_parse_color($opt{line_color} // 'red'),
        lw    => _opt_lw(\%opt, 1.2),
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
    my $std  = _stdv_pop($data) || 1;
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
        lw     => _opt_lw(\%opt, 1.0),
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
        lw     => _opt_lw(\%opt, 1.0),
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

# legend(loc => ...)
#   Inside the axes frame (a white 85% box, 6 px from the frame):
#     'upper right' (default), 'upper left', 'lower right', 'lower left'.
#   Outside the frame (no box), with room taken by tight_layout:
#     'outside top'   one row of entries in the title row, right-aligned to
#                     the frame. If the title would touch it, the title is
#                     left-aligned; if it still does not fit, the legend gets
#                     its own row between the title and the frame.
#     'outside right' one column right of the frame; the frame gets narrower.
#     'outside'       'outside top' with up to outside_max entries
#                     (default 3), else 'outside right'.
sub legend {
    my ($self, %opt) = @_;
    $self->{_show_legend} = 1;
    $self->{_legend_loc}  = $opt{loc} // 'upper right';
    $self->{_legend_outside_max} = $opt{outside_max} // 3;
    return $self;
}

# Where the legend goes: 'inside', 'top', 'right' or '' (no legend).
sub _legend_place {
    my ($self) = @_;
    return '' unless $self->{_show_legend} && @{ $self->_legends }
                  && !$self->{_axis_off};
    my $loc = $self->{_legend_loc} // 'upper right';
    if ($loc eq 'outside') {
        $loc = @{ $self->_legends } <= ($self->{_legend_outside_max} // 3)
             ? 'outside top' : 'outside right';
    }
    return 'top'   if $loc eq 'outside top';
    return 'right' if $loc eq 'outside right';
    return 'inside';
}

# Legend entry sizes measured with $m (a Driver, or tight_layout's measurer).
#   entry_w: [ width of each entry: patch + gap + text ]
#   row_w: one row with LEG_SEP px between entries; col_w: widest entry.
use constant { LEG_FS => 11, LEG_LH => 20, LEG_PW => 24, LEG_PAD => 8,
               LEG_SEP => 14, LEG_GAP => 10 };
sub _text_wh {
    my ($m, $str) = @_;
    return $m->text_size($str) if $m->can('text_size');
    return ($m->text_width($str), 16);
}
sub _legend_geom {
    my ($self, $m) = @_;
    $m->set_font(size => LEG_FS);
    my @ew = map { LEG_PW + LEG_PAD + (_text_wh($m, $_->{label}))[0] }
             @{ $self->_legends };
    my $row_w = 0;
    $row_w += $_ for @ew;
    $row_w += LEG_SEP * (@ew - 1) if @ew > 1;
    my $col_w = 0;
    for (@ew) { $col_w = $_ if $_ > $col_w }
    return { entry_w => \@ew, row_w => $row_w, col_w => $col_w,
             n => scalar @ew };
}

# The 'outside top' layout for a plot rectangle from $ml to $mr, top $mt.
# Returns { x0, yc, title_align, title_up }: the legend row starts at x0 and
# is centred on yc; the title is drawn with title_align ('center' or 'left')
# and title_up px higher than usual.
sub _legend_top_layout {
    my ($self, $m, $ml, $mr, $mt, $level) = @_;
    my $g    = $self->_legend_geom($m);
    my $x0   = $mr - $g->{row_w};
    my $toff = $level == 1 ? 11 : 14;
    my %r = (x0 => $x0, title_align => 'center', title_up => 0,
             row_w => $g->{row_w}, entry_w => $g->{entry_w});
    if ($self->title eq '') {
        $r{yc} = $mt - 4 - LEG_LH / 2;
        return \%r;
    }
    $m->set_font(size => ($level == 1 ? 11 : 13), weight => 'bold');
    my ($tw, $th) = _text_wh($m, $self->title);
    if (($ml + $mr) / 2 + $tw / 2 + LEG_SEP <= $x0) {
        $r{yc} = $mt - $toff - $th / 2;          # beside the centred title
    } elsif ($ml + $tw + LEG_SEP <= $x0) {
        $r{title_align} = 'left';                # beside the title, moved left
        $r{yc} = $mt - $toff - $th / 2;
    } else {
        # own row just above the frame; the title moves up above it
        $r{yc}       = $mt - 4 - LEG_LH / 2;
        $r{title_up} = 4 + LEG_LH + 4 - $toff;
        $r{title_up} = 0 if $r{title_up} < 0;
    }
    return \%r;
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
    $self->{_position_set} = 1;     # tight_layout does not move it (_tight_gridspec)
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
    # 描画矩形と共有軸の範囲は、親の draw() が確定した値(_plot_m* /
    # _plot_range)を使う。親は axes_list で twin より前にあるので、同じ描画の
    # 中で先に確定している。twin の fig_x/width 等は作成時の値のままで、
    # tight_layout / subplots_adjust が親を動かしても追従しないため使わない。
    my $parent_rect;
    if ($self->_is_twin && $self->_twin_of) {
        my $parent = $self->_twin_of;
        my ($pxmin, $pxmax, $pymin, $pymax);
        if (my $pr = $parent->_plot_range) {
            ($pxmin, $pxmax, $pymin, $pymax) = @$pr;
            $parent_rect = [ $parent->_plot_ml, $parent->_plot_mt,
                             $parent->_plot_mr, $parent->_plot_mb ];
        } else {
            # 親がまだ描かれていない(twin 単独の draw)
            $parent->_finalize_range()
                unless defined $parent->xmin && defined $parent->ymin;
            ($pxmin, $pxmax, $pymin, $pymax)
                = ($parent->xmin, $parent->xmax, $parent->ymin, $parent->ymax);
        }

        if (($self->_twin_type // '') eq 'y') {
            # twiny: Y 軸を共有、X 軸は独立（上端に第2目盛り）
            $self->ymin($pymin);
            $self->ymax($pymax);
        } else {
            # twinx (デフォルト): X 軸を共有、Y 軸は独立（右端に第2目盛り）
            $self->xmin($pxmin);
            $self->xmax($pxmax);
        }
        # マージンは常に parent と揃える
        $self->margin_left(  $parent->margin_left);
        $self->margin_top(   $parent->margin_top);
        $self->margin_bottom($parent->margin_bottom);
        $self->margin_right( $parent->margin_right);
    }

    #
    my ($ml, $mt, $mr, $mb) = $parent_rect ? @$parent_rect : (
        $self->fig_x + $self->margin_left,
        $self->fig_y + $self->margin_top,
        $self->fig_x + $self->width  - $self->margin_right,
        $self->fig_y + $self->height - $self->margin_bottom,
    );

# set_aspect('equal') — データ座標の縦横比を保つ
    # (twin は親の確定矩形を使うので、aspect 補正は親側で済んでいる)
    if (!$parent_rect && defined $self->{_aspect} && $self->{_aspect} eq 'equal') {
        my $data_w = $self->xmax - $self->xmin;
        my $data_h = $self->ymax - $self->ymin;
        my $pix_w  = $mr - $ml;
        my $pix_h  = $mb - $mt;
        # データ座標1単位あたりのピクセル数を揃える
        my $scale_x = $pix_w / $data_w;
        my $scale_y = $pix_h / $data_h;
        my $anc = $self->{_aspect_anchor} // 'C';
        if ($scale_x > $scale_y) {
            # x方向が広すぎる → 余りを anchor 側でなく反対側へ寄せて縮める
            my $new_pix_w = $pix_h * $data_w / $data_h;
            my $diff = ($pix_w - $new_pix_w);
            if    ($anc eq 'W') { $mr -= $diff }             # 左寄せ(余りは右)
            elsif ($anc eq 'E') { $ml += $diff }             # 右寄せ(余りは左)
            else                { $ml += $diff/2; $mr -= $diff/2 }  # 中央(従来)
        } else {
            # y方向が広すぎる → 同様に上下で寄せる
            my $new_pix_h = $pix_w * $data_h / $data_w;
            my $diff = ($pix_h - $new_pix_h);
            if    ($anc eq 'N') { $mb -= $diff }             # 上寄せ(余りは下)
            elsif ($anc eq 'S') { $mt += $diff }             # 下寄せ(余りは上)
            else                { $mt += $diff/2; $mb -= $diff/2 }  # 中央(従来)
        }
    }

    # draw() が確定した plot 矩形を image_frac_to_data 用にキャッシュ
    $self->_plot_ml($ml);
    $self->_plot_mr($mr);
    $self->_plot_mt($mt);
    $self->_plot_mb($mb);
    $self->_plot_range([ $self->xmin, $self->xmax, $self->ymin, $self->ymax ]);

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

    # Figure::add_connection / data_to_pixel が描画後に参照する確定済み Transform
    $self->{_last_tr} = $tr;

    # legend(loc=>'outside top'): タイトルと凡例の並べ方をここで決め、
    # _draw_labels(タイトル)と _draw_legend の両方が使う。
    delete $self->{_legend_top_now};
    if (!$self->_is_twin && $self->_legend_place eq 'top') {
        $self->{_legend_top_now} = $self->_legend_top_layout(
            $backend, $ml, $mr, $mt, $self->_compact_labels || 0);
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
    # clip_pad_top(): 上側の許容はみ出し量 (px)。既定 15 は従来どおり。
    my $pad_t  = $self->{_clip_pad_top} // 15;
    my $clip_h = $mb - $mt + $pad_t + 1;
    if ($clip_w > 0 && $clip_h > 0) {
        # :  + (14px)
        $backend->clip_rect($ml-1, $mt-$pad_t, $clip_w, $clip_h);
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


        # 枠・目盛り・ラベルは、データを描く命令が 1 つでもあれば描く。
        # データでない命令(text の annot、PGPLOT 互換の pgmtxt/pgtick)だけ
        # の軸では描かない。以前は描く側の種類を列挙していて、
        # pcolormesh・contour・hexbin・heatmap・specgram が漏れており、
        # それだけを描いた軸に枠も目盛りも出なかった。
        my $has_plot = grep {
            $_->{type} !~ /^(annot|pgmtxt|pgtick)$/
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
        # _draw_labels は下で(データの有無・twin によらず)1 回だけ呼ぶ。
        # 以前はここでも呼んでいて、データのある軸ではタイトル・xlabel・
        # ylabel を同じ位置に 2 回重ね描きしていた(文字のふちが濃くなり、
        # 描画時間も余分にかかっていた)。
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
    $self->_draw_colorbar($backend, $ml,$mr,$mt,$mb) if $self->_colorbar_shown;

    # ユーザ指定レンジ（または undef）を復元。次回 draw で autoscale を再解決させる。
    # twin も同じ。twin の共有軸は毎回の draw で親からコピーし直すので、
    # 巻き戻しても失われない。確定した範囲は _plot_range で読める。
    $self->xmin($user_lim[0]); $self->xmax($user_lim[1]);
    $self->ymin($user_lim[2]); $self->ymax($user_lim[3]);
    return $self;
}

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
# Drawing of each queued command type. The subs live in Axes/Render/*.pm
# (same package; loaded at the end of this file). A type added to the
# queue needs an entry here; a type not listed is not drawn.
our %RENDER = (
    # Axes/Render/Basic.pm
    line          => \&_render_line,
    scatter       => \&_render_scatter,
    step          => \&_render_step,
    stem          => \&_render_stem,
    errorbar      => \&_render_errorbar,
    fill_between  => \&_render_fill_between,
    hline         => \&_render_hline,
    vline         => \&_render_vline,
    vspan         => \&_render_vspan,
    hspan         => \&_render_hspan,
    # Axes/Render/Bar.pm
    bar           => \&_render_bar,
    barh          => \&_render_barh,
    hist          => \&_render_hist,
    pie           => \&_render_pie,
    # Axes/Render/Image.pm
    imshow        => \&_render_imshow,
    pcolormesh    => \&_render_pcolormesh,
    contour       => \&_render_contour,
    contourf      => \&_render_contourf,
    heatmap       => \&_render_heatmap,
    hexbin        => \&_render_hexbin,
    specgram      => \&_render_specgram,
    # Axes/Render/Stats.pm
    boxplot_item  => \&_render_boxplot_item,
    box_fliers    => \&_render_box_fliers,
    violin_item   => \&_render_violin_item,
    # Axes/Render/Text.pm
    annot         => \&_render_annot,
    annotate      => \&_render_annotate,
    pgmtxt        => \&_render_pgmtxt,
    pgtick        => \&_render_pgtick,
);

sub _render_cmd {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $draw = $RENDER{ $cmd->{type} } or return;   # unknown types draw nothing
    return $self->$draw($b, $tr, $cmd, $ml,$mt,$mr,$mb);
}

# ------------------------------------------------------------------
#



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
    my ($self, $asp, $anchor) = @_;
    $self->{_aspect} = $asp;
    # 余った方向をどちら側に寄せるか。既定 'C'(中央寄せ=従来互換)。
    # 'W'/'E'=左/右寄せ(横に余るとき), 'N'/'S'=上/下寄せ(縦に余るとき)。
    $self->{_aspect_anchor} = $anchor if defined $anchor;
    return $self;
}

# colorbar location/width/pad/length
# colorbar(%opt)
#   location / loc, width, pad, length / shrink, label   as before
#   cmap => name or ColorMap object, vmin => .., vmax => ..
#       attach a colorbar that does not come from a plot command of this Axes
#       (an image the caller coloured itself, e.g. a scalp map drawn as RGB).
#       The object needs rgb_at($v), $v in [0,1], returning (r, g, b) in [0,1].
#       A colorbar given this way is drawn on an axis('off') panel too.
#   tick_step => 1
#       ticks at the multiples of this value (0, +-1, +-2, ...) instead of
#       automatically chosen ones, so the spacing stays the same when the
#       limits change. When the numbers would overlap on a short bar, only
#       every 2nd, 3rd, ... multiple is kept (0 always among them).
#   reserve => 0
#       do not take room for the colorbar from the plot rectangle; the bar is
#       drawn in whatever lies beside it. For an equal-aspect image narrower
#       than its panel, this keeps the image centred in the panel.
sub colorbar {
    my ($self, %opt) = @_;
    if (defined $opt{cmap}) {
        defined $opt{vmin} && defined $opt{vmax}
            or do { require Carp; Carp::croak("colorbar(cmap => ...) needs vmin and vmax") };
        my $cm = ref $opt{cmap} ? $opt{cmap} : $self->_resolve_cmap($opt{cmap});
        $self->_colorbar({ cmap => $cm, vmin => $opt{vmin}, vmax => $opt{vmax} });
        $self->{_colorbar_force} = 1;
    }
    $self->colorbar_reserve(exists $opt{reserve} ? ($opt{reserve} ? 1 : 0) : 1);
    if (defined $opt{tick_step}) {
        $opt{tick_step} > 0
            or do { require Carp; Carp::croak("colorbar: tick_step must be positive") };
    }
    $self->colorbar_tick_step($opt{tick_step});
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
    # row 0 at the top (_render_heatmap draws row r at y = rows-1-r)
    $self->_yticks([map { $rows - 1 - $_ } 0..$rows-1]);
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

# get_xlim / get_ylim — (lo, hi) を返す。ユーザ指定(xlim/ylim)があればその値、
# 無ければ最後の draw() が確定した範囲(autoscale の余白込み、matplotlib の
# get_xlim と同じ意味)。draw 前で指定も無ければ (0, 1)。
sub get_xlim {
    my ($self) = @_;
    my $pr = $self->_plot_range || [];
    return ($self->xmin // $pr->[0] // 0,
            $self->xmax // $pr->[1] // 1);
}
sub get_ylim {
    my ($self) = @_;
    my $pr = $self->_plot_range || [];
    return ($self->ymin // $pr->[2] // 0,
            $self->ymax // $pr->[3] // 1);
}

# _frac_range — image_frac_to_data / data_to_image_frac が使うデータ範囲
# (xmin, xmax, ymin, ymax)。draw 済みなら描かれた範囲(_plot_range)を使う。
# 画像上の位置と対応するのは描かれた範囲で、autoscale の軸ではデータ端
# (_*_auto)の外に余白が付いているため。draw 前(tight_layout だけ)なら
# 明示 lim、無ければ autoscale のデータ端で近似する。
sub _frac_range {
    my ($self) = @_;
    if (my $pr = $self->_plot_range) {
        return @$pr;
    }
    return ($self->xmin // $self->_xmin_auto // 0,
            $self->xmax // $self->_xmax_auto // 1,
            $self->ymin // $self->_ymin_auto // 0,
            $self->ymax // $self->_ymax_auto // 1);
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
    # 実効レンジ: 描かれた範囲(_frac_range 参照)。draw() 完了後は xmin/xmax が
    # ユーザ指定値(=未指定なら undef)へ巻き戻されるので、それは使わない。
    my ($xmin, $xmax, $ymin, $ymax) = $self->_frac_range;
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
    my ($xmin, $xmax, $ymin, $ymax) = $self->_frac_range;
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
# clip_pad_top($px) — how far above the plot rectangle the plotted data may be
#   drawn before it is clipped (default 15 px). 0 clips exactly at the top edge.
sub clip_pad_top {
    my ($self, $px) = @_;
    return $self->{_clip_pad_top} // 15 unless defined $px;
    $self->{_clip_pad_top} = $px;
    return $self;
}

# data_to_pixel($x, $y) / axes_to_pixel($fx, $fy)
#   Figure pixel coordinates of a data point, or of a fraction of the plot
#   rectangle ((0,0) = bottom-left, (1,1) = top-right). Valid once the axes has
#   been drawn (the transform and plot rectangle are fixed in draw()); returns
#   an empty list before that.
sub data_to_pixel {
    my ($self, $x, $y) = @_;
    my $tr = $self->{_last_tr} or return;
    return ($tr->x($x), $tr->y($y));
}

sub axes_to_pixel {
    my ($self, $fx, $fy) = @_;
    return unless defined $self->_plot_ml;
    return ($self->_plot_ml + $fx * ($self->_plot_mr - $self->_plot_ml),
            $self->_plot_mb - $fy * ($self->_plot_mb - $self->_plot_mt));
}

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

# Drawing code split out of this file (P:G:C31); same package.
require PDL::Graphics::Cairo::Axes::Decor;
require PDL::Graphics::Cairo::Axes::Render::Basic;
require PDL::Graphics::Cairo::Axes::Render::Bar;
require PDL::Graphics::Cairo::Axes::Render::Image;
require PDL::Graphics::Cairo::Axes::Render::Stats;
require PDL::Graphics::Cairo::Axes::Render::Text;

1;
