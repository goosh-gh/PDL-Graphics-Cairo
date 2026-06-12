package PDL::Graphics::Cairo::Figure;

# =============================================================
# Figure -- equivalent to matplotlib Figure
#   subplot / subplots 
# =============================================================

use strict;
use warnings;
use Moo;
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
has suptitle => (is => 'rw', default => sub { '' });

# List of Axes
has axes_list => (is => 'ro', default => sub { [] });

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
    my $top_pad = $self->suptitle ne '' ? 40 : 10;

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

    # 1x1 → 1xN or Nx1 → 1NxM → 2
    if ($nrows == 1 && $ncols == 1) {
        return $grid[0][0];
    }
    elsif ($nrows == 1) {
        return @{ $grid[0] };
    }
    elsif ($ncols == 1) {
        return map { $_->[0] } @grid;
    }
    return @grid;
}

#  Axes
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
# set_suptitle — Figure 
# ------------------------------------------------------------------
sub set_suptitle {
    my ($self, $title, %opt) = @_;
    $self->suptitle($title);
    return $self;
}

# ------------------------------------------------------------------
# save
# ------------------------------------------------------------------
# ------------------------------------------------------------------
# _render_to($driver) —  driver 
# ------------------------------------------------------------------
sub _render_to {
    my ($self, $driver) = @_;

    if ($self->suptitle ne '') {
        $driver->set_font(size => 15, weight => 'bold');
        $driver->set_color(0,0,0);
        $driver->text($self->width/2, 18, $self->suptitle,
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
    my $top_pad = $self->suptitle ne '' ? 36 : 8;

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
    for my $ax (@{ $self->axes_list }) {
        # Axes  fig_x/fig_y 
        my $col = int(($ax->fig_x - $left + $cell_w * 0.5) / $cell_w);
        my $row = int(($ax->fig_y - $top  + $cell_h * 0.5) / $cell_h);
        $col = 0 if $col < 0; $col = $ncols-1 if $col >= $ncols;
        $row = 0 if $row < 0; $row = $nrows-1 if $row >= $nrows;

        # : Y
        my $ml = $col == 0 ? 68 : 52;
        $ml = 80 if $ax->ylabel ne "";
        $ml = 80 if $ax->ylabel ne '';

        # : 
        my $mr = $ax->_colorbar ? 72 : (exists $ax->{_right_ylabel} && $ax->{_right_ylabel} ne "") ? 110 : 16;

        # : X
        my $mb = $row == $nrows-1 ? 56 : 36;
        $mb = 64 if $ax->xlabel ne '';

        # : 
        my $mt = $ax->title ne '' ? 38 : 24;
        $mt = 48 if $row == 0 && $self->suptitle ne '';

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
