package PDL::Graphics::Cairo;

use strict;
use warnings;

our $VERSION = '0.1';

use Exporter;
our @EXPORT_OK = qw(figure subplots subplot_mosaic imread
                    ListedColormap Normalize LogNorm BoundaryNorm TwoSlopeNorm
                    style rcParams);
our %EXPORT_TAGS = (
    gnuplot => [],
);

# ==================================================================
# グローバル設定 (matplotlib の rcParams 相当)
# ==================================================================
our %_RCPARAMS = (
    'font.family'      => 'Helvetica Neue',
    'font.size'        => 11,
    'axes.facecolor'   => 'white',
    'axes.edgecolor'   => 'black',
    'axes.grid'        => 0,
    'figure.facecolor' => 'white',
    'lines.linewidth'  => 1.5,
    'lines.markersize' => 4,
    'text.color'       => 'black',
    'xtick.color'      => 'black',
    'ytick.color'      => 'black',
    'xtick.labelsize'  => 10,
    'ytick.labelsize'  => 10,
    # カラーサイクル
    '_color_cycle'     => ['#1f77b4','#ff7f0e','#2ca02c','#d62728',
                           '#9467bd','#8c564b','#e377c2','#7f7f7f',
                           '#bcbd22','#17becf'],
);

# スタイルプリセット定義
our %_STYLE_PRESETS = (
    'default' => {
        'font.family'    => 'Helvetica Neue',
        'axes.facecolor' => 'white',
        'axes.edgecolor' => 'black',
        'axes.grid'      => 0,
        '_color_cycle'   => ['#1f77b4','#ff7f0e','#2ca02c','#d62728',
                             '#9467bd','#8c564b','#e377c2','#7f7f7f',
                             '#bcbd22','#17becf'],
    },
    'ggplot' => {
        'axes.facecolor' => '#E5E5E5',
        'axes.edgecolor' => 'white',
        'axes.grid'      => 1,
        'text.color'     => '#555555',
        'xtick.color'    => '#555555',
        'ytick.color'    => '#555555',
        '_color_cycle'   => ['#E24A33','#348ABD','#988ED5','#777777',
                             '#FBC15E','#8EBA42','#FFB5B8'],
    },
    'seaborn' => {
        'axes.facecolor' => '#EAEAF2',
        'axes.edgecolor' => 'white',
        'axes.grid'      => 1,
        'font.family'    => 'DejaVu Sans',
        '_color_cycle'   => ['#4C72B0','#DD8452','#55A868','#C44E52',
                             '#8172B3','#937860','#DA8BC3','#8C8C8C',
                             '#CCB974','#64B5CD'],
    },
    'seaborn-v0_8' => {  # seaborn の古いエイリアス
        'axes.facecolor' => '#EAEAF2',
        'axes.edgecolor' => 'white',
        'axes.grid'      => 1,
        '_color_cycle'   => ['#4C72B0','#DD8452','#55A868','#C44E52',
                             '#8172B3','#937860','#DA8BC3','#8C8C8C',
                             '#CCB974','#64B5CD'],
    },
    'dark_background' => {
        'axes.facecolor' => '#121212',
        'axes.edgecolor' => '#AAAAAA',
        'figure.facecolor' => '#121212',
        'text.color'     => 'white',
        'xtick.color'    => '#AAAAAA',
        'ytick.color'    => '#AAAAAA',
        'axes.grid'      => 0,
        '_color_cycle'   => ['#8dd3c7','#feffb3','#bfbbd9','#fa8174',
                             '#81b1d2','#fdb462','#b3de69','#bc82bd',
                             '#ccebc4','#ffed6f'],
    },
    'bmh' => {
        'axes.facecolor' => '#EEEEEE',
        'axes.edgecolor' => '#999999',
        'axes.grid'      => 1,
        'font.family'    => 'DejaVu Sans',
        '_color_cycle'   => ['#348ABD','#A60628','#7A68A6','#467821',
                             '#D55E00','#CC79A7','#56B4E9','#009E73',
                             '#F0E442','#0072B2'],
    },
    'fivethirtyeight' => {
        'axes.facecolor' => '#F0F0F0',
        'axes.edgecolor' => '#E0E0E0',
        'axes.grid'      => 1,
        'font.family'    => 'DejaVu Sans',
        '_color_cycle'   => ['#30a2da','#fc4f30','#e5ae38','#6d904f',
                             '#8b8b8b'],
    },
    'grayscale' => {
        'axes.facecolor' => 'white',
        'axes.edgecolor' => 'black',
        'axes.grid'      => 0,
        '_color_cycle'   => ['#000000','#404040','#606060','#808080',
                             '#A0A0A0','#C0C0C0'],
    },
    'tableau-colorblind10' => {
        'axes.facecolor' => 'white',
        'axes.edgecolor' => 'black',
        '_color_cycle'   => ['#006BA4','#FF800E','#ABABAB','#595959',
                             '#5F9ED1','#C85200','#898989','#A2C8EC',
                             '#FFBC79','#CFCFCF'],
    },
);

# style オブジェクト (plt.style.use() の namespace)
package PDL::Graphics::Cairo::Style;
sub use {  ## no critic (ProhibitBuiltinHomonyms)
    my ($class_or_name, $name) = @_;
    # クラスメソッドとして: PDL::Graphics::Cairo::Style->use('ggplot')
    # または直接:           style->use('ggplot')  → $class_or_name は 'ggplot'
    if (!defined $name) {
        $name = $class_or_name;
    }
    my $preset = $PDL::Graphics::Cairo::_STYLE_PRESETS{$name}
        or die "PDL::Graphics::Cairo: unknown style '$name'.\n"
             . "Available: " . join(', ', sort keys %PDL::Graphics::Cairo::_STYLE_PRESETS) . "\n";
    while (my ($k, $v) = each %$preset) {
        $PDL::Graphics::Cairo::_RCPARAMS{$k} = $v;
    }
    return;
}
sub available { return sort keys %PDL::Graphics::Cairo::_STYLE_PRESETS }

package PDL::Graphics::Cairo;

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

# rcParams(%set) または rcParams($key) — グローバル設定の取得/設定
# 使い方:
#   rcParams('font.family', 'IPAGothic');          # 設定
#   rcParams('font.family' => 'Noto Sans CJK JP'); # ハッシュ形式
#   my $f = rcParams('font.family');               # 取得
sub rcParams {
    if (@_ == 1) {
        return $_RCPARAMS{$_[0]};
    } elsif (@_ >= 2 && @_ % 2 == 0) {
        my %h = @_;
        $PDL::Graphics::Cairo::_RCPARAMS{$_} = $h{$_} for keys %h;
    }
    return;
}

# style — plt.style 相当のネームスペース。
#
# 重要な制限事項: 'style->use("ggplot")' という bareword->method 記法は
# Perl の文法上、Exporter 経由でインポートされた関数に対しては正しく
# 動作しない（コンパイル時に 'style' が定数サブルーチンだと認識されない
# ため、'style' は単なるクラス名の bareword として解釈されてしまう）。
# そのため、このモジュールでは以下の2つの確実な呼び方を提供する:
#
#   1. PDL::Graphics::Cairo::Style->use('ggplot');   -- 直接クラスメソッド呼び出し
#   2. style('ggplot');                              -- 関数呼び出し(推奨・短い)
#
# 'style->use(...)' という書き方をする場合は、呼び出し側で
# 'use constant style => "PDL::Graphics::Cairo::Style";' を明示的に
# 書く必要がある（详細はPOD参照）。
sub style {
    # 引数なしで呼ばれた場合 → Style クラス名を返す
    # (PDL::Graphics::Cairo::Style->use(...) で使うため)
    if (@_ == 0) {
        return 'PDL::Graphics::Cairo::Style';
    }
    # 文字列1つで呼ばれた場合 → style('ggplot') のショートカット
    return PDL::Graphics::Cairo::Style->use(@_);
}

use Scalar::Util qw(looks_like_number);
use PDL::Graphics::Cairo::Figure;
use PDL::Graphics::Cairo::ListedColormap;

# ListedColormap / Normalize factory functions
sub ListedColormap {
    my ($colors, %opt) = @_;
    return PDL::Graphics::Cairo::ListedColormap->new($colors, %opt);
}

sub Normalize {
    my (%opt) = @_;
    return PDL::Graphics::Cairo::Normalize->new(%opt);
}

sub LogNorm {
    my (%opt) = @_;
    return PDL::Graphics::Cairo::LogNorm->new(%opt);
}

sub BoundaryNorm {
    my (%opt) = @_;
    return PDL::Graphics::Cairo::BoundaryNorm->new(%opt);
}

sub TwoSlopeNorm {
    my (%opt) = @_;
    return PDL::Graphics::Cairo::TwoSlopeNorm->new(%opt);
}

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
    # MxN のとき @axes は ArrayRef のリスト。フラット Axes と混同しないよう
    # 案内する。常時警告するとmake test等の出力が読みにくくなるため、
    # PGC_DEBUG_LABELS環境変数が設定されているときのみ表示する
    # (他のデバッグ用warnと同じ制御方式に統一)。
    if ($nrows > 1 && $ncols > 1 && $ENV{PGC_DEBUG_LABELS}) {
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

0.1

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
