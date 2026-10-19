package PDL::Graphics::Cairo::Figure;

# =============================================================
# Figure -- equivalent to matplotlib Figure
#   subplot / subplots 
# =============================================================

use strict;
use warnings;
use Moo;
use PDL::Graphics::Cairo::GridSpec;
use PDL::Graphics::Cairo::Axes;
use PDL::Graphics::Cairo::TextLayout qw(estimate_max_line_px);
use PDL::Graphics::Cairo::Tick qw(nice_ticks);

# カラーバーが必要とするマージン幅/高さ(px)を実寸見積り。固定 68/75/50 を置換。
# 右/左: pad + バー幅 + 目盛りギャップ + 目盛りラベル実寸 + (回転ラベル分)。
# 上/下: pad + バー幅 + 目盛り高 + (ラベル分)。過小見積りで切れないよう安全余裕を足す。
sub _cbar_reserve {
    my ($ax) = @_;
    my $loc  = $ax->colorbar_location // 'right';
    my $cw   = $ax->colorbar_width // 16;
    my $pad  = $ax->colorbar_pad // 10;
    my $lab  = $ax->colorbar_label // '';
    my $cb   = $ax->_colorbar;
    if ($loc eq 'right' || $loc eq 'left') {
        my $tickw = 22;                                   # fallback
        if (ref $cb eq 'HASH' && defined $cb->{vmin} && defined $cb->{vmax}) {
            my @tk = eval { $ax->_colorbar_ticks };
            my $mx = 0;
            for my $v (@tk) {
                my $s = eval { PDL::Graphics::Cairo::Axes::_fmt_tick($v) } // sprintf('%g',$v);
                my $w = estimate_max_line_px($s, 9);
                $mx = $w if $w > $mx;
            }
            $tickw = int($mx + 0.5) if $mx > 0;
        }
        my $labw = ($lab ne '') ? 18 : 0;                 # 回転ラベル(高さ≒幅)
        return $pad + $cw + 7 + $tickw + 5 + $labw;
    } else {                                              # top / bottom(横バー)
        my $labh = ($lab ne '') ? 16 : 0;
        return $pad + $cw + 4 + 14 + $labh;               # バー + 目盛り高 + ラベル
    }
}

# Margins of a GridSpec Axes must leave a plot rectangle. In a narrow cell the
# margins chosen for tick numbers can add up to more than the cell (a 31 px
# colorbar cell with 33 + 14 px of margins): the right edge of the plot
# rectangle then lies left of its left edge and data_to_pixel runs backwards.
# When less than MIN_PLOT px would remain, shrink the two margins of that
# direction in proportion so that they take 80% of the cell.
use constant MIN_PLOT => 8;
sub _fit_margins {
    my ($ax, $ml, $mr, $mt, $mb) = @_;
    my ($w, $h) = ($ax->width, $ax->height);
    if ($w - $ml - $mr < MIN_PLOT && $ml + $mr > 0) {
        my $k = 0.8 * $w / ($ml + $mr);
        ($ml, $mr) = (int($ml * $k), int($mr * $k));
    }
    if ($h - $mt - $mb < MIN_PLOT && $mt + $mb > 0) {
        my $k = 0.8 * $h / ($mt + $mb);
        ($mt, $mb) = (int($mt * $k), int($mb * $k));
    }
    return ($ml, $mr, $mt, $mb);
}
use PDL::Graphics::Cairo::Driver::Cairo;
use PDL::Graphics::Cairo::Driver::Gnuplot;

# Text measurer for tight_layout (which runs before any drawing surface
# exists). It answers set_font/text_size like a Driver, from a cache keyed by
# font family, size, weight and string; on a miss it measures with a 1x1
# Driver::Cairo made on first use. The family is read from rcParams on each
# call, so a changed 'font.family' is measured anew.
# (A 5x5 grid asks for ~400 sizes per tight_layout; measuring each took
# 5.7 ms per call, which show_interactive / grid scrub pay on every frame.)
sub _measure_driver {
    return PDL::Graphics::Cairo::Figure::TextMeasure->new;
}

package PDL::Graphics::Cairo::Figure::TextMeasure;
my %SIZE_CACHE;
my $DRIVER;
sub new {
    my $family = $PDL::Graphics::Cairo::_RCPARAMS{'font.family'} // 'Helvetica Neue';
    return bless { family => $family, size => 11, weight => 'normal' }, shift;
}
# Axes::_label_room caches its result only for a measurer that names its font
sub cache_tag { $_[0]{family} }
sub set_font {
    my ($self, %o) = @_;
    $self->{size}   = $o{size}   // $self->{size};
    $self->{weight} = $o{weight} // 'normal';
    return $self;
}
sub text_size {
    my ($self, $str) = @_;
    my $key = join "\0", @$self{qw(family size weight)}, $str // '';
    my $wh = $SIZE_CACHE{$key};
    unless ($wh) {
        $DRIVER //= eval {
            PDL::Graphics::Cairo::Driver::Cairo->new(
                width => 1, height => 1, file => ':memory:')
        } or return (0, 0);
        $DRIVER->set_font(family => $self->{family}, size => $self->{size},
                          weight => $self->{weight});
        %SIZE_CACHE = () if keys %SIZE_CACHE > 20000;
        $wh = $SIZE_CACHE{$key} = [ $DRIVER->text_size($str) ];
    }
    return @$wh;
}
package PDL::Graphics::Cairo::Figure;

# ------------------------------------------------------------------
# DPI
# ------------------------------------------------------------------
has width  => (is => 'rw', default => sub { 800 });
has height => (is => 'rw', default => sub { 600 });
has dpi    => (is => 'ro', default => sub { 96 });

# figsize 展開は Cairo.pm の _apply_figsize() が担う。

# Figure 
has _suptitle_text  => (is => 'rw', default => sub { '' });
has _suptitle_fontsize => (is => 'rw', default => sub { 15 });
has _suptitle_y        => (is => 'rw', default => sub { 18 });

# List of Axes
has axes_list => (is => 'ro', default => sub { [] });
has _gs_axes  => (is => 'ro', default => sub { [] });  # [{ax=>, r0=>, r1=>, c0=>, c1=>}, ...]

# subplot 
has _nrows => (is => 'rw', default => sub { 1 });
has _ncols => (is => 'rw', default => sub { 1 });

# ------------------------------------------------------------------
# subplot(rows, cols, index) — 1-indexedmatplotlib 
# ------------------------------------------------------------------
sub subplot {
    my ($self, $nrows, $ncols, $idx) = @_;
    $idx //= 1;

    $self->_nrows($nrows);
    $self->_ncols($ncols);

    my $fw = $self->width;
    my $fh = $self->height;

    #

    my $pad_x = 20;
    my $pad_y = 20;
    my $top_pad = ($self->{_suptitle_text} // '') ne '' ? 40 : 10;

    my $cell_w = ($fw - $pad_x * ($ncols+1)) / $ncols;
    my $cell_h = ($fh - $pad_y * ($nrows+1) - $top_pad) / $nrows;

    my $row = int(($idx-1) / $ncols);
    my $col = ($idx-1) % $ncols;

    my $fig_x = $pad_x + $col * ($cell_w + $pad_x);
    my $fig_y = $top_pad + $pad_y + $row * ($cell_h + $pad_y);

    my $ax = PDL::Graphics::Cairo::Axes->new(
        width  => $cell_w,
        height => $cell_h,
        fig_x  => $fig_x,
        fig_y  => $fig_y,
    );
    push @{ $self->axes_list }, $ax;
    $ax->_figure($self);
    return $ax;
}

# subplots(rows, cols) — Axes 
sub subplots {
    my ($self, $nrows, $ncols, %opt) = @_;
    $nrows //= 1;
    $ncols //= 1;

    my @grid;
    for my $r (1 .. $nrows) {
        my @row;
        for my $c (1 .. $ncols) {
            my $idx = ($r-1)*$ncols + $c;
            push @row, $self->subplot($nrows, $ncols, $idx);
        }
        push @grid, \@row;
    }

    # 戻り値の規約:
    #   1x1  → Axes オブジェクト 1個
    #   1xN  → Axes のフラットリスト ($ax1, $ax2, ...)
    #   Nx1  → Axes のフラットリスト ($ax1, $ax2, ...)
    #   MxN  → ArrayRef のリスト    ($row0_ref, $row1_ref, ...)
    #            アクセス: my ($fig, @rows) = subplots(M,N); $rows[$r][$c]
    if ($nrows == 1 && $ncols == 1) {
        return $grid[0][0];
    }
    # 1xN / Nx1 をスカラーで受けると、N=1 では Axes なのに N>=2 では黙って
    # 個数(2, 3, ...)になる。チャンネル数で N が変わるコードで踏むので警告する。
    if (defined wantarray && !wantarray) {
        warn "PDL::Graphics::Cairo: subplots($nrows,$ncols) returns a list of "
           . ($nrows * $ncols) . " Axes; in scalar context you get their count.\n"
           . "  Use:  my \@ax = \$fig->subplots($nrows,$ncols);   (one Axes or many)\n"
           . "  or    \$fig->ax(\$i) after subplots().\n";
    }
    if ($nrows == 1) {
        return @{ $grid[0] };
    }
    elsif ($ncols == 1) {
        return map { $_->[0] } @grid;
    }
    # MxN: ArrayRef のリストを返す — フラットに受けないよう警告
    warn "PDL::Graphics::Cairo: subplots($nrows,$ncols) returns a list of "
       . "ArrayRefs, not a flat Axes list.\n"
       . "  Correct usage:  my (\$fig, \@rows) = subplots($nrows,$ncols);\n"
       . "                  \$rows[\$r][\$c]->line(...);\n"
       . "  Wrong usage:    my (\$fig,\$ax1,\$ax2,...) = subplots($nrows,$ncols);\n"
        if !wantarray;
    return @grid;
}

# add_subplot(R, C, idx) — matplotlib 互換。1-based idx で Axes を返す。
# add_gridspec(nrows, ncols, %opt) — matplotlib GridSpec
# Options: left, right, top, bottom (0..1), hspace, wspace
# subplot_mosaic($layout, %opt) — matplotlib subplot_mosaic
# $layout: 'AB\nCC'  or [['A','B'],['C','C']]
# Returns: ($fig, %ax)  where %ax{'A'} etc. are Axes objects
# Options: width, height, hspace, wspace, left, right, top, bottom
sub subplot_mosaic {
    my ($class_or_fig, $layout, %opt) = @_;
    my ($fig, $self);
    if (ref $class_or_fig) {
        $self = $class_or_fig;
    } else {
        require PDL::Graphics::Cairo;
        $fig  = PDL::Graphics::Cairo::Figure->new(
            width  => $opt{width}  // 640,
            height => $opt{height} // 480,
        );
        $self = $fig;
    }

    # Parse layout string or arrayref
    my @rows;
    if (ref $layout eq 'ARRAY') {
        @rows = @$layout;
    } else {
        @rows = map { [ split //, $_ ] } split /\n/, $layout;
    }

    my $nrows = scalar @rows;
    my $ncols = scalar @{ $rows[0] };

    # Validate rectangular layout
    for my $row (@rows) {
        die 'subplot_mosaic: all rows must have same length' if @$row != $ncols;
    }

    # Find unique labels
    my %labels;
    for my $r (0..$nrows-1) {
        for my $c (0..$ncols-1) {
            $labels{ $rows[$r][$c] } = 1;
        }
    }

    # For each label find bounding box (r0,r1,c0,c1)
    my %bbox;
    for my $lbl (keys %labels) {
        my ($r0,$r1,$c0,$c1) = ($nrows,-1,$ncols,-1);  # r0/c0: big sentinel, r1/c1: -1 sentinel
        for my $r (0..$nrows-1) {
            for my $c (0..$ncols-1) {
                next unless $rows[$r][$c] eq $lbl;
                $r0 = $r if $r < $r0;
                $r1 = $r if $r > $r1;
                $c0 = $c if $c < $c0;
                $c1 = $c if $c > $c1;
            }
        }
        $bbox{$lbl} = [$r0, $r1+1, $c0, $c1+1];  # r1/c1 exclusive
    }

    # Build GridSpec with mosaic dims
    my %gs_opt;
    for my $k (qw(left right top bottom hspace wspace)) {
        $gs_opt{$k} = $opt{$k} if exists $opt{$k};
    }
    my $gs = $self->add_gridspec($nrows, $ncols, %gs_opt);

    my %ax;
    for my $lbl (sort keys %labels) {
        my ($r0,$r1,$c0,$c1) = @{ $bbox{$lbl} };
        my $cell = PDL::Graphics::Cairo::GridSpecCell->new(
            gridspec => $gs,
            r0=>$r0, r1=>$r1, c0=>$c0, c1=>$c1,
        );
        $ax{$lbl} = $self->add_subplot($cell);
    }

    return ($self, %ax);
}

sub add_gridspec {
    my ($self, $nrows, $ncols, %opt) = @_;
    $nrows //= 1; $ncols //= 1;
    return PDL::Graphics::Cairo::GridSpec->new(
        nrows  => $nrows,
        ncols  => $ncols,
        figure => $self,
        %opt,
    );
}

sub add_subplot {
    my ($self, $nrows_or_cell, $ncols, $idx, %opt) = @_;
    if (ref($nrows_or_cell) && $nrows_or_cell->isa('PDL::Graphics::Cairo::GridSpecCell')) {
        my $cell = $nrows_or_cell;
        my ($fig_x, $fig_y, $w, $h) = $cell->pixel_rect;
        my $ax_class = ($opt{projection} // '') eq 'polar'
            ? 'PDL::Graphics::Cairo::PolarAxes'
            : 'PDL::Graphics::Cairo::Axes';
        if ($ax_class eq 'PDL::Graphics::Cairo::PolarAxes') {
            require PDL::Graphics::Cairo::PolarAxes;
        }
        my $ax = $ax_class->new(
            width => $w, height => $h,
            fig_x => $fig_x, fig_y => $fig_y,
        );
        push @{ $self->axes_list }, $ax;
        push @{ $self->_gs_axes }, {
            ax => $ax,
            r0 => $cell->r0, r1 => $cell->r1,
            c0 => $cell->c0, c1 => $cell->c1,
            gs => $cell->gridspec,
        };
        $ax->_figure($self);
        return $ax;
    }
    my ($nrows, $ncols2, $idx2) = ($nrows_or_cell, $ncols, $idx);
    $nrows //= 1;  $ncols2 //= 1;  $idx2 //= 1;
    # projection キーワードは %opt から取る
    if (($opt{projection} // '') eq 'polar') {
        require PDL::Graphics::Cairo::PolarAxes;
        my $fw = $self->width;
        my $fh = $self->height;
        my $pad_x = 20;
        my $pad_y = 20;
        my $top_pad = 10;
        my $cell_w = ($fw - $pad_x * ($ncols2+1)) / $ncols2;
        my $cell_h = ($fh - $pad_y * ($nrows+1) - $top_pad) / $nrows;
        my $row = int(($idx2-1) / $ncols2);
        my $col = ($idx2-1) % $ncols2;
        my $fig_x = $pad_x + $col * ($cell_w + $pad_x);
        my $fig_y = $top_pad + $pad_y + $row * ($cell_h + $pad_y);
        my $ax = PDL::Graphics::Cairo::PolarAxes->new(
            width => $cell_w, height => $cell_h,
            fig_x => $fig_x,  fig_y  => $fig_y,
        );
        push @{ $self->axes_list }, $ax;
        $ax->_figure($self);
        return $ax;
    }
    return $self->subplot($nrows, $ncols2, $idx2);
}

#  Axes
# ax($idx)       — 0-based 線形インデックス (matplotlib の axes.flat[i] 相当)
# ax($row, $col) — 0-based (row, col)      (matplotlib の axes[r,c] 相当)
sub ax {
    my ($self, $row_or_idx, $col) = @_;
    my $list = $self->axes_list;
    if (defined $col) {
        my $ncols = $self->_ncols || 1;
        return $list->[$row_or_idx * $ncols + $col];
    }
    return $list->[$row_or_idx];
}

sub axes {
    my ($self, %opt) = @_;
    my $ax = PDL::Graphics::Cairo::Axes->new(
        width  => $self->width,
        height => $self->height,
        fig_x  => 0,
        fig_y  => 0,
        %opt,
    );
    push @{ $self->axes_list }, $ax;
    $ax->_figure($self);
    return $ax;
}



# ------------------------------------------------------------------
# save
# ------------------------------------------------------------------
# ------------------------------------------------------------------
# _render_to($driver) —  driver 
# ------------------------------------------------------------------
# suptitle($text, fontsize=>N, size=>N, y=>0..1)
# matplotlib互換: $fig->suptitle('T') または $fig->set_suptitle('T', fontsize=>16)
sub suptitle {
    my ($self, $title, %opt) = @_;
    return $self->{_suptitle_text} // '' unless defined $title;  # getter
    $self->{_suptitle_text} = $title;
    $self->_suptitle_fontsize($opt{fontsize} // $opt{size} // 15);
    $self->_suptitle_y(int($opt{y} * $self->height)) if defined $opt{y};
    return $self;
}

sub set_suptitle { my ($self, $title, %opt) = @_; $self->suptitle($title, %opt) }

sub _render_to {
    my ($self, $driver) = @_;

    if (($self->{_suptitle_text} // '') ne '') {
        $driver->set_font(size => $self->_suptitle_fontsize, weight => 'bold');
        $driver->set_color(0,0,0);
        $driver->text($self->width/2, $self->_suptitle_y, $self->{_suptitle_text},
            align=>'center', valign=>'middle');
    }

    # tight_layout が未適用なら自動で適用する
    # _auto: GridSpec cells stay as the GridSpec gives them unless tight_layout
    # is called explicitly (see _tight_gridspec)
    $self->tight_layout(_auto => 1) unless $self->{_tight_done};
    for my $ax (@{ $self->axes_list }) {
        $ax->draw($driver);
    }
    $self->_draw_connections($driver);

    $driver->finish();
}

# add_connection(%opt) — a straight line between a point of one axes and a point
# of another (matplotlib ConnectionPatch). Drawn over all axes, unclipped.
#
#   axA => $ax, xyA => [x, y], coordsA => 'data' | 'axes' | 'figure'
#   axB => $ax, xyB => [x, y], coordsB => 'data' | 'axes' | 'figure'
#   color => '#888888', lw => 1, ls => 'solid', alpha => 1
#
# 'data'  : data coordinates of that axes (default)
# 'axes'  : fraction of that axes' plot rectangle, (0,0) bottom-left
# 'figure': fraction of the figure, (0,0) bottom-left (no axes needed)
# A coords value may also be [cx, cy] to mix, e.g. ['data', 'axes'] for
# "this x in data units, the top edge of the plot rectangle".
sub add_connection {
    my ($self, %o) = @_;
    for my $e ('A', 'B') {
        my $c = $o{"coords$e"} //= 'data';
        my @c = ref $c ? @$c : ($c, $c);
        die "add_connection: coords$e must be data, axes or figure\n"
            if grep { !/^(?:data|axes|figure)$/ } @c;
        die "add_connection: xy$e => [x, y] required\n"
            unless ref $o{"xy$e"} eq 'ARRAY' && @{ $o{"xy$e"} } == 2;
        die "add_connection: ax$e required for coords$e '@c'\n"
            if !$o{"ax$e"} && grep { $_ ne 'figure' } @c;
    }
    push @{ $self->{_connections} //= [] }, { %o };
    return $self;
}

# add_text(%opt) — text placed in the same coordinates as add_connection, drawn
# over all axes and unclipped (so it can sit just outside a plot rectangle).
#
#   text => 'N = 293', ax => $ax, xy => [x, y], coords => 'data' | 'axes' | 'figure'
#   ha => 'left' | 'center' | 'right', va => 'top' | 'middle' | 'bottom'
#   offset => [dx, dy]   pixels added after the transform (dy > 0 is downwards)
#   fontsize => 10, weight => 'normal' | 'bold', color => 'black', angle => 0
sub add_text {
    my ($self, %o) = @_;
    my $c = $o{coords} //= 'data';
    my @c = ref $c ? @$c : ($c, $c);
    die "add_text: text required\n" unless defined $o{text};
    die "add_text: coords must be data, axes or figure\n"
        if grep { !/^(?:data|axes|figure)$/ } @c;
    die "add_text: xy => [x, y] required\n" unless ref $o{xy} eq 'ARRAY' && @{ $o{xy} } == 2;
    die "add_text: ax required for coords '@c'\n" if !$o{ax} && grep { $_ ne 'figure' } @c;
    push @{ $self->{_fig_texts} //= [] }, { %o };
    return $self;
}

sub _connection_point {
    my ($self, $ax, $xy, $coords) = @_;
    my @c = ref $coords ? @$coords : ($coords, $coords);
    my @p;
    for my $i (0, 1) {
        my @q = $c[$i] eq 'figure' ? ($xy->[0] * $self->width, (1 - $xy->[1]) * $self->height)
              : $c[$i] eq 'axes'   ? $ax->axes_to_pixel(@$xy)
              :                      $ax->data_to_pixel(@$xy);
        return unless @q;
        $p[$i] = $q[$i];
    }
    return @p;
}

sub _draw_connections {
    my ($self, $driver) = @_;
    for my $c (@{ $self->{_connections} // [] }) {
        my @a = $self->_connection_point($c->{axA}, $c->{xyA}, $c->{coordsA}) or next;
        my @b = $self->_connection_point($c->{axB}, $c->{xyB}, $c->{coordsB}) or next;
        my $lw  = $c->{lw} // $c->{linewidth} // 1;
        my $col = PDL::Graphics::Cairo::Axes->_parse_color($c->{color} // '#888888');
        $driver->set_color(@$col[0 .. 2], $c->{alpha} // 1);
        $driver->set_linewidth($lw);
        $driver->set_linestyle($c->{ls} // $c->{linestyle} // 'solid', $lw);
        $driver->line_seg(@a, @b);
        $driver->set_linestyle('solid', $lw);
    }
    for my $t (@{ $self->{_fig_texts} // [] }) {
        my @p = $self->_connection_point($t->{ax}, $t->{xy}, $t->{coords}) or next;
        my ($dx, $dy) = @{ $t->{offset} // [0, 0] };
        my $col = PDL::Graphics::Cairo::Axes->_parse_color($t->{color} // 'black');
        $driver->set_font(size => ($t->{fontsize} // 10), weight => ($t->{weight} // 'normal'));
        $driver->set_color(@$col[0 .. 2], $t->{alpha} // 1);
        $driver->text($p[0] + $dx, $p[1] + $dy, $t->{text},
                      align  => ($t->{ha} // $t->{halign} // 'left'),
                      valign => ($t->{va} // $t->{valign} // 'bottom'),
                      angle  => ($t->{angle} // 0));
    }
}

sub save {
    my ($self, $file, %opt) = @_;

    # dpi指定があれば幅・高さをスケールして高解像度PNGを生成する
    my $scale = 1.0;
    if (defined $opt{dpi}) {
        my $base_dpi = $self->dpi // 96;
        $scale = $opt{dpi} / $base_dpi;
    }

    my $driver = PDL::Graphics::Cairo::Driver::Cairo->new(
        width  => int($self->width  * $scale),
        height => int($self->height * $scale),
        scale  => $scale,
        file   => $file,
    );
    $self->_render_to($driver);
}

sub _default_backend {
    if ($^O eq 'darwin') {
        # ドライバ一本化: macOS ネイティブ表示は giza_server (/gs) に集約。
        # Driver::GS が giza_server を auto-spawn するので viewer 探索は不要。
        # 退役した Driver::OSX/pdlcairo_viewer は既定では使わない。
        # giza_server が起動中でもバイナリも見つからない時だけ gnuplot に
        # 退避する（giza-server 未ビルドの素のチェックアウトでも描けるよう保険）。
        require PDL::Graphics::Cairo::Driver::GS;
        return 'gs' if PDL::Graphics::Cairo::Driver::GS->_available;
    }
    return 'gnuplot';
}

# ------------------------------------------------------------------
# show(%opts) — gnuplot または OSX ネイティブ
# ------------------------------------------------------------------
sub show {
    my ($self, %opt) = @_;
#     my $backend = lc($opt{backend} // $ENV{PDLCAIRO_BACKEND} // 'gnuplot');
    my $backend = lc($opt{backend} // $ENV{PDLCAIRO_BACKEND} // _default_backend());

    if ($backend eq 'gs') {
        require PDL::Graphics::Cairo::Driver::GS;
        my $driver = PDL::Graphics::Cairo::Driver::GS->new(
            width  => $self->width,
            height => $self->height,
            title  => $opt{title} // 'PDL::Graphics::Cairo',
            start  => $opt{start} // 'auto',
        );
        $driver->show($self);
        return;
    }

    if ($backend eq 'osx') {
        require PDL::Graphics::Cairo::Driver::OSX;
        my $driver = PDL::Graphics::Cairo::Driver::OSX->new(
            width  => $self->width,
            height => $self->height,
            title  => $opt{title} // 'PDL::Graphics::Cairo',
            nowait => $opt{nowait} // 0,
            keep   => $opt{keep}   // 0,
        );
        $driver->show($self);
        return;
    }

    # 従来通り gnuplot
    my $driver = PDL::Graphics::Cairo::Driver::Gnuplot->new(
        width    => $self->width,
        height   => $self->height,
        terminal => $opt{terminal} // '',
        keep     => $opt{keep}     // 0,
    );
    $driver->show($self);
}



# ------------------------------------------------------------------
# add_axes($ax) — 既存の Axes を Figure に登録する。冪等: 登録済みの
# 同一オブジェクトは積まない(twinx/twiny は自動登録するので、重ねて
# 呼ばれても二重描画しない)。_figure が未設定なら張る。
# ------------------------------------------------------------------
sub add_axes {
    my ($self, $ax) = @_;
    push @{ $self->axes_list }, $ax
        unless grep { $_ == $ax } @{ $self->axes_list };
    $ax->_figure($self) unless $ax->_figure;
    return $self;
}

# ------------------------------------------------------------------
# savefig — save() matplotlib 
# ------------------------------------------------------------------
sub savefig {
    my ($self, $file, %opt) = @_;
    return $self->save($file, %opt);
}

# ------------------------------------------------------------------
# subplots_adjust(%opt)  — マージン手動調整 (matplotlib互換)
# left/right/top/bottom: 0-1のfraction座標 (left=0.1 → 10%余白)
# wspace/hspace: subplot間スペース(fraction of subplot幅/高さ)
# ------------------------------------------------------------------
sub subplots_adjust {
    my ($self, %opt) = @_;

    my $fw = $self->width;
    my $fh = $self->height;

    # fraction → pixel変換。matplotlib と同じ座標系:
    #   left/right: Figure幅に対する割合 (0=左端, 1=右端)
    #   top/bottom: Figure高さに対する割合 (0=下端, 1=上端) ← 注意: Figureのy
    my $left   = defined $opt{left}   ? int($opt{left}   * $fw) : undef;
    my $right  = defined $opt{right}  ? int($opt{right}  * $fw) : undef;
    my $bottom = defined $opt{bottom} ? int((1 - $opt{bottom}) * $fh) : undef;
    my $top    = defined $opt{top}    ? int((1 - $opt{top})    * $fh) : undef;

    my $nrows = $self->_nrows || 1;
    my $ncols = $self->_ncols || 1;

    # top 未指定時のデフォルト: suptitle() が設定されている場合、その分の
    # 余白(subplot()内のtop_padと同じ40px)を確保する。指定しないと
    # suptitleとパネル1のタイトルが重なってしまう。
    my $default_top = (($self->{_suptitle_text} // '') ne '') ? 40 : 0;

    my $area_left   = $left   // 0;
    my $area_top    = $top    // $default_top;
    my $area_right  = $right  // $fw;
    my $area_bottom = $bottom // $fh;

    my $wspace = $opt{wspace} // 0.2;
    my $hspace = $opt{hspace} // 0.2;

    my $total_w = $area_right - $area_left;
    my $total_h = $area_bottom - $area_top;

    # セル間ギャップをpxに変換
    my $cell_w = $total_w / ($ncols + ($ncols-1)*$wspace);
    my $cell_h = $total_h / ($nrows + ($nrows-1)*$hspace);
    my $gap_w  = $cell_w * $wspace;
    my $gap_h  = $cell_h * $hspace;

    my %gs_ax_set = map { $_ => 1 } map { $_->{ax} } @{ $self->_gs_axes };

    for my $ax (@{ $self->axes_list }) {
        next if $ax->_is_twin;
        next if $ax->_is_inset;
        next if $gs_ax_set{$ax};

        # 現在のfig_xからどの行・列かを逆引き
        my $col = ($ncols <= 1) ? 0
            : int(($ax->fig_x - $area_left + ($cell_w+$gap_w)*0.5) / ($cell_w+$gap_w));
        my $row = ($nrows <= 1) ? 0
            : int(($ax->fig_y - $area_top  + ($cell_h+$gap_h)*0.5) / ($cell_h+$gap_h));
        $col = 0 if $col < 0; $col = $ncols-1 if $col >= $ncols;
        $row = 0 if $row < 0; $row = $nrows-1 if $row >= $nrows;

        my $new_x = $area_left + $col * ($cell_w + $gap_w);
        my $new_y = $area_top  + $row * ($cell_h + $gap_h);

        $ax->{fig_x}  = $new_x;
        $ax->{fig_y}  = $new_y;
        $ax->{width}  = $cell_w;
        $ax->{height} = $cell_h;
    }

    $self->{_tight_done} = 1;  # tight_layout再実行を抑制
    return $self;
}

# ------------------------------------------------------------------
# Tick numbers on some panels only, for grids whose panels share their axes.
#
#   $fig->label_outer(%opt)       tick numbers of the y axis only on the
#                                 leftmost panel of each row, of the x axis
#                                 only on the lowest panel of each column
#                                 (matplotlib label_outer). Rows and columns
#                                 are found from the position of the panels,
#                                 so a grid with empty cells works: the lowest
#                                 panel of a column need not be in the last row.
#   $fig->label_only($ax, %opt)   tick numbers on $ax (or [$ax, ...]) only
#
#   axis => 'x' | 'y' | 'both' (default)
#   axes => [$ax, ...]   the panels to treat (default: every Axes of the figure
#                        but twins, insets, polar and axis('off') panels)
#
# The tick marks stay; only the numbers are switched (tick_params labelleft /
# labelbottom), on and off, so a later call replaces an earlier one.
# ------------------------------------------------------------------
sub _label_panels {
    my ($self, $opt) = @_;
    return @{ $opt->{axes} } if $opt->{axes};
    return grep {
        !$_->_is_twin && !$_->_is_inset && !$_->{_axis_off}
            && !$_->isa('PDL::Graphics::Cairo::PolarAxes')
    } @{ $self->axes_list };
}

sub _set_tick_numbers {
    my ($ax, $axis, $on) = @_;
    $ax->tick_params(axis => 'x', labelbottom => $on) if $axis ne 'y';
    $ax->tick_params(axis => 'y', labelleft   => $on) if $axis ne 'x';
}

sub label_only {
    my ($self, $keep, %opt) = @_;
    my $axis = $opt{axis} // 'both';
    my %keep = map { $_ => 1 } (ref $keep eq 'ARRAY' ? @$keep : ($keep));
    _set_tick_numbers($_, $axis, $keep{$_} ? 1 : 0) for $self->_label_panels(\%opt);
    return $self;
}

sub label_outer {
    my ($self, %opt) = @_;
    my $axis = $opt{axis} // 'both';
    my @ax   = $self->_label_panels(\%opt);
    # leftmost panel of each row (same top edge), lowest of each column (same left edge)
    my (%left, %low);
    for my $ax (@ax) {
        my ($row, $col) = (int($ax->fig_y + 0.5), int($ax->fig_x + 0.5));
        $left{$row} = $ax if !$left{$row} || $ax->fig_x < $left{$row}->fig_x;
        $low{$col}  = $ax if !$low{$col}  || $ax->fig_y > $low{$col}->fig_y;
    }
    my %is_left = map { $_ => 1 } values %left;
    my %is_low  = map { $_ => 1 } values %low;
    for my $ax (@ax) {
        _set_tick_numbers($ax, 'x', $is_low{$ax}  ? 1 : 0) if $axis ne 'y';
        _set_tick_numbers($ax, 'y', $is_left{$ax} ? 1 : 0) if $axis ne 'x';
    }
    return $self;
}

# ------------------------------------------------------------------
# set_facecolor($color)  — Figure背景色 (matplotlib互換)
# ------------------------------------------------------------------
sub set_facecolor {
    my ($self, $color) = @_;
    $self->{_facecolor} = $color;
    return $self;
}

# ------------------------------------------------------------------
# clf — Figure 
# ------------------------------------------------------------------
sub clf {
    my ($self) = @_;
    @{ $self->axes_list } = ();
    $self->{_connections} = [];
    $self->{_fig_texts}   = [];
    $self->suptitle('');
    return $self;
}

# ------------------------------------------------------------------
# tight_layout — subplot 
# ------------------------------------------------------------------
# _tight_gridspec(\@entries, $measurer, $room_of, $left, $top, $right, $bottom)
# Lays out the panels of one GridSpec inside the area (px) given. Each panel
# needs room around its plot rectangle: tick numbers, labels and title
# (Axes::_label_room), a twin's axis, a colorbar. A column gets on its left
# the largest need of the panels that start there and on its right the
# largest of those that end there (rows likewise, top and bottom); between
# two neighbouring columns the two needs add up, with GS_PAD px between them.
# What is left is shared among the columns (rows) by width_ratios
# (height_ratios). Each panel's plot rectangle is then exactly the span of
# its cells, so the plot rectangles of a row (column) line up, and its
# margins are its own needs.
# Returns false (and changes nothing) when the GridSpec has cell_margins, a
# polar panel or a panel placed with set_position, or when the plot
# rectangles would be smaller than GS_MIN px;
# tight_layout then falls back to margins inside the GridSpec's own cells.
# Up to 0.42 tight_layout kept the GridSpec's cells (left/right/top/bottom and
# hspace/wspace) and added its own fixed margins (60-72 px left, 36-66 px
# below, ...) inside each cell, so the gaps were both added and the figures
# of examples/example_gridspec.pl were mostly empty space.
use constant { GS_PAD => 10, GS_MIN => 40 };
sub _tight_gridspec {
    my ($ents, $meas, $room_of, $left, $top, $right, $bottom) = @_;
    my $gs = $ents->[0]{gs};
    return 0 if defined $gs->cell_margins;
    return 0 if grep { $_->{ax}{_position_set} } @$ents;   # placed with set_position
    return 0 if grep { $_->{ax}->isa('PDL::Graphics::Cairo::PolarAxes') } @$ents;
    my ($nr, $nc) = ($gs->nrows, $gs->ncols);

    # room each panel needs: (left, right, top, bottom)
    my %need;
    for my $e (@$ents) {
        my $ax = $e->{ax};
        my ($l, $r, $t, $b);
        if ($ax->{_axis_off}) {
            ($l, $r, $t, $b) = (2, 2, 2, 2);
        } else {
            my ($nl, $nb, $nt, $nrt) = $room_of->($ax);
            ($l, $r, $t, $b) = ($nl, $nrt, $nt, $nb);
            $r = 4 if $r < 4;           # the frame line and the last x tick number
            $t = 4 if $t < 4;
        }
        if ($ax->_colorbar && $ax->colorbar_reserve) {
            my $loc = $ax->colorbar_location // 'right';
            my $res = _cbar_reserve($ax);
            if    ($loc eq 'left')   { $l += $res }
            elsif ($loc eq 'top')    { $t += $res }
            elsif ($loc eq 'bottom') { $b += $res }
            else                     { $r += $res }
        }
        for my $twin (@{ $ax->_twin_axes }) {
            if (($twin->_twin_type // '') eq 'y') {
                $t += 36 + ($twin->xlabel ne '' ? 20 : 0);
            } else {
                $r += $twin->_twin_yaxis_room($meas);
            }
        }
        $need{$ax} = [ map { int($_ + 0.999) } $l, $r, $t, $b ];
    }

    # per column / row: the largest need on each side
    my (@cl, @cr, @rt, @rb);
    $cl[$_] = $cr[$_] = 0 for 0 .. $nc - 1;
    $rt[$_] = $rb[$_] = 0 for 0 .. $nr - 1;
    for my $e (@$ents) {
        my ($l, $r, $t, $b) = @{ $need{ $e->{ax} } };
        $cl[ $e->{c0} ]     = $l if $l > $cl[ $e->{c0} ];
        $cr[ $e->{c1} - 1 ] = $r if $r > $cr[ $e->{c1} - 1 ];
        $rt[ $e->{r0} ]     = $t if $t > $rt[ $e->{r0} ];
        $rb[ $e->{r1} - 1 ] = $b if $b > $rb[ $e->{r1} - 1 ];
    }

    # inner (plot rectangle) start and size of each column / row
    my $span = sub {
        my ($lo, $hi, $before, $after, $ratios, $n) = @_;
        my @rat = $ratios ? @$ratios : (1) x $n;
        my $deco = $before->[0] + $after->[$n - 1];
        $deco += $after->[$_] + GS_PAD + $before->[$_ + 1] for 0 .. $n - 2;
        my $avail = ($hi - $lo) - $deco;
        my $sum = 0; $sum += $_ for @rat;
        return unless $sum > 0 && $avail > 0;
        my @size = map { $avail * $_ / $sum } @rat;
        return if grep { $_ < GS_MIN } @size;
        my @start = ($lo + $before->[0]);
        push @start, $start[-1] + $size[$_] + $after->[$_] + GS_PAD + $before->[$_ + 1]
            for 0 .. $n - 2;
        # whole pixels, start and size each rounded: equal ratios give equal
        # sizes, and every panel ending on a column ends on the same pixel
        return ([ map { int($_ + 0.5) } @start ], [ map { int($_ + 0.5) } @size ]);
    };
    my ($cx, $cw) = $span->($left, $right,  \@cl, \@cr, $gs->width_ratios,  $nc);
    my ($ry, $rh) = $span->($top,  $bottom, \@rt, \@rb, $gs->height_ratios, $nr);
    return 0 unless $cx && $ry;

    for my $e (@$ents) {
        my $ax = $e->{ax};
        my ($l, $r, $t, $b) = @{ $need{$ax} };
        my $x0 = $cx->[ $e->{c0} ];
        my $x1 = $cx->[ $e->{c1} - 1 ] + $cw->[ $e->{c1} - 1 ];
        my $y0 = $ry->[ $e->{r0} ];
        my $y1 = $ry->[ $e->{r1} - 1 ] + $rh->[ $e->{r1} - 1 ];
        my ($px0, $px1, $py0, $py1) = ($x0, $x1, $y0, $y1);   # already whole pixels
        $ax->{fig_x}  = $px0 - $l;
        $ax->{fig_y}  = $py0 - $t;
        $ax->{width}  = ($px1 - $px0) + $l + $r;
        $ax->{height} = ($py1 - $py0) + $t + $b;
        $ax->margin_left($l);  $ax->margin_right($r);
        $ax->margin_top($t);   $ax->margin_bottom($b);
    }
    return 1;
}

sub tight_layout {
    my ($self, %opt) = @_;

    # pad: Figure  1.08 = 8%
    # h_pad: subplot px
    # w_pad: subplot px
    my $pad   = $opt{pad}   // 1.08;
    my $h_pad = $opt{h_pad} // 24;
    my $w_pad = $opt{w_pad} // 24;
    my $rect  = $opt{rect};

    my $nrows = $self->_nrows || 1;
    my $ncols = $self->_ncols || 1;
    my $fw    = $self->width;
    my $fh    = $self->height;

    # suptitle 
    my $top_pad = ($self->{_suptitle_text} // '') ne '' ? 36 : 8;

    # Figure pad  px 
    my $outer = int(($fw < $fh ? $fw : $fh) * ($pad - 1.0) * 0.5);
    $outer = 8 if $outer < 8;

    #

    my ($left, $bottom, $right, $top);
    if ($rect) {
        $left   = int($rect->[0] * $fw);
        $bottom = int((1 - $rect->[3]) * $fh);
        $right  = int($rect->[2] * $fw);
        $top    = int((1 - $rect->[1]) * $fh);
    } else {
        $left   = $outer;
        $top    = $outer + $top_pad;
        $right  = $fw - $outer;
        $bottom = $fh - $outer;
    }

    #

    # cell_w/cell_h: パネル本体のサイズ。h_pad/w_pad は隣接パネル間の
    # 「外枠から外枠までの隙間」(px)として確保する。
    # 例: nrows=2 なら 1箇所の縦ギャップ(h_pad)を差し引いた残りを
    # 2分割する。これにより上段パネルの margin_bottom(xlabel領域)と
    # 下段パネルの margin_top(title領域)が隙間なく隣接して重なる、
    # という不具合(2026-06-19 報告)を防ぐ。
    # 以前は h_pad/w_pad が定義されているだけで一切使われておらず、
    # 2行以上のレイアウトで上下パネルが詰まって重なる根本原因になっていた。
    my $cell_w = (($right - $left) - $w_pad * ($ncols - 1)) / $ncols;
    my $cell_h = (($bottom - $top) - $h_pad * ($nrows - 1)) / $nrows;

    #  Axes  margin 
    # Y Axes  margin_left 
    # X Axes  margin_bottom 
    # Build GS axes lookup for skip
    my %gs_ax_set = map { $_ => 1 } map { $_->{ax} } @{ $self->_gs_axes };

    # uniform_margins => 1 用の事前走査:
    # 「全パネルで同じマージンに揃える」が目的のオプションなので、
    # グリッド内のどのパネルかに関わらず、ylabel/xlabel を持つパネルが
    # 1つでもあれば全パネルで同じだけマージンを広げる。
    # （列/行ごとに ylabel 有無で個別判定すると、ylabel のある列/行だけ
    #   プロット領域が狭くなり、グリッド全体が不均一に見えてしまうため。
    #   5x5 EEGグリッドで左列のみylabelを付けた際に左列だけ幅が狭くなる
    #   不具合の修正。）
    my $grid_has_ylabel = 0;
    my $grid_has_xlabel = 0;
    if ($opt{uniform_margins}) {
        for my $ax (@{ $self->axes_list }) {
            $grid_has_ylabel = 1 if $ax->ylabel ne '';
            $grid_has_xlabel = 1 if $ax->xlabel ne '';
        }
    }

    # 目盛り数字・xlabel・ylabel・title が枠の外に要る幅を実測する
    # (Axes::_label_room)。下の固定値(70px など)とセルの大きさに比例した
    # 縮小は、この実測値を下回らない範囲で使う。以前は固定値だけで決めて
    # いたため、目盛り数字が長い(2.00e+04 など)と ylabel が図の外に出て
    # 見えず、高さの低い図では xlabel が下端で切れていた。
    # 測るための Cairo は 1x1 の画像面で、描画と同じフォント(rcParams)を使う。
    my %room;    # Axes => [left, bottom, top]
    my $level = $opt{uniform_margins} ? 1 : 0;
    my $meas = _measure_driver();    # also used for a twinx's right axis below
    if (my $m = $meas) {
        for my $ax (@{ $self->axes_list }) {
            next if $ax->_is_twin || $ax->_is_inset
                 || $ax->isa('PDL::Graphics::Cairo::PolarAxes');
            $room{$ax} = [ $ax->_label_room($m, $gs_ax_set{$ax} ? 0 : $level) ];
        }
    }
    # uniform_margins: 全パネルで同じマージンにするので、最大値を全員に使う
    my @room_max = (0, 0, 0, 0);
    if ($opt{uniform_margins}) {
        for my $r (values %room) {
            for my $k (0..3) { $room_max[$k] = $r->[$k] if $r->[$k] > $room_max[$k] }
        }
    }
    # (left, bottom, top, right); right is the column of a legend outside the
    # frame, added to the right margin.
    my $room_of = sub {
        my ($ax) = @_;
        my $r = $room{$ax} or return (0, 0, 0, 0);
        return $opt{uniform_margins} && !$gs_ax_set{$ax} ? @room_max : @$r;
    };

    # GridSpec / subplot_mosaic: place the cells from what each panel needs
    # around its plot rectangle (as matplotlib's tight_layout, which replaces
    # the GridSpec's left/right/top/bottom/hspace/wspace). Not for a GridSpec
    # with cell_margins (fixed margins asked for) or with polar panels.
    # Only on an explicit $fig->tight_layout: when save/show apply it by
    # themselves, a GridSpec keeps the left/right/.../hspace/wspace it was
    # given (scripts that place their panels with GridSpec bounds or
    # set_position rely on that, as with matplotlib, which never applies
    # tight_layout unasked).
    my %gs_done;
    if ($meas && !$opt{_auto}) {
        my %by_gs;
        for my $e (@{ $self->_gs_axes }) {
            push @{ $by_gs{ $e->{gs} } }, $e;
        }
        for my $ents (values %by_gs) {
            my $done = _tight_gridspec($ents, $meas, $room_of,
                $left, $top, $right, $bottom) or next;
            $gs_done{ $_->{ax} } = 1 for @$ents;
        }
    }

    for my $ax (@{ $self->axes_list }) {
        # twinx/twiny の戻り値(twin object): マージンは draw() 内で
        # 親(_twin_of)と常に揃えられるため、ここでの個別計算は不要。
        # 親側のマージン計算で twin の存在(上側 or 右側の追加余白)を
        # 考慮するので、ここでは何もせずスキップする。
        if ($ax->_is_twin) {
            next;
        }

        # PolarAxes: 独自の描画ロジックを持つのでマージン計算不要
        if ($ax->isa('PDL::Graphics::Cairo::PolarAxes')) {
            next;
        }

        # Inset axes: fixed position, use minimal margins
        if ($ax->_is_inset) {
            $ax->margin_left(28);  $ax->margin_right(8);
            $ax->margin_bottom(24); $ax->margin_top(12);
            next;
        }

        # GridSpec Axes: position already set, just compute margins
        if ($gs_ax_set{$ax}) {
            next if $gs_done{$ax};     # placed by _tight_gridspec
            # cell_margins: the same fixed margins for every Axes of the GridSpec.
            # A colorbar takes its room from the plot rectangle on its side,
            # unless it was attached with reserve => 0.
            my ($cm_info) = grep { $_->{ax} == $ax } @{ $self->_gs_axes };
            if (my ($ml, $mr, $mt, $mb) = $cm_info->{gs}->cell_margins_px) {
                if ($ax->_colorbar_shown && $ax->colorbar_reserve) {
                    my $loc = $ax->colorbar_location // 'right';
                    my $res = _cbar_reserve($ax);
                    if    ($loc eq 'left')   { $ml += $res }
                    elsif ($loc eq 'top')    { $mt += $res }
                    elsif ($loc eq 'bottom') { $mb += $res }
                    else                     { $mr += $res }
                }
                ($ml, $mr, $mt, $mb) = _fit_margins($ax, $ml, $mr, $mt, $mb);
                $ax->margin_left($ml);   $ax->margin_right($mr);
                $ax->margin_bottom($mb); $ax->margin_top($mt);
                next;
            }
            # 軸OFF: 目盛り/枠/ラベルを描かないのでマージン不要。カラーバー分のみ実寸確保。
            if ($ax->{_axis_off}) {
                my ($ml,$mr,$mt,$mb) = (2,2,2,2);
                if ($ax->_colorbar && $ax->colorbar_reserve) {
                    my $loc = $ax->colorbar_location // 'right';
                    my $res = _cbar_reserve($ax);
                    if    ($loc eq 'right')  { $mr = $res }
                    elsif ($loc eq 'left')   { $ml = $res }
                    elsif ($loc eq 'top')    { $mt = $res }
                    elsif ($loc eq 'bottom') { $mb = $res }
                    else                     { $mr = $res }
                }
                ($ml, $mr, $mt, $mb) = _fit_margins($ax, $ml, $mr, $mt, $mb);
                $ax->margin_left($ml);  $ax->margin_right($mr);
                $ax->margin_bottom($mb); $ax->margin_top($mt);
                next;
            }
            # find gs info
            my ($gsinfo) = grep { $_->{ax} == $ax } @{ $self->_gs_axes };
            my $gs   = $gsinfo->{gs};
            my $r0   = $gsinfo->{r0};
            my $r1   = $gsinfo->{r1};
            my $c0   = $gsinfo->{c0};
            my $nr   = $gs->nrows;
            my $nc   = $gs->ncols;
            # Cell pixel size from GridSpec
            my ($gx,$gy,$gw,$gh) = ($ax->fig_x, $ax->fig_y, $ax->width, $ax->height);
            my $ml = ($c0 == 0 ? 60 : 44);
            $ml = 72 if $ax->ylabel ne '';
            $ml = int($ml * 0.75) if $gw < 200;
            my $mb = ($r1 == $nr ? 58 : 36);
            $mb = 66 if $ax->xlabel ne '';
            $mb = int($mb * 0.8) if $gh < 150;
            my $mt = $ax->title ne '' ? 34 : 18;
            $mt = 44 if $r0 == 0 && ($self->{_suptitle_text} // '') ne '';
            my $mr = 14;
            my ($need_l, $need_b, $need_t, $need_r) = $room_of->($ax);
            $ml = $need_l if $need_l > $ml;
            $mb = $need_b if $need_b > $mb;
            $mt = $need_t if $need_t > $mt;
            # colorbar_location に応じて、実際にcolorbarが描かれる側の
            # マージンを拡張する。以前は colorbar の有無だけで常に mr
            # (右マージン)を拡張していたため、location=>'left'/'top'/
            # 'bottom' を指定してもその側のマージンが確保されず、
            # colorbar がylabel領域やfigure外にはみ出す不具合があった。
            if ($ax->_colorbar && $ax->colorbar_reserve) {
                my $cbloc = $ax->colorbar_location // 'right';
                my $res   = _cbar_reserve($ax);            # 固定68/75/50 → 実寸見積り
                if    ($cbloc eq 'right')  { $mr = $res; }
                elsif ($cbloc eq 'left')   { $ml += $res; }
                elsif ($cbloc eq 'top')    { $mt += $res; }
                elsif ($cbloc eq 'bottom') { $mb += $res; }
                else                       { $mr = $res; }
            }
            # legend(loc=>'outside right') の列(colorbar より外側)
            $mr += $need_r;
            # カスタム y 目盛りラベルが margin_left に収まるよう下限を確保
            # (主経路と同じ。tight_layout は描画前で text_width 実測不可)。
            if ($ax->_yticklabels && @{ $ax->_yticklabels }) {
                my $lsize = $ax->_tick_params->{y_labelsize} // 10;
                my $need  = 0;
                for my $lab (@{ $ax->_yticklabels }) {
                    my $w = estimate_max_line_px($lab, $lsize);
                    $need = $w if $w > $need;
                }
                $need = int($need + 0.5) + 15;
                $ml   = $need if $need > $ml;
            }
            ($ml, $mr, $mt, $mb) = _fit_margins($ax, $ml, $mr, $mt, $mb);
            $ax->margin_left($ml);  $ax->margin_right($mr);
            $ax->margin_bottom($mb); $ax->margin_top($mt);
            next;
        }
        # Axes  fig_x/fig_y 
        # (cell_w+w_pad)/(cell_h+h_pad) を1セル分の周期として逆算する。
        my $col = int(($ax->fig_x - $left + ($cell_w+$w_pad) * 0.5) / ($cell_w+$w_pad));
        my $row = int(($ax->fig_y - $top  + ($cell_h+$h_pad) * 0.5) / ($cell_h+$h_pad));
        $col = 0 if $col < 0; $col = $ncols-1 if $col >= $ncols;
        $row = 0 if $row < 0; $row = $nrows-1 if $row >= $nrows;

        # マージン基準値をセルサイズに比例させる（多パネル時の隙間を削減）
        my $scale_h = $cell_h < 120 ? $cell_h / 120.0 : 1.0;
        my $scale_w = $cell_w < 160 ? $cell_w / 160.0 : 1.0;

        # 左マージン: Y軸ラベル有無で変化
        # uniform_margins => 1: 内側値で全パネルを揃える（外縁余白はpadで確保）
        # 注意: uniform_margins 指定時は個別 Axes の ylabel 有無ではなく
        # グリッド全体の有無（事前走査した $grid_has_ylabel）で判定する。
        # これにより、ylabel を一部のパネルにしか付けていなくても
        # グリッド全体で同じマージンが確保され、列ごとの幅の不均一を防ぐ。
        my $ml = ($opt{uniform_margins})
            ? int(36 * $scale_w + 0.5)
            : ($col == 0 ? int(56 * $scale_w + 0.5) : int(36 * $scale_w + 0.5));
        if ($opt{uniform_margins}) {
            # uniform_margins 時は単一figure用の固定値(70px)ではなく、
            # 縦書きylabel+tickラベルが収まる実用上の最小値に近い値を使う。
            # 70px のままだとパネルが小さい多パネルグリッド(5x5等)で
            # 隙間が不必要に広がり、空間効率が悪化する。
            $ml = int(52 * $scale_w + 0.5) if $grid_has_ylabel;
        } else {
            $ml = int(70 * $scale_w + 0.5) if $ax->ylabel ne '';
        }
        $ml = 28 if $ml < 28;   # 最小値

        # カスタム y 目盛りラベル (yticks(vals,labels) / set_yticklabels) が
        # 固定ヒューリスティック margin_left に収まらず左端で切れるのを防ぐ。
        # tight_layout は描画前に走り backend($b)が無いため text_width を
        # 実測できないので、最長行の文字数からラベル占有幅を見積もり、
        # それを下回らないよう margin_left の下限を引き上げる。
        # 複数行ラベル "name\n(scale)" は estimate_max_line_px が最長行で
        # 評価するので、横方向は単一行と同じ扱いになる (縦の重なりは別問題で
        # 呼び出し側が行数を制御する)。
        if ($ax->_yticklabels && @{ $ax->_yticklabels }) {
            my $lsize = $ax->_tick_params->{y_labelsize} // 10;
            my $need  = 0;
            for my $lab (@{ $ax->_yticklabels }) {
                my $w = estimate_max_line_px($lab, $lsize);
                $need = $w if $w > $need;
            }
            # tick_ext(~3) + y_pad(~10) + 2 + 予備 の合計 ~15px を上乗せ。
            $need = int($need + 0.5) + 15;
            $ml   = $need if $need > $ml;
        }

        # 右マージン
        my $mr = $ax->_colorbar ? 72 : (exists $ax->{_right_ylabel} && $ax->{_right_ylabel} ne "") ? 110 : int(10 * $scale_w + 8);

        # uniform_margins 時、title/xlabel のフォントと固定オフセットを
        # 縮小する「コンパクトモード」を有効化する（_draw_labels側で使用）。
        # これにより mt+mb の合計を 90px→78px 程度まで圧縮できる。
        $ax->_compact_labels($opt{uniform_margins} ? 1 : 0);

        # 下マージン: X軸ラベル有無で変化（uniform_margins時はグリッド全体で判定）
        my $mb = ($opt{uniform_margins})
            ? int(28 * $scale_h + 0.5)
            : ($row == $nrows-1 ? int(48 * $scale_h + 0.5) : int(28 * $scale_h + 0.5));
        if ($opt{uniform_margins}) {
            # コンパクトモードの xlabel は plot_bottom+38 の位置、
            # フォント9pt(高さ≈11px)+視覚的余白(4px)を加えた53pxが必要量。
            # （詳細は _draw_labels のコンパクト分岐コメントを参照）
            $mb = int(53 * $scale_h + 0.5) if $grid_has_xlabel;
        } else {
            $mb = int(56 * $scale_h + 0.5) if $ax->xlabel ne '';
        }
        $mb = 20 if $mb < 20;

        # 上マージン: タイトル有無で変化
        # uniform_margins 時はコンパクトモードのタイトル
        # (オフセット11+フォント11pt高さ≈14px)で 25px 程度が必要量。
        my $mt = $ax->title ne ''
            ? int(($opt{uniform_margins} ? 25 : 32) * $scale_h + 0.5)
            : int(16 * $scale_h + 0.5);
        $mt = int(40 * $scale_h + 0.5) if $row == 0 && $self->_suptitle_text ne '';
        $mt = 12 if $mt < 12;

        # 実測した文字の必要量を下限にする(上の %room のコメント参照)。
        # 図の外周に接するパネルは、外周の余白(pad、既定 8 px)まで文字が
        # 入ってよいので、その分を差し引く(_label_room は端に 2 px 残す)。
        # suptitle 用の上の余白は差し引かない。uniform_margins では全パネルを
        # 同じにするので差し引かない。
        {
            my ($need_l, $need_b, $need_t) = $room_of->($ax);
            unless ($opt{uniform_margins}) {
                $need_l -= $left            if $col == 0;
                $need_b -= ($fh - $bottom)  if $row == $nrows - 1;
                $need_t -= $outer           if $row == 0 && !$rect;
            }
            $ml = $need_l if $need_l > $ml;
            $mb = $need_b if $need_b > $mb;
            $mt = $need_t if $need_t > $mt;
        }

        # colorbar_location に応じて、実際にcolorbarが描かれる側の
        # マージンを拡張する。以前は colorbar の有無だけで mr(右マージン)
        # を常に拡張していたため(上の $mr 計算)、location=>'left'/'top'/
        # 'bottom' を指定してもその側のマージンが確保されず、colorbar が
        # ylabel領域やfigure外にはみ出す不具合があった。
        # mr は既に colorbar 用に72px確保されているので、right以外の
        # location時はそれを通常値に戻し、該当する側を拡張する。
        if ($ax->_colorbar) {
            my $cbloc = $ax->colorbar_location // 'right';
            my $extra = ($ax->colorbar_label // '') ne '' ? 40 : 0;
            if ($cbloc eq 'left') {
                $mr = int(10 * $scale_w + 8);  # right側はcolorbar不要なので通常値に戻す
                # 68px ではcolorbar本体がY軸数値ラベルと数px差しかなく
                # 重なって見える不具合があったため75pxに調整
                # （_draw_colorbar側のcx計算 ml-47-pad-cw との組み合わせで
                #   Y軸数値ラベルから安全マージンを確保する）
                $ml += 75 + $extra;
            } elsif ($cbloc eq 'top') {
                $mr = int(10 * $scale_w + 8);
                $mt += 50 + $extra;
            } elsif ($cbloc eq 'bottom') {
                $mr = int(10 * $scale_w + 8);
                $mb += 50 + $extra;
            } else {  # right (デフォルト)
                $mr += $extra;
            }
            warn sprintf("[DEBUG tight_layout colorbar] cbloc=%s ml=%s mr=%s mt=%s mb=%s\n",
                $cbloc, $ml, $mr, $mt, $mb) if $ENV{PGC_DEBUG_LABELS};
        }

        # twinx()/twiny() が呼ばれている場合、第2軸(上のX軸 or 右のY軸)
        # 用のスペースをこの親のマージンに追加で確保する。
        # tight_layout は twin オブジェクト自体をスキップする
        # (上の "if ($ax->_is_twin) { next; }" 参照)ため、第2軸の余白は
        # 必ず親側のマージン計算で確保しなければならない。
        # 以前はこの処理が一切なく、twin の第2軸目盛り・ラベルが
        # タイトルや反対側のY軸ラベルと重なる不具合があった。
        # _twin_axes は1つの親に対してtwinx()/twiny()を両方呼んだ場合
        # 両方のtwinオブジェクトを保持する配列。
        for my $twin (@{ $ax->_twin_axes }) {
            my $twin_type = $twin->_twin_type // '';
            if ($twin_type eq 'y') {
                # twiny: 上に第2X軸の目盛り(約16px)+ラベル(約20px)
                $mt += 36 + ($twin->xlabel ne '' ? 20 : 0);
            } else {
                # twinx: 右に第2Y軸の目盛り数値と右ラベル。描画
                # (_draw_twin_yaxis)と同じ式で実測する(_twin_yaxis_room)。
                # 0.42 までは固定の 36px(+ ylabel なら 20px)で、
                # set_right_ylabel のラベル分を数えていなかった。
                $mr += $meas ? $twin->_twin_yaxis_room($meas)
                             : 36 + ($twin->_twin_ylabel_text ne '' ? 20 : 0);
            }
            warn sprintf("[DEBUG tight_layout twin] twin_type=%s mt=%s mr=%s twin_xlabel='%s'\n",
                $twin_type, $mt, $mr, $twin->xlabel) if $ENV{PGC_DEBUG_LABELS};
        }

        # legend(loc=>'outside right') の列。colorbar や twinx の目盛りの
        # さらに外側に置くので、それらを足した後で加える。
        $mr += ($room_of->($ax))[3];

        # cell が小さいとき margin が描画域を食い尽くして $mt>$mb/$ml>$mr になる。
        # X/Y それぞれ合計が cell の 80% を超えないようクランプする。
        my $max_h = $cell_h * 0.80;
        my $max_w = $cell_w * 0.80;
        if ($mt + $mb > $max_h) {
            my $scale = $max_h / ($mt + $mb);
            $mt = int($mt * $scale);
            $mb = int($mb * $scale);
        }
        if ($ml + $mr > $max_w) {
            my $scale = $max_w / ($ml + $mr);
            $ml = int($ml * $scale);
            $mr = int($mr * $scale);
        }

        $ax->margin_left($ml);
        $ax->margin_right($mr);
        $ax->margin_bottom($mb);
        $ax->margin_top($mt);

        # Axes 
        # (cell_w+w_pad)/(cell_h+h_pad) を1セル分の周期として配置する。
        my $new_x = $left + $col * ($cell_w + $w_pad);
        my $new_y = $top  + $row * ($cell_h + $h_pad);
        # fig_x/fig_y  ro 
        $ax->{fig_x}  = $new_x;
        $ax->{fig_y}  = $new_y;
        $ax->{width}  = $cell_w;
        $ax->{height} = $cell_h;
    }

    $self->{_tight_done} = 1;
    return $self;
}


# --- inline display for App-PDL-Notebook -----------------------------------
sub to_svg { $_[0]->_inline_bytes('svg') }
sub to_png { $_[0]->_inline_bytes('png') }

sub _inline_bytes {
    my ($self, $ext) = @_;
    require File::Temp;
    my ($fh, $fn) = File::Temp::tempfile(SUFFIX => ".$ext", UNLINK => 1);
    close $fh;
    $self->save($fn);
    open my $r, '<:raw', $fn or die "read $fn: $!";
    local $/;
    my $bytes = <$r>;
    close $r;
    return $bytes;
}

# raster-heavy plot types bloat as SVG; prefer PNG when the figure has one
my %RASTER = map { $_ => 1 } qw(imshow contourf pcolor pcolormesh);

sub _prefers_raster {
    my ($self) = @_;
    for my $ax (@{ $self->axes_list }) {
        for my $item (@{ $ax->_queue }) {
            return 1 if $RASTER{ $item->{type} // '' };
        }
    }
    return 0;
}

sub to_inline {
    my ($self) = @_;
    return $self->_prefers_raster
        ? ('image/png',     $self->to_png)
        : ('image/svg+xml', $self->to_svg);
}


# ==============================================================
# Reactive API — App::PDL::Notebook::Reactive との橋渡し
#
# ノートブック内で:
#   my $freq = $fig->param('freq', 1.0, min=>0.1, max=>5.0, label=>'Frequency');
#   $fig->on_change(sub { my ($name,$val)=@_; $ax->clear; ... });
#
# スタンドアロン（ノートブック外）では何もしない（die しない）。
# ==============================================================
sub param {
    my ($self, $name, $default, %opt) = @_;
    return $default unless _reactive_ok();
    return App::PDL::Notebook::Reactive::param($name, $default, %opt);
}

sub button {
    my ($self, $name, %opt) = @_;
    return unless _reactive_ok();
    App::PDL::Notebook::Reactive::button($name, %opt);
    return;
}

sub on_change {
    my ($self, $cb, $group) = @_;
    return unless _reactive_ok();
    App::PDL::Notebook::Reactive::on_change($cb, $group);
    return;
}

sub _reactive_ok {
    return eval { require App::PDL::Notebook::Reactive; 1 } ? 1 : 0;
}

1;
