#!/usr/bin/env perl
# examples/example_gs_zoom_pan.pl — interactive zoom/pan demo
#
# Controls (macOS):
#   pinch in/out or Ctrl+scroll  : zoom
#   two-finger drag while zoomed : pan
#   double-click                 : reset to full view
#
# How zoom_pan_redraw => 1 works:
#   - giza-server detects zoom/pan gestures and sends GSP_MSG_ZOOM
#   - Driver::GS writes the new view range into $state:
#       _zoom_xlim_lo / _zoom_xlim_hi  ... new x display range
#       _zoom_ylim_lo / _zoom_ylim_hi  ... new y display range
#       _zoom, _pan_x, _pan_y          ... raw zoom/pan values
#   - render applies these to xlim/ylim for full-resolution redraw
#   - when reset (zoom=1, pan=0), the _zoom_xlim_* keys are removed

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(subplots);
use PDL::Graphics::Cairo::Driver::GS;

# --- Data: waveform with fine structure revealed by zooming in ---
my $x = sequence(2000) / 200;          # 0..10, 2000 points
my $y = sin($x * 3) * exp(-$x/5)      # damped sine
      + 0.15 * sin($x * 37)           # high-freq component (visible when zoomed)
      + 0.05 * sin($x * 120);         # even higher frequency

# --- Render callback ---
my $render = sub {
    my ($state, $w, $h) = @_;
    my ($fig, $ax) = subplots(1, 1, width => $w, height => $h);

    # zoom_pan_redraw writes the current view range into $state
    my $xlo = $state->{_zoom_xlim_lo} // 0;
    my $xhi = $state->{_zoom_xlim_hi} // 10;
    my $ylo = $state->{_zoom_ylim_lo} // -1.3;
    my $yhi = $state->{_zoom_ylim_hi} //  1.3;

    $ax->xlim($xlo, $xhi);
    $ax->ylim($ylo, $yhi);

    # Draw only data within the visible range (performance optimization)
    my $margin = ($xhi - $xlo) * 0.05;
    my $mask   = ($x >= $xlo - $margin) & ($x <= $xhi + $margin);
    my $xv = $x->where($mask);
    my $yv = $y->where($mask);

    $ax->line($xv, $yv, color => 'steelblue', lw => 1.5);
    $ax->set_xlabel('x');
    $ax->set_ylabel('y');

    # Show zoom state in plot
    if (defined $state->{_zoom} && $state->{_zoom} > 1.01) {
        my $zmsg = sprintf("zoom=%.1fx  x=[%.3f, %.3f]", $state->{_zoom}, $xlo, $xhi);
        $ax->text($xlo + ($xhi-$xlo)*0.02, $yhi - ($yhi-$ylo)*0.05,
            $zmsg, ha=>'left', va=>'top', fontsize=>10, color=>'darkgreen');
    } else {
        $ax->set_title('pinch / Ctrl+scroll to zoom  |  two-finger drag to pan  |  double-click to reset');
    }

    $fig->tight_layout;
    return $fig;
};

# --- Launch interactive viewer ---
my $drv = PDL::Graphics::Cairo::Driver::GS->new(
    width  => 900,
    height => 500,
    title  => 'zoom/pan demo',
);

print "pinch in/out or Ctrl+scroll to zoom\n";
print "two-finger drag to pan\n";
print "double-click to reset\n\n";

$drv->show_interactive(
    render          => $render,
    zoom_pan_redraw => 1,
    cursor_overlay  => 1,
    on_zoom => sub {
        my ($zoom, $px, $py) = @_;
        printf "\rzoom=%.2f pan=(%.3f,%.3f)   ", $zoom, $px, $py;
    },
);
