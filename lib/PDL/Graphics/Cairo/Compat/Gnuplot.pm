package PDL::Graphics::Cairo::Compat::Gnuplot;

# ==============================================================
# PDL::Graphics::Cairo::Compat::Gnuplot
#
# gnuplot ユーザー向け互換レイヤー。
# use PDL::Graphics::Cairo ':gnuplot';  で自動的に有効になる。
#
# 提供するもの:
#   1. Axes に gnuplot "with <style>" style-string を受け付ける
#      plot/scatter/bar/step/stem/errorbar/quiver/fill_between
#   2. Axes に gnuplot "with xxx" 名エイリアス
#      lines / points / linespoints / lp / impulses / boxes /
#      filledcurves / vectors / yerrorbars / xerrorbars
#   3. $ax->gset("xrange [0:10]") 等 gnuplot set 文の簡易パース
# ==============================================================

use strict;
use warnings;

# ---------------------------------------------------------------
# gnuplot style-string -> P:G:C opt hash
# ---------------------------------------------------------------
sub _parse_style {
    my ($str) = @_;
    return () unless defined $str && $str =~ /\S/;

    my %opt;
    my $s = $str;

    if ($s =~ s/\bwith\s+(\w+)//)               { $opt{_with} = lc $1 }
    if ($s =~ s/\b(?:lw|linewidth)\s+([\d.]+)//) { $opt{lw}    = $1+0 }
    if ($s =~ s/\b(?:ps|pointsize)\s+([\d.]+)//) { $opt{s}     = int($1*6+0.5) }
    if ($s =~ s/\b(?:pt|pointtype)\s+(\d+)//) {
        my %ptmap = (1=>'x',2=>'+',3=>'*',4=>'s',5=>'s',6=>'o',7=>'o',8=>'^',9=>'^');
        $opt{marker} = $ptmap{$1+0} // 'o';
    }
    if ($s =~ s/\b(?:lc|linecolor)\s+rgb\s+['"]([^'"]+)['"]//) { $opt{color} = $1 }
    elsif ($s =~ s/\b(?:lc|linecolor)\s+['"]([^'"]+)['"]//)    { $opt{color} = $1 }
    elsif ($s =~ s/\b(?:lc|linecolor)\s+(#[\da-fA-F]{6})//)    { $opt{color} = $1 }
    if ($s =~ s/\b(?:dt|dashtype)\s+(\d+)//) {
        my %dtmap = (1=>'solid',2=>'dashed',3=>'dotted',4=>'dashdot');
        $opt{linestyle} = $dtmap{$1+0} // 'solid';
    }
    if ($s =~ s/\balpha\s+([\d.]+)//)            { $opt{alpha} = $1+0 }
    if ($s =~ s/\btransparency\s+([\d.]+)//)      { $opt{alpha} = 1-($1+0) }
    if ($s =~ s/\btitle\s+['"]([^'"]*)['"]//)     { $opt{label} = $1 }
    if ($s =~ /\bnotitle\b/)                      { delete $opt{label} }

    return %opt;
}

sub _is_style_string {
    my ($v) = @_;
    return 0 unless defined $v && !ref $v;
    return 0 unless $v =~ /\s/;   # スペースなし = 単独キーワード（ハッシュキー）→ false
    return $v =~ /\b(?:with|lw|lc|pt|ps|dt|title|notitle|linewidth|linecolor|pointtype|pointsize|dashtype)\b/;
}

# ---------------------------------------------------------------
# style-string wrapper を既存メソッドに適用
# ---------------------------------------------------------------
sub _wrap_with_style {
    my ($pkg, $method) = @_;
    my $orig = $pkg->can($method) or return;
    no strict 'refs';
    no warnings 'redefine';
    *{"${pkg}::${method}"} = sub {
        my ($self, $x, $y, @rest) = @_;
        if (@rest && _is_style_string($rest[0])) {
            my %parsed = _parse_style(shift @rest);
            delete $parsed{_with};
            push @rest, %parsed;
        }
        return $orig->($self, $x, $y, @rest);
    };
}

# ---------------------------------------------------------------
# linespoints
# ---------------------------------------------------------------
sub _install_linespoints {
    my ($pkg) = @_;
    no strict 'refs';
    # ラップ前の line/scatter を直接キャプチャする。
    # _wrap_with_style 後に $pkg->can('plot') を経由すると
    # ラッパーがハッシュキー('lw'等)を style string と誤認する可能性があるため。
    my $orig_line    = $pkg->can('line')    or return;
    my $orig_scatter = $pkg->can('scatter') or return;
    *{"${pkg}::linespoints"} = sub {
        my ($self, $x, $y, @rest) = @_;
        if (@rest && _is_style_string($rest[0])) {
            my %p = _parse_style(shift @rest);
            delete $p{_with};
            push @rest, %p;
        }
        my %opt = @rest;
        $orig_line->($self, $x, $y, %opt);
        $orig_scatter->($self, $x, $y,
            color  => $opt{color}  // undef,
            s      => $opt{s}      // 4,
            marker => $opt{marker} // 'o',
            alpha  => $opt{alpha}  // 0.8,
        );
        return $self;
    };
    *{"${pkg}::lp"} = \&{"${pkg}::linespoints"};
}

# ---------------------------------------------------------------
# gset
# ---------------------------------------------------------------
sub _install_gset {
    my ($pkg) = @_;
    no strict 'refs';

    *{"${pkg}::_gset_tics"} = sub {
        my ($self, $axis, $spec) = @_;
        $spec =~ s/^\s+|\s+$//g;
        my (@vals, @labs);
        if ($spec =~ /^\(/) {
            while ($spec =~ /['"]([^'"]+)['"]\s*([-\d.e+]+)/g) {
                push @labs, $1; push @vals, $2+0;
            }
        } else {
            @vals = map { $_ + 0 } grep { /\S/ } split /[,\s]+/, $spec;
        }
        if ($axis eq 'x') { $self->set_xticks(\@vals, @labs ? \@labs : ()) }
        else               { $self->set_yticks(\@vals, @labs ? \@labs : ()) }
        return $self;
    };

    *{"${pkg}::gset"} = sub {
        my ($self, $cmd) = @_;
        $cmd =~ s/^\s+|\s+$//g;

        if ($cmd =~ /^xrange\s*\[\s*([-\d.e+]+)\s*:\s*([-\d.e+]+)\s*\]/i)
            { return $self->set_xlim($1+0,$2+0) }
        if ($cmd =~ /^yrange\s*\[\s*([-\d.e+]+)\s*:\s*([-\d.e+]+)\s*\]/i)
            { return $self->set_ylim($1+0,$2+0) }
        if ($cmd =~ /^title\s+['"]?(.*?)['"]?\s*$/i)   { return $self->set_title($1) }
        if ($cmd =~ /^xlabel\s+['"]?(.*?)['"]?\s*$/i)  { return $self->set_xlabel($1) }
        if ($cmd =~ /^ylabel\s+['"]?(.*?)['"]?\s*$/i)  { return $self->set_ylabel($1) }
        if ($cmd =~ /^nogrid\b/i)                       { return $self->grid(0) }
        if ($cmd =~ /^grid\b/i)                         { return $self->grid(1) }
        if ($cmd =~ /^logscale\s+xy\b/i)
            { $self->set_xscale('log'); return $self->set_yscale('log') }
        if ($cmd =~ /^logscale\s+x\b/i)                { return $self->set_xscale('log') }
        if ($cmd =~ /^logscale\s+y\b/i)                { return $self->set_yscale('log') }
        if ($cmd =~ /^nologscale/i)
            { $self->set_xscale('linear'); return $self->set_yscale('linear') }
        if ($cmd =~ /^key\s+off\b/i)                   { return $self }
        if ($cmd =~ /^key\b/i)                          { return $self->legend() }
        if ($cmd =~ /^size\s+ratio\s+1\b/i)            { return $self->set_aspect('equal') }
        if ($cmd =~ /^xtics\s+(.*)/i)                  { return $self->_gset_tics('x',$1) }
        if ($cmd =~ /^ytics\s+(.*)/i)                  { return $self->_gset_tics('y',$1) }

        warn "gset: unrecognized command '$cmd' (ignored)\n";
        return $self;
    };
}

# ---------------------------------------------------------------
# install() -- Axes クラスへの一括注入
# ---------------------------------------------------------------
sub install {
    my $pkg = 'PDL::Graphics::Cairo::Axes';

    for my $m (qw(plot line scatter bar barh step stem errorbar
                  fill_between quiver)) {
        _wrap_with_style($pkg, $m);
    }

    {
        no strict 'refs';
        *{"${pkg}::lines"}        = \&{"${pkg}::plot"};
        *{"${pkg}::points"}       = \&{"${pkg}::scatter"};
        *{"${pkg}::impulses"}     = \&{"${pkg}::stem"};
        *{"${pkg}::boxes"}        = \&{"${pkg}::bar"};
        *{"${pkg}::filledcurves"} = \&{"${pkg}::fill_between"};
        *{"${pkg}::vectors"}      = \&{"${pkg}::quiver"};
        *{"${pkg}::yerrorbars"}   = \&{"${pkg}::errorbar"};
        *{"${pkg}::xerrorbars"}   = \&{"${pkg}::errorbar"};
    }

    _install_linespoints($pkg);
    _install_gset($pkg);
}

1;
