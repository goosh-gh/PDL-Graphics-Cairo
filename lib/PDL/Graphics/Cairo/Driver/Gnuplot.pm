package PDL::Graphics::Cairo::Driver::Gnuplot;

# =============================================================
# Driver::Gnuplot — gnuplot 
#
# :
#   1. Figure  PNG Driver::Cairo 
#   2. gnuplot 
#   3. 
#      : aqua (Aquaterm/macOS) → wxt → x11 → qt
#
# :
#   $fig->show();                        #

#   $fig->show(terminal => 'aqua');      #

#   $fig->show(terminal => 'x11');
#   $fig->show(keep => 1);              #

# =============================================================

use strict;
use warnings;
use Moo;
use File::Temp qw(tempfile);
use PDL::Graphics::Cairo::Driver::Cairo;

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
has width    => (is => 'ro', required => 1);
has height   => (is => 'ro', required => 1);
has terminal => (is => 'ro', default  => sub { '' });
has gnuplot  => (is => 'ro', default  => sub { 'gnuplot' });
has keep     => (is => 'ro', default  => sub { 0 });

# ------------------------------------------------------------------
#

#
# qx{gnuplot -e "set terminal"}  macOS 
# OSDISPLAY 
# ------------------------------------------------------------------
sub _resolve_terminal {
    my ($self) = @_;

    my $is_mac    = ($^O eq 'darwin');
    my $has_display = defined $ENV{DISPLAY} && $ENV{DISPLAY} ne '';

    #

    if ($self->terminal ne '') {
        my $requested = $self->terminal;
        # x11  _terminal_works  False 
        # (DISPLAY )
        my $skip_check = ($requested eq 'x11' && $has_display);
        if ($skip_check || $self->_terminal_works($requested)) {
            return $requested;
        }
        # fallback: reported in show()
    }

    # macOS + XQuartz: DISPLAY  :0 
    if ($is_mac && !$has_display) {
        $ENV{DISPLAY} = ':0';
        $has_display = 1;
    }

    # Priority order:
    #   macOS: aqua(Aquaterm) → x11(XQuartz) → wxt → qt
    #   Linux: wxt → x11 → qt
    my @order = $is_mac
        ? qw(aqua x11 wxt qt)
        : qw(wxt x11 qt);

    for my $term (@order) {
        next if ($term eq 'x11' || $term eq 'wxt') && !$has_display;
        if ($self->_terminal_works($term)) {
            return $term;
            return $term;
        }
    }

    # Final fallback: OS default viewer
    my $viewer = $is_mac ? 'open' : 'xdg-open';
    warn "Driver::Gnuplot: no gnuplot terminal available,"
       . " using OS viewer '$viewer'\n";
    return $viewer;

    die "Driver::Gnuplot: no interactive terminal available.\n"
      . "  gnuplot needs aqua, wxt, x11, or qt.\n"
      . "  Specify explicitly: \$fig->show(terminal => 'aqua')\n";
}

# ------------------------------------------------------------------
#

# gnuplot  'set terminal XXX'  stderr 
# 5
# ------------------------------------------------------------------
sub _terminal_works {
    my ($self, $term) = @_;

    # gnuplot  echo 
    # 'set terminal aqua'  stderr  "unknown terminal" 
    my $gp_cmd = $self->gnuplot;

    # open3 
    require IPC::Open3;
    require POSIX;

    my ($in, $out, $err);
    $err = Symbol::gensym() if eval { require Symbol; 1 };

    # Test by running gnuplot -e "set terminal TERM; quit"
    # and checking stderr for "unknown" or "ambiguous" - exactly as the user
    # would test it from the shell:
    #   gnuplot -e "set terminal qt; quit" 2>&1
    # If stderr contains "unknown" -> terminal not supported -> return False
    my $pid = eval {
        IPC::Open3::open3($in, $out, $err,
            $gp_cmd,
            '-e', "set terminal $term; quit")
    };
    return 0 unless $pid;

    close $in;

    # 3
    my $ok = 1;
    eval {
        local $SIG{ALRM} = sub { die "timeout
" };
        alarm(3);
        my $stderr_out = '';
        if ($err) {
            while (<$err>) { $stderr_out .= $_ }
        }
        waitpid($pid, 0);
        alarm(0);
        # "unknown terminal" or "not available" in stderr means NG
        # Same check as: gnuplot -e "set terminal TERM; quit" 2>&1
        $ok = 0 if $stderr_out =~ /unknown|ambiguous|not available|not compiled/i;
        # stdout not needed
    };
    alarm(0);
    if ($@) {
        #

        kill 'TERM', $pid;
        waitpid($pid, POSIX::WNOHANG());
        return 0;
    }
    return $ok;
}

# ------------------------------------------------------------------
# show($figure) — Figure 
# ------------------------------------------------------------------
sub show {
    my ($self, $figure) = @_;

    # 1.  PNG 
    my ($fh, $tmpfile) = tempfile(
        'pdlcairo_XXXXXX',
        SUFFIX => '.png',
        TMPDIR => 1,
        UNLINK => $self->keep ? 0 : 1,
    );
    close $fh;

    my $png = PDL::Graphics::Cairo::Driver::Cairo->new(
        width  => $self->width,
        height => $self->height,
        file   => $tmpfile,
    );
    $figure->_render_to($png);

    # 2. 
    my $requested = $self->terminal;
    my $term      = $self->_resolve_terminal();
    my $w         = $self->width;
    my $h         = $self->height;

    #

    if ($requested ne '' && $requested ne $term) {
        warn "Warning: gnuplot terminal '$requested' is not available."
           . " Using '$term' instead.\n";
    }
    warn "Driver::Gnuplot: auto-selected terminal '$term'\n"
        if $requested eq '' && $ENV{PDLCAIRO_DEBUG};
    warn "Driver::Gnuplot: terminal=$term  file=$tmpfile\n"
        if $ENV{PDLCAIRO_DEBUG};

    # 3. 
    if ($term eq 'open' || $term eq 'xdg-open') {
        # OS 
        system($term, $tmpfile);
    } else {
        # gnuplot 
        my $term_cmd = _terminal_cmd($term, $w, $h);
        $self->_gnuplot_show($term_cmd, $tmpfile, $w, $h, $term);
    }

    return $tmpfile;
}

sub _gnuplot_show {
    my ($self, $term_cmd, $tmpfile, $w, $h, $term) = @_;

    # Replicate exactly what works interactively:
    #   set terminal x11 persist
    #   plot 'file.png' binary filetype=png with rgbimage
    # No extra range/margin settings that might interfere.
    # Do not use -persist flag (let terminal's own "persist" handle it).
    # Send ALL commands via pipe only.
    # Do NOT use -e flag: on some systems (e.g. MacPorts gnuplot on macOS)
    # the startup file (~/.gnuplot) is read AFTER -e, overriding our terminal.
    # Piped commands are always evaluated last, so they reliably override
    # whatever the startup file set.
    open my $gp, '|-', $self->gnuplot
        or die "Driver::Gnuplot: cannot start gnuplot: $!\n";
    print $gp "$term_cmd\n";
    print $gp "unset key\n";
    print $gp "unset border\n";
    print $gp "unset tics\n";
    print $gp "set margins 0,0,0,0\n";
    print $gp "plot '$tmpfile' binary filetype=png with rgbimage notitle\n";

    # For wxt/qt: "persist" option may not work on all systems.
    # Send "pause mouse close" so the window stays until the user closes it.
    # For aqua/x11: persist is handled by the terminal itself, no pause needed.
    if ($term eq 'wxt' || $term eq 'qt') {
        print $gp "pause mouse close\n";
    }

    close $gp;
}


# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
sub _terminal_cmd {
    my ($term, $w, $h) = @_;

    # aqua: Aquaterm（macOS）
    # 96 dpi 
    if ($term eq 'aqua') {
        my $wi = sprintf("%.1f", $w / 96);
        my $hi = sprintf("%.1f", $h / 96);
        return "set terminal aqua size $w,$h title 'PDL::Graphics::Cairo'";
    }

    # wxt: wxWidgets (cross-platform)
    # "persist" keeps the window open after gnuplot pipe closes
    if ($term eq 'wxt') {
        return "set terminal wxt size $w,$h title 'PDL::Graphics::Cairo' enhanced persist";
    }

    # x11: XQuartz / X11
    # "persist" keeps the window open after gnuplot pipe closes
    # (same as interactive: "set terminal x11 persist")
    if ($term eq 'x11') {
        return "set terminal x11 persist";
    }

    # qt: Qt
    if ($term eq 'qt') {
        return "set terminal qt size $w,$h title 'PDL::Graphics::Cairo' persist";
    }

    return "set terminal $term";
}

1;

__END__

=head1 NAME

PDL::Graphics::Cairo::Driver::Gnuplot - Interactive display via gnuplot

=head1 SYNOPSIS

  use PDL;
  use PDL::Graphics::Cairo qw(figure);

  my $fig = figure(width => 800, height => 500);
  my $ax  = $fig->axes();
  $ax->line(sequence(100)/10, sin(sequence(100)/10));
  $fig->show();
  $fig->show(terminal => 'aqua');

=head1 DESCRIPTION

Renders to a temporary PNG and displays it via gnuplot.
Requires gnuplot 5.0 or later.

Supported terminals (priority order): aqua, wxt, x11, qt

=head1 ENVIRONMENT

Set C<PDLCAIRO_DEBUG=1> to enable debug output.

=cut
