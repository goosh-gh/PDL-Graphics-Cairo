package PDL::Graphics::Cairo::PGPLOT;

# =============================================================
# PDL::Graphics::Cairo::PGPLOT
#
# PGPLOT  —  PGPLOT 
# PDL::Graphics::Cairo 
#
# :
#   cpgbeg / cpgopen / cpgend / cpgclos / cpgpage / cpgsubp
#   cpgenv / cpgswin / cpgsvp / cpgvstd / cpgvstd
#   cpglab / cpgmtxt
#   cpgline / cpgmove / cpgdraw / cpgpoly / cpgrect
#   cpgpt / cpgpt1
#   cpgsci / cpgscr / cpgslw / cpgsls / cpgsch
#   cpgerry / cpgerrx / cpgerr1
#   cpghist / cpgbin
#   cpggray / cpgimag / cpgwedg / cpgctab
#   cpgcont / cpgconf
#   cpgbbuf / cpgebuf / cpgupdt
#   cpgqwin / cpgqvp / cpgqvsz / cpgqci / cpgqch / cpgqlw / cpgqls
#   cpgiden / cpgask / cpgpap
#   cpgtext / cpgptxt
#
# :
#   "/OSX"   → Driver::Gnuplot (aqua)
#   "/X11"   → Driver::Gnuplot (x11)
#   "/XWIN"  → Driver::Gnuplot (x11)
#   "/WXT"   → Driver::Gnuplot (wxt)
#   "/PNG"   → Driver::Cairo (PNG )
#   "/PDF"   → Driver::Cairo (PDF )
#   "/SVG"   → Driver::Cairo (SVG )
#   "file.png/PNG" → file.png 
#   "file.pdf/PDF" → file.pdf 
#
# :
#   use PDL::Graphics::Cairo::PGPLOT;
#   cpgbeg(0, "/OSX", 1, 1);
#   cpgenv(0.0, 10.0, -1.0, 1.0, 0, 0);
#   cpglab("x", "y", "sin(x)");
#   cpgline($n, $x, $y);
#   cpgend();
# =============================================================

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure);
use Exporter 'import';

our $VERSION = '0.10';

#

our @EXPORT = qw(
    cpgbeg cpgopen cpgend cpgclos cpgpage cpgsubp
    cpgenv cpgswin cpgsvp cpgvstd cpgvsiz cpgpap
    cpglab cpgmtxt cpgtext cpgptxt
    cpgline cpgmove cpgdraw cpgpoly cpgrect
    cpgpt  cpgpt1  cpgarro cpgcirc
    cpgsci cpgscr  cpgshls cpgslw cpgsls cpgsch cpgscf cpgsfs cpgscrl
    cpgsah cpgsave cpgunsa
    cpgerry cpgerrx cpgerr1 cpgerrb
    cpghist cpgbin
    cpggray cpgimag cpgwedg cpgctab cpgsitf
    cpgcont cpgconf cpgconb cpgcons
    cpgbbuf cpgebuf cpgupdt cpgeras
    cpgqwin cpgqvp  cpgqvsz cpgqci  cpgqch  cpgqlw  cpgqls
    cpgqcf  cpgqfs  cpgqcr  cpgqcs  cpgqah  cpgqhs  cpgqinf
    cpgiden cpgask  cpgrnd  cpgrnge cpgnumb
    cpgband cpgcurs cpgncur cpglcur
    cpgsvp  cpgvp   cpgwnad

    pgbeg pgopen pgend pgclos pgpage pgsubp pgpanl
    pgenv pgswin pgsvp pgvstd pgvsiz pgpap pgwnad
    pglab pgmtxt pgtext pgptxt
    pgline pgmove pgdraw pgpoly pgrect
    pgpt  pgpt1  pgarro pgcirc
    pgsci pgscr  pgshls pgslw pgsls pgsch pgscf pgsfs pgscrl
    pgsah pgsave pgunsa
    pgerry pgerrx pgerr1 pgerrb
    pghist pgbin
    pggray pgimag pgwedg pgctab pgsitf
    pgcont pgconf pgconb pgcons
    pgbbuf pgebuf pgupdt pgeras
    pgqwin pgqvp  pgqvsz pgqci  pgqch  pgqlw  pgqls
    pgqcf  pgqfs  pgqcr  pgqcs  pgqah  pgqhs  pgqinf
    pgiden pgask  pgrnd  pgrnge pgnumb
    pgband pgcurs pgncur pglcur pgvp

    pgbegin pgclose pgpoint pgpoints pglabel pgvect
    cpgbox pgbox
);

# pg cpg — PDL::Graphics::PGPLOT 
our @EXPORT_OK = qw(
    pgbeg pgopen pgend pgclos pgpage pgsubp
    pgenv pgswin pgsvp pgvstd pgvsiz pgpap
    pglab pgmtxt pgtext pgptxt
    pgline pgmove pgdraw pgpoly pgrect
    pgpt  pgpt1  pgarro pgcirc
    pgsci pgscr  pgshls pgslw pgsls pgsch pgscf pgsfs pgscrl
    pgsah pgsave pgunsa
    pgerry pgerrx pgerr1 pgerrb
    pghist pgbin
    pggray pgimag pgwedg pgctab pgsitf
    pgcont pgconf pgconb pgcons
    pgbbuf pgebuf pgupdt pgeras
    pgqwin pgqvp  pgqvsz pgqci  pgqch  pgqlw  pgqls
    pgqcf  pgqfs  pgqcr  pgqcs  pgqah  pgqhs  pgqinf
    pgiden pgask  pgrnd  pgrnge pgnumb
    pgband pgcurs pgncur pglcur
    pgsvp  pgvp   pgwnad
    pgbegin pgclose pgpoint pgpoints pglabel pgvect
    cpgbox pgbox
);

# :pg  pg 
our %EXPORT_TAGS = (
    pg  => \@EXPORT_OK,
    cpg => \@EXPORT,
    all => [@EXPORT, @EXPORT_OK],
);

# =============================================================
#

# =============================================================

my %_state = (
    fig          => undef,
    axes         => [],
    current_ax   => undef,
    device       => '',
    outfile      => undef,
    interactive  => 0,
    terminal     => 'aqua',
    width        => 600,
    height       => 500,
    nxsub        => 1,
    nysub        => 1,
    panel_idx    => 0,
    #

    ci           => 1,         # color index
    lw           => 1,         # line width
    ls           => 1,         # line style (1=solid)
    ch           => 1.0,       # character height
    cf           => 1,         # character font (1=normal)
    fs           => 1,         # fill style
    #

    xmin => 0, xmax => 1, ymin => 0, ymax => 1,
    y_reversed   => 0,
    background   => 'white',    # PGPLOT_BACKGROUND
    # viewport (normalized)
    vxmin => 0.1, vxmax => 0.9, vymin => 0.1, vymax => 0.9,
    #

    buffering    => 0,
    # ask
    ask          => 0,
    # world 
    pen_x => 0, pen_y => 0,
);

# PGPLOT color index → RGB
# CI=0: background color, CI=1: foreground (opposite of background)
# Background is determined at runtime via _PDLCAIRO_PGBG (set by cpgopen).
# This way the Cairo API (figure/save) is never affected.
my @_CI_COLORS_WHITE = (
    [1.000, 1.000, 1.000],   # 0: white background
    [0.000, 0.000, 0.000],   # 1: black foreground
);
my @_CI_COLORS_BLACK = (
    [0.000, 0.000, 0.000],   # 0: black background
    [1.000, 1.000, 1.000],   # 1: white foreground
);
my @_CI_COLORS = (
    # 0: background (resolved at runtime via _ci_to_rgb)
    [1.000, 1.000, 1.000],
    # 1: foreground
    [0.000, 0.000, 0.000],
    # 2: red
    [1.000, 0.000, 0.000],
    # 3: green
    [0.000, 1.000, 0.000],
    # 4: blue
    [0.000, 0.000, 1.000],
    # 5: cyan
    [0.000, 1.000, 1.000],
    # 6: magenta
    [1.000, 0.000, 1.000],
    # 7: yellow
    [1.000, 1.000, 0.000],
    # 8: orange
    [1.000, 0.500, 0.000],
    # 9: yellow-green
    [0.500, 1.000, 0.000],
    # 10: green-cyan
    [0.000, 1.000, 0.500],
    # 11: blue-cyan
    [0.000, 0.500, 1.000],
    # 12: blue-magenta
    [0.500, 0.000, 1.000],
    # 13: red-magenta
    [1.000, 0.000, 0.500],
    # 14: dark gray
    [0.333, 0.333, 0.333],
    # 15: light gray
    [0.667, 0.667, 0.667],
);
# cpgscr 
my %_custom_colors;

# line style: PGPLOT → PDL::Graphics::Cairo
my @_LS_MAP = ('solid','solid','dashed','dotted','dashdot','dashed');

# marker style: PGPLOT symbol → PDL::Graphics::Cairo marker
my %_MARKER_MAP = (
    0  => '.',   # dot
    1  => '+',   # plus
    2  => '*',   # asterisk → use +
    3  => '*',   # asterisk
    4  => 'o',   # circle
    5  => 'x',   # cross
    6  => 's',   # square
    7  => '^',   # triangle up
    8  => '+',   # plus (bold)
    9  => 'o',   # circle (bold)
   11  => 'd',   # diamond
   12  => 's',   # filled square
   13  => '^',   # filled triangle
   17  => 's',   # filled square
   20  => 'o',   # filled circle
   -1  => '.',   # dot (small)
   -2  => '+',
   -3  => '*',
   -4  => 'o',
);

# =============================================================
#

# =============================================================

sub _ci_to_rgb {
    my ($ci) = @_;
    return @{ $_custom_colors{$ci} } if exists $_custom_colors{$ci};
    # CI=0/1: resolve based on current background setting
    if ($ci == 0 || $ci == 1) {
        my $bg_black = (lc($ENV{_PDLCAIRO_PGBG} // 'white') eq 'black');
        my @tbl = $bg_black ? @_CI_COLORS_BLACK : @_CI_COLORS_WHITE;
        return @{ $tbl[$ci] };
    }
    return @{ $_CI_COLORS[$ci] } if $ci >= 0 && $ci < scalar @_CI_COLORS;
    return (1,1,1);
}

sub _parse_device {
    my ($device) = @_;

    #  PGPLOT_DEV 
    if (!defined $device || $device eq '' || $device eq ' ') {
        $device = $ENV{PGPLOT_DEV} // '/xw';
    }

    my ($file, $type) = ('', '');

    if ($device =~ m{^(.*)/(\w+)$}) {
        ($file, $type) = ($1, uc($2));
    } else {
        $type = uc($device);
    }

    #

    if ($type eq 'PNG') {
        return (interactive=>0, file => $file || 'pgplot.png', ext=>'png');
    } elsif ($type eq 'PDF') {
        return (interactive=>0, file => $file || 'pgplot.pdf', ext=>'pdf');
    } elsif ($type eq 'SVG') {
        return (interactive=>0, file => $file || 'pgplot.svg', ext=>'svg');
    } elsif ($type eq 'PS' || $type eq 'CPS' || $type eq 'VCPS') {
        # PS  PDF 
        return (interactive=>0, file => ($file || 'pgplot').'.pdf', ext=>'pdf');
    }

    #

    my %term_map = (
        OSX  => 'osx',  AQUA => 'aqua', AQT => 'aqua',
        GS   => 'gs',   GW   => 'gs',   GIZA => 'gs',
        X11  => 'x11',  XWIN => 'x11', XW  => 'x11', XSERVE => 'x11',
        WXT  => 'wxt',  QT   => 'qt',
    );
    # Default: auto-detect (empty string → Gnuplot driver resolves)
    my $term = $term_map{$type} // '';
    return (interactive=>1, terminal=>$term);
}

sub _current_color {
    my @rgb = _ci_to_rgb($_state{ci});
    return \@rgb;
}

sub _current_lw  { return $_state{lw} * 0.7 }

sub _current_ls  {
    my $ls = $_state{ls};
    return $ls >= 1 && $ls <= 5 ? $_LS_MAP[$ls] : 'solid';
}

sub _marker_str {
    my ($sym) = @_;
    return $_MARKER_MAP{$sym} // 'o';
}

sub _state { return \%_state }

sub _to_pdl {
    my ($v) = @_;
    return $v if ref($v) && ref($v) ne 'ARRAY' && eval { $v->isa('PDL') };
    return pdl(ref($v) eq 'ARRAY' ? @$v : $v);
}

sub _ax {
    my $ax = $_state{current_ax};
    die "PGPLOT: no open device (call cpgbeg/cpgopen first)\n" unless $ax;
    return $ax;
}

sub _flush {
    return unless $_state{fig};
    return if $_state{buffering};
    my $fig = $_state{fig};

    # pglab/cpgmtxt によるylabel設定は _build_panels/_apply_pgplot_margins
    # 実行後(各pgenvループの中)に行われることが多いため、保存直前に
    # 改めて _apply_pgplot_margins() を呼び、ylabel有無に応じたmlの
    # 動的拡張(_apply_pgplot_margins内のhas_ylabel判定)を最終状態で
    # 反映させる。
    _apply_pgplot_margins();

    #  Axes 1 Figure 
    my $has_content = grep { defined $_->xmin } @{ $fig->axes_list };
    return unless $has_content;
    if ($_state{interactive}) {
     my $t = $_state{terminal};
     if ($t eq 'osx' || $t eq 'gs') {
        # ドライバ一本化: レガシーな /osx デバイスと新規 /gs デバイスは
        # どちらも giza_server 経由で表示する（Driver::GS が auto-spawn）。
        # 以前はここで明示的に $fig->tight_layout() を呼んでいたが、
        # これは _build_panels/_apply_pgplot_margins で設定済みの
        # PGPLOT流マルチパネル配置(fig_x/fig_y等)を 1x1 前提で
        # 上書きしてしまい、全パネルが重なって描画される不具合の
        # 原因だった（PNG保存経路の _render_to と同じ問題）。
        # PGPLOT経路はレイアウトを自前で計算済みなので、ここでは
        # 呼ばず、_tight_done を立てて show() 内部の自動呼び出しも
        # 抑制する。
        $fig->{_tight_done} = 1;
        $fig->show(backend => 'gs');
     } else {
        $fig->{_tight_done} = 1;
        $fig->show(terminal => $t);
     }

    } else {
        # _render_to は tight_layout が未実行(_tight_done未セット)だと
        # 自動的に tight_layout() を呼んでしまう。tight_layout() は
        # 各Axesの fig_x/fig_y/width/height を Figure の _nrows/_ncols
        # (PGPLOT経路では未設定=1x1扱い)に基づいて再計算し直すため、
        # _build_panels/_apply_pgplot_margins で設定した PGPLOT 流の
        # マルチパネル配置(fig_x=col*cw等)が全パネル(0,0)に統一されて
        # しまい、結果として全サブプロットが重なって描かれる不具合になる。
        # PGPLOT経路は自前でレイアウトを計算済みなので、_tight_done を
        # 立てて _render_to 側の自動 tight_layout を抑制する。
        $fig->{_tight_done} = 1;
        $fig->save($_state{outfile});
    }
}

sub _new_figure {
    $_state{fig} = figure(
        width  => $_state{width},
        height => $_state{height},
    );
    $_state{axes}      = [];
    $_state{panel_idx} = 0;
    _build_panels();
    _apply_pgplot_margins();
}

# PGPLOT  Axes 
sub _apply_pgplot_margins {
    my $nx = abs($_state{nxsub} || 1) || 1;
    my $ny = abs($_state{nysub} || 1) || 1;
    return unless $nx * $ny > 1;

    #  OK
    # "-10" ≈ 18px → margin_left=22px
    # X 8px → margin_bottom=14px
    #  8px → margin_top=12px
    # X(8px) + (3px) = 11px → mb 
    # YminX mb 
    # mt: (8px) + (2px) = 10px
    # mb: X(8px) + (3px) + Y(4px) = 15px → 18px
    # ml: ylabel('uV'等)の縦書きgap(19px)に対して数値ラベルとの
    # 重なりを避ける安全マージンを確保するため、nx>4時も22→26pxに調整。
    my $ml = $nx > 4 ? 26 : 30;
    my $mr = $nx > 4 ?  4 :  6;
    my $mt = $ny > 4 ? 16 : 20;
    # mb: 数値ラベル(pad6+tick_ext3+2+高さ10=21px)に加えて
    # xlabel文字自体(オフセット23+高さ10=33px)を収める必要があるため、
    # 当初の22/26pxでは不足する。34/30px程度に調整する。
    my $mb = $ny > 4 ? 30 : 34;

    # ylabel('uV'等)を持つパネルが1つでもあれば、ml をさらに拡張する。
    # _draw_labels の縦書きylabel gap(19+tick_w、tick_wは数値ラベル文字幅の
    # 実測値で2-3桁では12-18px程度になる)に対し、上記の固定ml(26-30px)
    # では安全マージンが数px〜マイナスしかなく、ylabelがプロット枠の
    # すぐ際や枠内に描かれてしまう不具合があった。
    # ylabelがある場合のみ、実測を待たずに安全側の固定値(58px)へ拡張する。
    # （_apply_pgplot_margins は pglab 呼び出し前後の両方で呼ばれるため、
    #  まだ ylabel 未設定の初回呼び出し時は通常の ml のままになるが、
    #  _flush() 直前にも呼び直すことで pglab 後の最終状態を反映する。）
    my $has_ylabel = grep { ($_->ylabel // '') ne '' } @{ $_state{axes} };
    if ($has_ylabel) {
        $ml = $nx > 4 ? 50 : 58;
    }

    for my $ax (@{ $_state{axes} }) {
        $ax->margin_left($ml);
        $ax->margin_right($mr);
        $ax->margin_top($mt);
        $ax->margin_bottom($mb);

        # _compact_labels(2): _draw_labels に PGPLOT 専用の超コンパクトな
        # title/xlabel フォント・オフセットを使わせる(Axes.pm参照)。
        $ax->_compact_labels(2);

        # 数値ラベル(tick)自体も縮小しないと、上記の小さい mb/mt
        # (PGPLOT伝統の値)に対してラベルが飛び出してしまう。
        # pad/labelsize を縮め、tick位置をmb/mtの確保範囲内に収める。
        # 数値ラベル位置 = mb + tick_ext(3) + pad + 2 なので、
        # pad=6, tick_ext=3 で mb+11 となり mb=22-26px の範囲に収まる。
        $ax->tick_params(labelsize => 8, pad => 6, length => 3);
    }
}

sub _build_panels {
    my $nx  = abs($_state{nxsub} || 1) || 1;
    my $ny  = abs($_state{nysub} || 1) || 1;
    my $fig = $_state{fig} or return;
    my $fw  = $fig->width;
    my $fh  = $fig->height;

    @{ $_state{axes} } = ();
    # Figure  axes_list 
    $fig->{axes_list} = [];

    my $cw = int($fw / $nx);
    my $ch = int($fh / $ny);

    if ($nx == 1 && $ny == 1) {
        # : Figure 
        my $ax = PDL::Graphics::Cairo::Axes->new(
            width  => $fw, height => $fh,
            fig_x  => 0,   fig_y  => 0,
        );
        $ax->{_pgenv_called} = 0;
        $ax->{_pgbox}        = undef;
        push @{ $_state{axes} }, $ax;
        push @{ $fig->{axes_list} }, $ax;
    } else {
        # PGPLOT column-major:
        #   idx=0 → col=0,row=0  idx=1 → col=0,row=1  ...
        #   idx=ny → col=1,row=0  ...
        for my $idx (0..$nx*$ny-1) {
            my $col = int($idx / $ny);
            my $row = $idx % $ny;
            my $ax  = PDL::Graphics::Cairo::Axes->new(
                width  => $cw,
                height => $ch,
                fig_x  => $col * $cw,
                fig_y  => $row * $ch,
            );
            $ax->{_pgenv_called} = 0;
            $ax->{_pgbox}        = undef;
            push @{ $_state{axes} }, $ax;
            push @{ $fig->axes_list }, $ax;
        }
    }
    $_state{current_ax} = $_state{axes}[0];
    $_state{panel_idx}  = 0;
    _apply_pgplot_margins();
}

# =============================================================
#

# =============================================================

sub cpgopen {
    my ($device) = @_;
    my %d = _parse_device($device);
    $_state{device}      = $device;
    $_state{interactive} = $d{interactive};
    $_state{terminal}    = $d{terminal} // '';
    $_state{outfile}     = $d{file}     // 'pgplot.png';

    # PGPLOT_BACKGROUND: only active within the PGPLOT layer
    # Set internal variable so Driver::Cairo uses it,
    # but Cairo API (figure/save) is unaffected
    my $bg = $ENV{PGPLOT_BACKGROUND} // 'white';
    $_state{background} = lc($bg);
    $ENV{_PDLCAIRO_PGBG} = lc($bg);   # read by Driver::Cairo

    _new_figure();
    return 1;
}

sub cpgbeg {
    my ($unit, $file, $nxsub, $nysub) = @_;
    $nxsub //= 1; $nysub //= 1;
    # PGPLOT  → 
    $nxsub = abs($nxsub) || 1;
    $nysub = abs($nysub) || 1;
    $_state{nxsub} = $nxsub;
    $_state{nysub} = $nysub;
    return cpgopen($file);
}

sub cpgend {
    _flush();
    $_state{fig}        = undef;
    $_state{axes}       = [];
    $_state{current_ax} = undef;
    # Reset internal background flag so Cairo API is unaffected
    delete $ENV{_PDLCAIRO_PGBG};
}

sub cpgclos { cpgend() }

sub cpgpage {
    my $nx    = abs($_state{nxsub} || 1) || 1;
    my $ny    = abs($_state{nysub} || 1) || 1;
    my $total = $nx * $ny;

    if ($total <= 1) {
        # : flush  Figure
        _flush();
        _new_figure();
    } else {
        # subpanel : Figure 
        my $next = $_state{panel_idx} + 1;
        if ($next >= $total) {
            #  →  flush
            my $has_content = grep { defined $_->xmin } @{ $_state{fig}->axes_list };
            _flush() if $has_content;
            _new_figure();
            #  pgenv  xlim/ylim 
        } else {
            $_state{panel_idx} = $next;
            $_state{current_ax} = $_state{axes}[$next];
            #

            #  pgenv 
            my $ax = $_state{current_ax};
            if (defined $_state{xmin}) {
                my ($xl,$xr) = $_state{xmin} < $_state{xmax}
                    ? ($_state{xmin}, $_state{xmax})
                    : ($_state{xmax}, $_state{xmin});
                my ($yb,$yt) = $_state{ymin} < $_state{ymax}
                    ? ($_state{ymin}, $_state{ymax})
                    : ($_state{ymax}, $_state{ymin});
                $ax->xlim($xl, $xr);
                $ax->ylim($yb, $yt);
                $ax->{_y_reversed} = $_state{y_reversed};
            }
            #  pgenv/pgbox 
            $ax->{_pgenv_called} = 0;
            $ax->{_pgbox}        = undef;
        }
    }
}

sub cpgsubp {
    my ($nxsub, $nysub) = @_;
    $_state{nxsub} = abs($nxsub) || 1;
    $_state{nysub} = abs($nysub) || 1;
    _build_panels();
}

sub cpgpanl {
    my ($ix, $iy) = @_;
    my $nx  = $_state{nxsub};
    my $idx = ($iy - 1) * $nx + ($ix - 1);
    $_state{panel_idx}  = $idx;
    $_state{current_ax} = $_state{axes}[$idx];
}

# =============================================================
#

# =============================================================

sub cpgenv {
    my ($xmin, $xmax, $ymin, $ymax, $just, $axis) = @_;

    #

    #  pgpage  pgenv 
    {
        my $ax = _ax();
        if ($ax->{_pgenv_called} && scalar @{$ax->_queue} > 0) {
            cpgpage();
        }
    }

    $_state{xmin} = $xmin; $_state{xmax} = $xmax;
    $_state{ymin} = $ymin; $_state{ymax} = $ymax;

    # PGPLOT : XMAX < XMIN  YMAX < YMIN 
    # YMIN > YMAX  → Ynegative up: 
    $_state{y_reversed} = ($ymin + 0 > $ymax + 0) ? 1 : 0;

    my $ax = _ax();

    # xlim/ylim  min max 
    my ($xl, $xr) = $xmin < $xmax ? ($xmin, $xmax) : ($xmax, $xmin);
    my ($yb, $yt) = $ymin < $ymax ? ($ymin, $ymax) : ($ymax, $ymin);
    $ax->xlim($xl, $xr);
    $ax->ylim($yb, $yt);

    # Y negative up
    if ($_state{y_reversed}) {
        $ax->{_y_reversed} = 1;
    } else {
        $ax->{_y_reversed} = 0;
    }

    # axis 
    $ax->set_grid(1) if defined $axis && $axis == 2;

    # pgenv pgbox 
    $ax->{_pgenv_called} = 1;
    # axis=-2 →  pgbox _draw_frame 
    $ax->{_axis_opt} = $axis // 0;
}

sub cpgswin {
    my ($xmin, $xmax, $ymin, $ymax) = @_;
    $_state{xmin} = $xmin; $_state{xmax} = $xmax;
    $_state{ymin} = $ymin; $_state{ymax} = $ymax;
    $_state{y_reversed} = ($ymin + 0 > $ymax + 0) ? 1 : 0;
    my ($xl,$xr) = $xmin<$xmax ? ($xmin,$xmax) : ($xmax,$xmin);
    my ($yb,$yt) = $ymin<$ymax ? ($ymin,$ymax) : ($ymax,$ymin);
    my $ax = _ax();
    $ax->xlim($xl, $xr);
    $ax->ylim($yb, $yt);
    $ax->{_y_reversed} = $_state{y_reversed};
}

sub cpgsvp {
    my ($xleft, $xright, $ybot, $ytop) = @_;
    $_state{vxmin} = $xleft;  $_state{vxmax} = $xright;
    $_state{vymin} = $ybot;   $_state{vymax} = $ytop;
    # viewport  margin 
    my $ax = _ax();
    my $w  = $_state{width};
    my $h  = $_state{height};
    $ax->margin_left(  int($xleft  * $w));
    $ax->margin_right( int((1-$xright) * $w));
    $ax->margin_bottom(int((1-$ytop) * $h));
    $ax->margin_top(   int($ybot   * $h));
}

sub cpgvstd {
    cpgsvp(0.1, 0.9, 0.1, 0.9);
}

*cpgvp = \&cpgsvp;

sub cpgvsiz {
    my ($xleft, $xright, $ybot, $ytop) = @_;
    #  → 
    cpgvstd();
}

sub cpgwnad {
    #

    _ax()->set_aspect('equal');
}

sub cpgpap {
    my ($width, $aspect) = @_;
    # PGPLOT 1=96px 
    # pgpap(13, 0.75) → 13*96=1248px , =1248*0.75=936px
    my $dpi = 96;
    my $w   = $width  > 0 ? int($width * $dpi)   : 800;
    my $h   = $aspect > 0 ? int($w     * $aspect) : 600;
    $_state{width}  = $w;
    $_state{height} = $h;
    # pgpap  pgbegin 
    # → Figure 
    if ($_state{fig}) {
        my $fig = $_state{fig};
        $fig->{width}  = $w;
        $fig->{height} = $h;
        #  Axes subplot 
        my $nx = abs($_state{nxsub} || 1) || 1;
        my $ny = abs($_state{nysub} || 1) || 1;
        my $cw = int($w / $nx);
        my $ch = int($h / $ny);
        for my $idx (0 .. $#{ $_state{axes} }) {
            my $col = int($idx / $ny);
            my $row = $idx % $ny;
            my $ax  = $_state{axes}[$idx];
            $ax->{fig_x}  = $col * $cw;
            $ax->{fig_y}  = $row * $ch;
            $ax->{width}  = $cw;
            $ax->{height} = $ch;
        }
        _apply_pgplot_margins();
    }
}

# =============================================================
#

# =============================================================

sub cpglab {
    my ($xlbl, $ylbl, $toplbl) = @_;
    my $ax = _ax();
    $ax->xlabel($xlbl)  if defined $xlbl  && $xlbl  ne '';
    $ax->ylabel($ylbl)  if defined $ylbl  && $ylbl  ne '';
    $ax->title($toplbl) if defined $toplbl && $toplbl ne '';
}

# cpgmtxt: side='T'/'B'/'L'/'R', disp=displacement, coord, fjust, text
sub cpgmtxt {
    my ($side, $disp, $coord, $fjust, $text) = @_;
    my $ax  = _ax();
    my $s1  = uc(substr($side, 0, 1));

    # T/B/L/R title/xlabel/ylabel 
    # disp > 0 → , disp < 0 → 
    if ($disp >= 0) {
        if    ($s1 eq 'T') { $ax->title($text) }
        elsif ($s1 eq 'B') { $ax->xlabel($text) }
        elsif ($s1 eq 'L') { $ax->ylabel($text) }
        # R  twinx 
    } else {
        # disp < 0 → 
        # coord: 0=, 1=  fjust: 0=, 1=
        #  draw 
        push @{ $ax->_queue }, {
            type      => 'pgmtxt',
            side      => $s1,
            disp      => $disp,
            coord     => $coord // 0.5,
            fjust     => $fjust // 0.5,
            text      => $text,
            color     => _current_color(),
            ch        => $_state{ch},
        };
    }
}

sub cpgtext {
    my ($x, $y, $text) = @_;
    _ax()->text($x, $y, $text, ha=>'left', va=>'bottom');
}

sub cpgptxt {
    my ($x, $y, $angle, $fjust, $text) = @_;
    my $align = $fjust < 0.3 ? 'left' : $fjust > 0.7 ? 'right' : 'center';
    _ax()->text($x, $y, $text,
        align    => $align,
        valign   => 'middle',
        rotation => $angle,
    );
}

sub cpgiden {
    # ID — 
}

# =============================================================
#

# =============================================================

sub cpgline {
    my ($n, $xpts, $ypts) = @_;
    $xpts = _to_pdl($xpts);
    $ypts = _to_pdl($ypts);
    # pgline 
    _ax()->{_pgenv_called} = 1;
    _ax()->line($xpts, $ypts,
        color => _current_color(),
        lw    => _current_lw(),
        ls    => _current_ls(),
    );
    $_state{pen_x} = $xpts->at(-1);
    $_state{pen_y} = $ypts->at(-1);
}

sub cpgmove {
    my ($x, $y) = @_;
    $_state{pen_x} = $x;
    $_state{pen_y} = $y;
}

sub cpgdraw {
    my ($x, $y) = @_;
    _ax()->line(
        pdl($_state{pen_x}, $x),
        pdl($_state{pen_y}, $y),
        color => _current_color(),
        lw    => _current_lw(),
        ls    => _current_ls(),
    );
    $_state{pen_x} = $x;
    $_state{pen_y} = $y;
}

sub cpgpoly {
    my ($n, $xpts, $ypts) = @_;
    $xpts = _to_pdl($xpts);
    $ypts = _to_pdl($ypts);
    _ax()->line(
        $xpts->append($xpts->slice('0:0')),
        $ypts->append($ypts->slice('0:0')),
        color => _current_color(),
        lw    => _current_lw(),
        ls    => _current_ls(),
    );
}

sub cpgrect {
    my ($x1, $x2, $y1, $y2) = @_;
    my @cx = ($x1, $x2, $x2, $x1, $x1);
    my @cy = ($y1, $y1, $y2, $y2, $y1);
    cpgpoly(5, \@cx, \@cy);
}

sub cpgarro {
    my ($x1, $y1, $x2, $y2) = @_;
    _ax()->annotate('',
        xy     => [$x2, $y2],
        xytext => [$x1, $y1],
        color  => _current_color(),
    );
}

sub cpgcirc {
    my ($xcent, $ycent, $radius) = @_;
    my $n = 60;
    my $t = sequence($n+1) * 2 * 3.14159265358979 / $n;
    my $x = $xcent + $radius * cos($t);
    my $y = $ycent + $radius * sin($t);
    _ax()->line($x, $y, color=>_current_color(), lw=>_current_lw());
}

# =============================================================
#

# =============================================================

sub cpgpt {
    my ($n, $xpts, $ypts, $symbol) = @_;
    $xpts = _to_pdl($xpts);
    $ypts = _to_pdl($ypts);
    _ax()->{_pgenv_called} = 1;
    my $mk  = _marker_str($symbol);
    _ax()->scatter($xpts, $ypts,
        color  => _current_color(),
        s      => $_state{ch} * 5,
        marker => $mk,
    );
}

sub cpgpt1 {
    my ($xpt, $ypt, $symbol) = @_;
    cpgpt(1, [$xpt], [$ypt], $symbol);
}

# =============================================================
#

# =============================================================

sub cpgerry {
    # cpgerry(n, x, y1, y2, t) — 
    my ($n, $x, $y1, $y2, $t) = @_;
    $x  = _to_pdl($x);
    $y1 = _to_pdl($y1);
    $y2 = _to_pdl($y2);
    my $ymid = ($y1 + $y2) / 2;
    my $yerr = ($y2 - $y1) / 2;
    _ax()->errorbar($x, $ymid,
        yerr    => $yerr,
        color   => _current_color(),
        lw      => _current_lw(),
        capsize => $t * 10,
        marker  => 'none',
    );
}

sub cpgerrx {
    my ($n, $x1, $x2, $y, $t) = @_;
    $x1 = _to_pdl($x1);
    $x2 = _to_pdl($x2);
    $y  = _to_pdl($y);
    my $xmid = ($x1 + $x2) / 2;
    my $xerr = ($x2 - $x1) / 2;
    _ax()->errorbar($xmid, $y,
        xerr    => $xerr,
        color   => _current_color(),
        lw      => _current_lw(),
        capsize => $t * 10,
        marker  => 'none',
    );
}

sub cpgerr1 {
    my ($dir, $x, $y, $e, $t) = @_;
    if ($dir == 5 || $dir == 6) {
        cpgerry(1, [$x], [$y-$e], [$y+$e], $t);
    } else {
        cpgerrx(1, [$x-$e], [$x+$e], [$y], $t);
    }
}

sub cpgerrb {
    my ($dir, $n, $x, $y, $e, $t) = @_;
    if ($dir == 5 || $dir == 6) {
        cpgerry($n, $x, pdl($y)-pdl($e), pdl($y)+pdl($e), $t);
    } else {
        cpgerrx($n, pdl($x)-pdl($e), pdl($x)+pdl($e), $y, $t);
    }
}

# =============================================================
#

# =============================================================

sub cpghist {
    my ($n, $data, $datmin, $datmax, $nbin, $pgflag) = @_;
    $data = _to_pdl($data);
    _ax()->hist($data,
        bins  => $nbin,
        color => _current_color(),
    );
}

sub cpgbin {
    my ($nbin, $x, $data, $center) = @_;
    $x    = _to_pdl($x);
    $data = _to_pdl($data);
    _ax()->bar($x, $data,
        color => _current_color(),
        width => ($x->at(1) - $x->at(0)) * 0.9,
    );
}

# =============================================================
#

# =============================================================

sub cpggray {
    my ($a, $idim, $jdim, $i1, $i2, $j1, $j2, $fg, $bg, $tr) = @_;
    # 2D  imshow gray 
    my $mat = $a;
    $mat = pdl($mat) unless ref($mat) && $mat->isa('PDL');
    _ax()->imshow($mat, cmap=>'gray', vmin=>$bg, vmax=>$fg);
}

sub cpgimag {
    my ($a, $idim, $jdim, $i1, $i2, $j1, $j2, $a1, $a2, $tr) = @_;
    my $mat = $a;
    $mat = pdl($mat) unless ref($mat) && $mat->isa('PDL');
    _ax()->imshow($mat, cmap=>'viridis', vmin=>$a1, vmax=>$a2);
}

sub cpgwedg {
    my ($side, $disp, $width, $fg, $bg, $label) = @_;
    #  — imshow/contourf 
}

sub cpgctab {
    my ($l, $r, $g, $b, $nc, $contra, $bright) = @_;
    #  — viridis 
}

sub cpgsitf {
    my ($itf) = @_;
    # image transfer function — 
}

# =============================================================
#

# =============================================================

sub cpgcont {
    my ($a, $idim, $jdim, $i1, $i2, $j1, $j2, $c, $nc, $tr) = @_;
    my $mat = pdl($a);
    # x, y  $tr 
    my $ny  = $mat->dim(0);
    my $nx  = $mat->dim(1);
    my @xs  = map { $tr->[0] + $tr->[1] * $_ } 0..$nx-1;
    my @ys  = map { $tr->[3] + $tr->[5] * $_ } 0..$ny-1;
    _ax()->contourf(pdl(@xs), pdl(@ys), $mat,
        cmap   => 'viridis',
    );
}

*cpgconf = \&cpgcont;
*cpgconb = \&cpgcont;
*cpgcons = \&cpgcont;

# =============================================================
#

# =============================================================

sub cpgsci {
    my ($ci) = @_;
    $_state{ci} = $ci;
}

sub cpgscr {
    my ($ci, $r, $g, $b) = @_;
    $_custom_colors{$ci} = [$r, $g, $b];
}

sub cpgshls {
    my ($ci, $h, $l, $s) = @_;
    # HLS → RGB 
    require POSIX;
    #

    my ($r,$g,$b) = _hls_to_rgb($h, $l, $s);
    $_custom_colors{$ci} = [$r, $g, $b];
}

sub _hls_to_rgb {
    my ($h, $l, $s) = @_;
    $h /= 360.0;
    if ($s == 0) { return ($l,$l,$l) }
    my $q = $l < 0.5 ? $l*(1+$s) : $l+$s-$l*$s;
    my $p = 2*$l - $q;
    return map { _hue_to_rgb($p,$q,$_) } ($h+1/3, $h, $h-1/3);
}
sub _hue_to_rgb {
    my ($p,$q,$t) = @_;
    $t += 1 if $t < 0; $t -= 1 if $t > 1;
    return $p + ($q-$p)*6*$t     if 6*$t < 1;
    return $q                    if 2*$t < 1;
    return $p + ($q-$p)*(2/3-$t)*6 if 3*$t < 2;
    return $p;
}

sub cpgslw {
    my ($lw) = @_;
    $_state{lw} = $lw;
}

sub cpgsls {
    my ($ls) = @_;
    $_state{ls} = $ls;
}

sub cpgsch {
    my ($ch) = @_;
    $_state{ch} = $ch;
}

sub cpgscf {
    my ($cf) = @_;
    $_state{cf} = $cf;
}

sub cpgsfs {
    my ($fs) = @_;
    $_state{fs} = $fs;
}

sub cpgsah {
    my ($fs, $angle, $vent) = @_;
    # arrowhead Cairo 
    $_state{arrow_fs}    = $fs    // 1;
    $_state{arrow_angle} = $angle // 45.0;
    $_state{arrow_vent}  = $vent  // 0.3;
}

# pgsave/cpgunsa 
my @_attr_stack;

sub cpgsave {
    #

    push @_attr_stack, {
        ci => $_state{ci},
        lw => $_state{lw},
        ls => $_state{ls},
        ch => $_state{ch},
        cf => $_state{cf},
        fs => $_state{fs},
    };
}

sub cpgunsa {
    #

    my $saved = pop @_attr_stack;
    return unless $saved;
    $_state{ci} = $saved->{ci};
    $_state{lw} = $saved->{lw};
    $_state{ls} = $saved->{ls};
    $_state{ch} = $saved->{ch};
    $_state{cf} = $saved->{cf};
    $_state{fs} = $saved->{fs};
}

sub cpgscrl { }

# =============================================================
#

# =============================================================

sub cpgbbuf { $_state{buffering} = 1 }

sub cpgebuf {
    $_state{buffering} = 0;
    _flush();
}

sub cpgupdt { _flush() }

sub cpgeras {
    #  Axes 
    _new_figure();
}

# =============================================================
#

# =============================================================

sub cpgqwin {
    my ($x1, $x2, $y1, $y2) = @_;
    $$x1 = $_state{xmin}; $$x2 = $_state{xmax};
    $$y1 = $_state{ymin}; $$y2 = $_state{ymax};
}

sub cpgqvp {
    my ($units, $x1, $x2, $y1, $y2) = @_;
    $$x1 = $_state{vxmin}; $$x2 = $_state{vxmax};
    $$y1 = $_state{vymin}; $$y2 = $_state{vymax};
}

sub cpgqvsz {
    my ($units, $x1, $x2, $y1, $y2) = @_;
    $$x1 = 0; $$x2 = $_state{width};
    $$y1 = 0; $$y2 = $_state{height};
}

sub cpgqci  { my ($ci) = @_; $$ci = $_state{ci} }
sub cpgqch  { my ($ch) = @_; $$ch = $_state{ch} }
sub cpgqlw  { my ($lw) = @_; $$lw = $_state{lw} }
sub cpgqls  { my ($ls) = @_; $$ls = $_state{ls} }
sub cpgqcf  { my ($cf) = @_; $$cf = $_state{cf} }
sub cpgqfs  { my ($fs) = @_; $$fs = $_state{fs} }

sub cpgqcr {
    my ($ci, $r, $g, $b) = @_;
    my @c = _ci_to_rgb($ci);
    $$r=$c[0]; $$g=$c[1]; $$b=$c[2];
}

sub cpgqcs {
    my ($units, $xch, $ych) = @_;
    $$xch = $_state{ch} * 10;
    $$ych = $_state{ch} * 12;
}

sub cpgqah  { }
sub cpgqhs  { }
sub cpgqinf { }
sub cpgqdt  { }
sub cpgqndt { }

# =============================================================
#

# =============================================================

sub cpgbox {
    my ($xopt, $xtick, $nxsub, $yopt, $ytick, $nysub) = @_;
    $xopt //= ''; $yopt //= '';
    my $ax = _ax();
    return unless $ax->{_pgenv_called};  # ← 元に戻す
    $ax->set_grid(1) if $xopt =~ /G/i || $yopt =~ /G/i;
    $ax->{_pgbox} = {
        xopt  => uc($xopt), yopt  => uc($yopt),
        xtick => $xtick // 0, ytick => $ytick // 0,
        nxsub => $nxsub // 0, nysub => $nysub // 0,
        color => _current_color(),
    };
}

*pgbox = \&cpgbox;

sub cpgask  { my ($f) = @_; $_state{ask} = $f }
sub cpgrnd {
    my ($x, $nsub) = @_;
    # PGPLOT: x  nsub  nice 
    return 0 unless $x;
    my $sign = $x > 0 ? 1 : -1;
    my $ax   = abs($x);
    my $exp  = int(log($ax) / log(10));
    my $mant = $ax / (10 ** $exp);
    # nice mantissa: 1, 2, 2.5, 5, 10
    for my $nice (1, 2, 2.5, 5, 10) {
        if ($mant <= $nice) {
            return $sign * $nice * (10 ** $exp);
        }
    }
    return $sign * 10 * (10 ** $exp);
}
sub cpgrnge {
    my ($x1, $x2, $xlo, $xhi) = @_;
    # PGPLOT: x1x2  nice 
    my ($lo, $hi) = ($x1 < $x2) ? ($x1, $x2) : ($x2, $x1);
    my $range = $hi - $lo;
    return unless $range > 0;
    my $exp   = int(log($range) / log(10)) - 1;
    my $unit  = 10 ** $exp;
    # nice /
    $$xlo = $unit * int($lo / $unit);
    $$xhi = $unit * (int($hi / $unit) + 1);
}
sub cpgnumb {
    my ($mm, $pp, $form, $string, $nc) = @_;
    # PGPLOT: mm * 10^pp 
    my $val = $mm * (10 ** $pp);
    my $str;
    if ($form == 1) {
        $str = sprintf("%.2e", $val);
    } else {
        # floating: 
        if (abs($pp) > 4) {
            $str = sprintf("%.2e", $val);
        } elsif ($pp >= 0) {
            $str = sprintf("%d", int($val + 0.5));
        } else {
            $str = sprintf("%.*f", -$pp, $val);
        }
    }
    $$string = $str if ref($string);
    $$nc     = length($str) if ref($nc);
    return $str;
}

#

sub cpgband { return 0 }
sub cpgcurs { return 0 }
sub cpgncur { return 0 }
sub cpglcur { return 0 }

# =============================================================
#

#
# :
#   cpgXxx  C giza/PGPLOT C ← 
#   pgXxx   PGPLOT Perl XS require PGPLOT
#   pgXxx   pg cpg  1:1 
#
# require PGPLOT 
# =============================================================

{
    no strict 'refs';

    # --- cpgXxx → pgXxx  ---
    my @cpg_stems = qw(
        beg open end clos page subp panl
        env swin svp vstd vsiz pap wnad
        lab mtxt text ptxt
        line move draw poly rect
        pt pt1 arro circ
        sci scr shls slw sls sch scf sfs scrl
        sah save unsa
        erry errx err1 errb
        hist bin
        gray imag wedg ctab sitf
        cont conf conb cons
        bbuf ebuf updt eras
        qwin qvp qvsz qci qch qlw qls
        qcf qfs qcr qcs qah qhs qinf
        iden ask rnd rnge numb
        band curs ncur lcur vp
    );

    for my $stem (@cpg_stems) {
        *{"PDL::Graphics::Cairo::PGPLOT::pg$stem"} =
            \&{"PDL::Graphics::Cairo::PGPLOT::cpg$stem"};
    }

    # --- PGPLOT Perl XS  ---
    # (require PGPLOT )

    # pgbegin = cpgbeg
    *{"PDL::Graphics::Cairo::PGPLOT::pgbegin"} =
        \&PDL::Graphics::Cairo::PGPLOT::cpgbeg;

    # pgclose = cpgclos
    *{"PDL::Graphics::Cairo::PGPLOT::pgclose"} =
        \&PDL::Graphics::Cairo::PGPLOT::cpgclos;

    # pgpoint / pgpoints = cpgpt
    *{"PDL::Graphics::Cairo::PGPLOT::pgpoint"}  =
        \&PDL::Graphics::Cairo::PGPLOT::cpgpt;
    *{"PDL::Graphics::Cairo::PGPLOT::pgpoints"} =
        \&PDL::Graphics::Cairo::PGPLOT::cpgpt;

    # pglabel = cpglab
    *{"PDL::Graphics::Cairo::PGPLOT::pglabel"} =
        \&PDL::Graphics::Cairo::PGPLOT::cpglab;

    # pgvect = cpgvect ()
    *{"PDL::Graphics::Cairo::PGPLOT::pgvect"} = sub {
        warn "pgvect: not yet implemented in PDL::Graphics::Cairo::PGPLOT\n";
    };

    # pgqinf = cpgqinf
    *{"PDL::Graphics::Cairo::PGPLOT::pgqinf"} =
        \&PDL::Graphics::Cairo::PGPLOT::cpgqinf;
}

1;

__END__

=head1 NAME

PDL::Graphics::Cairo::PGPLOT - PGPLOT compatible layer for PDL::Graphics::Cairo

=head1 SYNOPSIS

  use PDL;
  use PDL::Graphics::Cairo::PGPLOT;

  cpgbeg(0, "/OSX", 1, 1);
  cpgenv(0.0, 10.0, -1.0, 1.0, 0, 1);
  cpglab("x", "y", "sin(x)");

  my $n = 100;
  my $x = sequence($n) / 10.0;
  my $y = sin($x);
  cpgsci(2);   # red
  cpgline($n, $x, $y);

  cpgsci(4);   # blue
  my $y2 = cos($x);
  cpgline($n, $x, $y2);

  cpgend();

=head1 DESCRIPTION

Compatibility layer that maps PGPLOT commands to PDL::Graphics::Cairo.
Migrate existing PGPLOT code to Cairo-based rendering with minimal changes.

=head1 DEVICE STRINGS

  "/OSX"        macOS native window (via gnuplot aqua)
  "/X11"        X11 window (via gnuplot x11)
  "/WXT"        wxWidgets window (via gnuplot wxt)
  "/PNG"        save to pgplot.png
  "/PDF"        save to pgplot.pdf
  "/SVG"        save to pgplot.svg
  "file.png/PNG"   save to file.png

=head1 IMPLEMENTED COMMANDS

cpgbeg cpgopen cpgend cpgclos cpgpage cpgsubp cpgpanl
cpgenv cpgswin cpgsvp cpgvstd cpgwnad cpgpap
cpglab cpgmtxt cpgtext cpgptxt
cpgline cpgmove cpgdraw cpgpoly cpgrect cpgarro cpgcirc
cpgpt cpgpt1
cpgsci cpgscr cpgshls cpgslw cpgsls cpgsch cpgscf cpgsfs
cpgerry cpgerrx cpgerr1 cpgerrb
cpghist cpgbin
cpggray cpgimag
cpgcont cpgconf cpgconb cpgcons
cpgbbuf cpgebuf cpgupdt cpgeras
cpgqwin cpgqvp cpgqvsz cpgqci cpgqch cpgqlw cpgqls cpgqcr

=head1 SEE ALSO

L<PDL::Graphics::Cairo>, L<PDL::Graphics::PGPLOT>

=cut
