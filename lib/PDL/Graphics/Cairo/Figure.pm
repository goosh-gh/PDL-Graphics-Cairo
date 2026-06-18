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
use PDL::Graphics::Cairo::Driver::Cairo;
use PDL::Graphics::Cairo::Driver::Gnuplot;

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
    elsif ($nrows == 1) {
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
    my ($self, $nrows_or_cell, $ncols, $idx) = @_;
    if (ref($nrows_or_cell) && $nrows_or_cell->isa('PDL::Graphics::Cairo::GridSpecCell')) {
        my $cell = $nrows_or_cell;
        my ($fig_x, $fig_y, $w, $h) = $cell->pixel_rect;
        my $ax = PDL::Graphics::Cairo::Axes->new(
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
    $self->tight_layout() unless $self->{_tight_done};
    for my $ax (@{ $self->axes_list }) {
        $ax->draw($driver);
    }

    $driver->finish();
}

sub save {
    my ($self, $file) = @_;

    my $driver = PDL::Graphics::Cairo::Driver::Cairo->new(
        width  => $self->width,
        height => $self->height,
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
# add_axes($ax) — twinx  Axes 
# ------------------------------------------------------------------
sub add_axes {
    my ($self, $ax) = @_;
    push @{ $self->axes_list }, $ax;
    return $self;
}

# ------------------------------------------------------------------
# savefig — save() matplotlib 
# ------------------------------------------------------------------
sub savefig { goto &save }

# ------------------------------------------------------------------
# clf — Figure 
# ------------------------------------------------------------------
sub clf {
    my ($self) = @_;
    @{ $self->axes_list } = ();
    $self->suptitle('');
    return $self;
}

# ------------------------------------------------------------------
# tight_layout — subplot 
# ------------------------------------------------------------------
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

    my $cell_w = ($right - $left) / $ncols;
    my $cell_h = ($bottom - $top) / $nrows;

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

    for my $ax (@{ $self->axes_list }) {
        # twinx/twiny の戻り値(twin object): マージンは draw() 内で
        # 親(_twin_of)と常に揃えられるため、ここでの個別計算は不要。
        # 親側のマージン計算で twin の存在(上側 or 右側の追加余白)を
        # 考慮するので、ここでは何もせずスキップする。
        if ($ax->_is_twin) {
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
            # colorbar_location に応じて、実際にcolorbarが描かれる側の
            # マージンを拡張する。以前は colorbar の有無だけで常に mr
            # (右マージン)を拡張していたため、location=>'left'/'top'/
            # 'bottom' を指定してもその側のマージンが確保されず、
            # colorbar がylabel領域やfigure外にはみ出す不具合があった。
            if ($ax->_colorbar) {
                my $cbloc = $ax->colorbar_location // 'right';
                my $extra = ($ax->colorbar_label // '') ne '' ? 40 : 0; # label分の追加余白
                if    ($cbloc eq 'right')  { $mr = 68 + $extra; }
                elsif ($cbloc eq 'left')   { $ml += 75 + $extra; }
                elsif ($cbloc eq 'top')    { $mt += 50 + $extra; }
                elsif ($cbloc eq 'bottom') { $mb += 50 + $extra; }
                else                       { $mr = 68 + $extra; }
            }
            $ax->margin_left($ml);  $ax->margin_right($mr);
            $ax->margin_bottom($mb); $ax->margin_top($mt);
            next;
        }
        # Axes  fig_x/fig_y 
        my $col = int(($ax->fig_x - $left + $cell_w * 0.5) / $cell_w);
        my $row = int(($ax->fig_y - $top  + $cell_h * 0.5) / $cell_h);
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
                # twinx: 右に第2Y軸の目盛り数値(約36px)+ラベル(約20px)
                $mr += 36 + ($twin->ylabel ne '' ? 20 : 0);
            }
            warn sprintf("[DEBUG tight_layout twin] twin_type=%s mt=%s mr=%s twin_xlabel='%s'\n",
                $twin_type, $mt, $mr, $twin->xlabel) if $ENV{PGC_DEBUG_LABELS};
        }

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
        my $new_x = $left + $col * $cell_w;
        my $new_y = $top  + $row * $cell_h;
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
