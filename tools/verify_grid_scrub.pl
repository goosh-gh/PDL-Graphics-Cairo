#!/usr/bin/env perl
# Headless verification of show_grid_scrub's decoration logic WITHOUT giza-server.
# Drives the driver's private paint/hit-test methods against real Figure/Axes and
# renders to an in-memory Cairo surface, so the coordinate transforms, nearest-point
# snap, marker and readout are all exercised for real. GUI-independent.
use strict;
use warnings;
use lib 'lib';
use PDL;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::Driver::GS;
use PDL::Graphics::Cairo::Driver::Cairo;

my $W = 900; my $H = 700;
my $nrows = 5; my $ncols = 5;
my $t = sequence(101);                      # 0..100 ms latency
my $ok = 0; my $fail = 0;
sub okk { my ($c,$m)=@_; $m//=''; $c ? ($ok++, print "ok  - $m\n") : ($fail++, print "NOT OK - $m\n") }

# grid_render: 5x5, each cell a distinct sine so cells differ
my $grid_render = sub {
    my ($state, $w, $h) = @_;
    my $fig = figure(width=>$w, height=>$h);
    my @rows = $fig->subplots($nrows, $ncols);
    for my $r (0..$nrows-1) {
        for my $c (0..$ncols-1) {
            my $ax = $rows[$r][$c];
            my $k  = 1 + ($r*$ncols + $c);
            $ax->line($t, 30*sin($t/(2+$k)) );
            $ax->set_title("ch".($r*$ncols+$c));
        }
    }
    $fig->tight_layout;
    return $fig;
};

# cell_render: a single big axes reproducing cell $idx's trace
my $cell_render = sub {
    my ($idx, $state, $w, $h) = @_;
    my $r = int($idx / $ncols); my $c = $idx % $ncols;
    my $k = 1 + ($r*$ncols + $c);
    my $fig = figure(width=>$w, height=>$h);
    my $ax  = $fig->subplots(1,1);
    $ax->line($t, 30*sin($t/(2+$k)) );
    $ax->set_title("ch$idx (zoom)");
    $fig->tight_layout;
    return $fig;
};

# Build the driver + a minimal window-manager context by hand (no sockets).
my $drv = PDL::Graphics::Cairo::Driver::GS->new(width=>$W, height=>$H);
my $wm = {
    state       => {},
    grid_render => $grid_render,
    cell_render => $cell_render,
    zoom_w => $W, zoom_h => $H,
    vline  => { color=>[1,0,0], lw=>1.2 },
    marker => { color=>[1,0,0], ms=>7, marker=>'o' },
    readout=> sub { sprintf("x=%.4g\ny=%.4g", $_[0], $_[1]) },
    wins => [], cells => {},
};

# render helper (to :memory:), returns PNG byte length; also leaves _plot_* set
sub render_png {
    my ($drv, $fig) = @_;
    my $bytes = $drv->_figure_to_png($fig);
    return length($bytes);
}

# ---- 1) main paint WITHOUT scrub latency: no vlines added ------------
{
    my $win = { kind=>'main', w=>$W, h=>$H };
    my $fig = $drv->_paint_main($wm, $win);
    my $nv = grep { ($_->{type}//'') eq 'vline' } map { @{$_->_queue} } @{$fig->axes_list};
    okk($nv == 0, "main paint: no vlines when _scrub_lat unset");
    okk(scalar(@{$fig->axes_list}) == $nrows*$ncols, "main paint: 25 axes present");
    okk(render_png($drv,$fig) > 0, "main paint renders to PNG");
}

# ---- 2) main paint WITH scrub latency: one vline per cell -----------
{
    $wm->{state}{_scrub_lat} = 42.0;
    my $win = { kind=>'main', w=>$W, h=>$H };
    my $fig = $drv->_paint_main($wm, $win);
    my @vl = grep { ($_->{type}//'') eq 'vline' } map { @{$_->_queue} } @{$fig->axes_list};
    okk(scalar(@vl) == $nrows*$ncols, "main paint: exactly one vline per subplot (25)");
    okk( (grep { abs($_->{x}-42.0)<1e-9 } @vl) == $nrows*$ncols, "main paint: vlines at latency 42");
    okk(render_png($drv,$fig) > 0, "main paint with vlines renders");
    delete $wm->{state}{_scrub_lat};
}

# ---- 3) double-click hit-test: fraction over a known cell -> idx ----
{
    # render a base main figure so _plot_* are set for image_frac_to_data
    my $win = { kind=>'main', w=>$W, h=>$H };
    my $fig = $drv->_paint_main($wm, $win);
    render_png($drv, $fig);                 # populate plot rects
    $win->{last_fig} = $fig;

    # pick the center of cell (row=2,col=3) => idx = 2*5+3 = 13
    my $target = 2*$ncols + 3;
    my $ax = $fig->axes_list->[$target];
    # center of that axes' plot rect, in IMAGE fraction
    my $fx = ( ($ax->_plot_ml + $ax->_plot_mr)/2 ) / $W;
    my $fy = ( ($ax->_plot_mt + $ax->_plot_mb)/2 ) / $H;
    # replicate _dblclick_main's hit loop
    my $hit; my $i=0;
    for my $a (@{$fig->axes_list}) {
        my ($xd,$yd) = $a->image_frac_to_data($fx,$fy);
        if (defined $xd) { $hit=$i; last } $i++;
    }
    okk(defined $hit && $hit == $target, "hit-test: center of cell 13 resolves to idx 13 (got ".($hit//'undef').")");
}

# ---- 4) cell cursor + paint: live readout + PERSISTENT marker -------
{
    my $idx = 7;
    my $win = { kind=>'cell', ax_idx=>$idx, w=>$W, h=>$H, cursor=>undef, mark=>undef };
    my $base = $drv->_paint_cell($wm, $win);
    render_png($drv, $base);
    $win->{last_fig} = $base;
    my $ax = $base->axes_list->[0];

    my $frac = sub {   # image fraction at x-fraction $xf across plot, mid height
        my ($xf) = @_;
        return ( ($ax->_plot_ml + $xf*($ax->_plot_mr-$ax->_plot_ml))/$W,
                 ($ax->_plot_mt + 0.5*($ax->_plot_mb-$ax->_plot_mt))/$H );
    };
    my $count = sub {  # (annotations, markers) in the cell's queue
        my @q = @{ $_[0]->axes_list->[0]->_queue };
        return ( scalar(grep{($_->{type}//'')eq'annot'}@q),
                 scalar(grep{($_->{type}//'')eq'line'&&$_->{marker}}@q) );
    };

    # (a) hover with NO prior selection: readout only, no marker
    my ($fx,$fy) = $frac->(0.30);
    $drv->_cell_cursor($wm, $win, 0x18, $fx, $fy, 0);      # CURSOR btn=0 (hover)
    my ($an,$mk) = $count->( $drv->_paint_cell($wm,$win) );
    okk($an==1 && $mk==0, "cell hover(no selection): readout, no marker");

    # (b) drag at 62%: selection set → marker + readout + parent latency
    ($fx,$fy) = $frac->(0.62);
    $drv->_cell_cursor($wm, $win, 0x18, $fx, $fy, 1);      # CURSOR btn=1 (drag)
    (my $figD = $drv->_paint_cell($wm,$win));
    ($an,$mk) = $count->($figD);
    okk($mk==1, "cell drag: marker placed");
    okk(defined $wm->{state}{_scrub_lat}, "cell drag: _scrub_lat set (parent vlines)");
    my $lat = $wm->{state}{_scrub_lat};
    my ($ad) = grep { ($_->{type}//'')eq'annot' } @{ $figD->axes_list->[0]->_queue };
    my ($xd_read) = $ad->{str} =~ /x=([-\d.]+)/;
    okk(defined $xd_read && abs($xd_read-62)<=3, "cell drag: readout ~62ms (got $xd_read)");

    # (c) RELEASE then hover at 20% (btn=0): marker + readout MUST stay frozen
    #     at the selection (62), NOT follow the pointer; latency unchanged.
    ($fx,$fy) = $frac->(0.20);
    $drv->_cell_cursor($wm, $win, 0x18, $fx, $fy, 0);      # hover after release
    (my $figH = $drv->_paint_cell($wm,$win));
    ($an,$mk) = $count->($figH);
    okk($mk==1, "post-release hover: marker persists");
    okk($wm->{state}{_scrub_lat}==$lat, "post-release hover: selection latency unchanged");
    my ($ah) = grep { ($_->{type}//'')eq'annot' } @{ $figH->axes_list->[0]->_queue };
    my ($xh_read) = $ah->{str} =~ /x=([-\d.]+)/;
    okk(defined $xh_read && abs($xh_read-62)<=3, "post-release hover: readout KEEPS selection ~62ms (got $xh_read)");
    okk(render_png($drv,$figH) > 0, "post-release hover renders");
}

# ---- 5) shared selection across windows: a DIFFERENT cell opened after a
#         selection exists shows the marker immediately (no drag in it) -------
{
    $wm->{state}{_scrub_lat} = 55.0;           # a selection already exists
    my $other = { kind=>'cell', ax_idx=>19, w=>$W, h=>$H, cursor=>undef };
    my $fig = $drv->_paint_cell($wm, $other);  # first paint, never dragged here
    my @q = @{ $fig->axes_list->[0]->_queue };
    my $nmk  = grep { ($_->{type}//'')eq'line' && $_->{marker} } @q;
    my ($an) = grep { ($_->{type}//'')eq'annot' } @q;
    my ($xr) = $an ? $an->{str} =~ /x=([-\d.]+)/ : ();
    okk($nmk==1, "shared: newly-opened cell shows marker at shared latency (no drag)");
    okk(defined $xr && abs($xr-55)<=3, "shared: its readout is at the shared latency 55 (got ".($xr//'-').")");
    okk(render_png($drv,$fig) > 0, "shared: newly-opened cell renders");
    delete $wm->{state}{_scrub_lat};
}

# ---- 6) drag throttling: only active cell + main repaint during drag;
#         other cells are deferred and caught up when the drag stream idles ---
{
    # register a main + two cell windows in the manager
    my $main  = { kind=>'main', alive=>1, dirty=>0, w=>$W, h=>$H };
    my $cellA = { kind=>'cell', ax_idx=>7,  alive=>1, dirty=>0, w=>$W, h=>$H,
                  cursor=>undef, last_fig=>undef };
    my $cellB = { kind=>'cell', ax_idx=>19, alive=>1, dirty=>0, w=>$W, h=>$H,
                  cursor=>undef, last_fig=>undef };
    local $wm->{main} = $main;
    local $wm->{wins} = [ $main, $cellA, $cellB ];
    local $wm->{_scrub_stale} = 0;
    delete $wm->{state}{_scrub_lat};

    # give cellA a rendered last_fig so _cell_cursor can convert fx,fy
    my $baseA = $drv->_paint_cell($wm, $cellA); render_png($drv,$baseA);
    $cellA->{last_fig} = $baseA;
    my $ax = $baseA->axes_list->[0];
    my $fx = ($ax->_plot_ml + 0.5*($ax->_plot_mr-$ax->_plot_ml))/$W;
    my $fy = ($ax->_plot_mt + 0.5*($ax->_plot_mb-$ax->_plot_mt))/$H;

    # DRAG in cellA
    $main->{dirty}=0; $cellA->{dirty}=0; $cellB->{dirty}=0;
    $drv->_cell_cursor($wm, $cellA, 0x18, $fx, $fy, 1);
    okk($cellA->{dirty}==1, "throttle: active cell repaints during drag");
    okk($main->{dirty}==1,  "throttle: main repaints during drag (vlines follow)");
    okk($cellB->{dirty}==0, "throttle: other cell is NOT repainted during drag");
    okk($wm->{_scrub_stale}==1, "throttle: other cells marked stale (pending)");

    # IDLE catch-up (replicates the run-loop idle branch): flush stale cells
    if ($wm->{_scrub_stale}) {
        $wm->{_scrub_stale} = 0;
        $_->{dirty}=1 for grep { ($_->{kind}//'')eq'cell' } @{ $wm->{wins} };
    }
    okk($cellB->{dirty}==1, "throttle: deferred cell caught up when drag idled/released");
}
{
    my $cell_rev = sub {
        my ($idx,$state,$w,$h)=@_;
        my $fig = figure(width=>$w,height=>$h);
        my $ax  = $fig->subplots(1,1);
        $ax->line($t, 5*sin($t/6));
        $ax->{_y_reversed} = 1;             # ERP negative-up
        $fig->tight_layout; return $fig;
    };
    local $wm->{cell_render} = $cell_rev;
    my $win = { kind=>'cell', ax_idx=>0, w=>$W, h=>$H, cursor=>undef };
    my $base = $drv->_paint_cell($wm, $win); render_png($drv,$base); $win->{last_fig}=$base;
    my $ax = $base->axes_list->[0];
    my $fx = ($ax->_plot_ml + 0.5*($ax->_plot_mr-$ax->_plot_ml))/$W;
    my $fy = ($ax->_plot_mt + 0.5*($ax->_plot_mb-$ax->_plot_mt))/$H;
    my ($xd,$yd) = $ax->image_frac_to_data($fx,$fy);
    $win->{cursor} = { xd=>$xd, yd=>$yd };
    $wm->{state}{_scrub_lat} = $xd;      # exercise marker+readout under _y_reversed
    my $fig = $drv->_paint_cell($wm,$win);
    okk(render_png($drv,$fig) > 0, "y-reversed cell: readout+marker render without error");
    delete $wm->{state}{_scrub_lat};
}

print "\n$ok passed, $fail failed\n";
exit($fail ? 1 : 0);
