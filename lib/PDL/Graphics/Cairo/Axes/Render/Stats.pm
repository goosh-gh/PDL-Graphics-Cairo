package PDL::Graphics::Cairo::Axes;

# Drawing of the queued plot commands: box plots and violins.
# Part of PDL::Graphics::Cairo::Axes, split out of Axes.pm (P:G:C31): the
# subs below are methods of the same package, and _render_cmd (Axes.pm) calls
# them through %RENDER. The API methods that queue the commands stay in Axes.pm.
# Loaded at the end of Axes.pm, after its imports and constants.

use strict;
use warnings;
no warnings "redefine";

sub _render_boxplot_item {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $xc  = $cmd->{xc};
    my $hw  = $cmd->{hw};
    my $xl  = $tr->x(pdl($xc - $hw))->at(0);
    my $xr  = $tr->x(pdl($xc + $hw))->at(0);
    my $xcp = $tr->x(pdl($xc))->at(0);
    my $yq1 = $tr->y(pdl($cmd->{q1}))->at(0);
    my $yq3 = $tr->y(pdl($cmd->{q3}))->at(0);
    my $yme = $tr->y(pdl($cmd->{med}))->at(0);
    my $ymn = $tr->y(pdl($cmd->{mean}))->at(0);
    my $ylo = $tr->y(pdl($cmd->{wlo}))->at(0);
    my $yhi = $tr->y(pdl($cmd->{whi}))->at(0);

    #

    $b->set_color(@{$cmd->{facecolor}}, 0.8);
    $b->rect_fill($xl, $yq3, $xr - $xl, $yq1 - $yq3);

    #

    $b->set_color(@{$cmd->{edgecolor}});
    $b->set_linewidth(1.2);
    $b->line_seg($xcp, $yq3, $xcp, $yhi);
    #

    $b->line_seg($xcp, $yq1, $xcp, $ylo);

    #

    if ($cmd->{showcaps}) {
        my $cw = ($xr - $xl) * 0.4;
        $b->line_seg($xcp - $cw, $yhi, $xcp + $cw, $yhi);
        $b->line_seg($xcp - $cw, $ylo, $xcp + $cw, $ylo);
    }

    #

    $b->rect_stroke($xl, $yq3, $xr - $xl, $yq1 - $yq3);

    #

    $b->set_linewidth(2.0);
    $b->line_seg($xl, $yme, $xr, $yme);

    #

    if ($cmd->{showmean}) {
        $b->set_color(1, 0, 0);
        $b->marker($xcp, $ymn, 4, 'd', 1);
    }
}

sub _render_box_fliers {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $xcp = $tr->x(pdl($cmd->{xc}))->at(0);
    $b->set_color(@{$cmd->{color}});
    $b->set_linewidth(1.5);
    for my $j (0..$cmd->{data}->nelem-1) {
        my $yp = $tr->y(pdl($cmd->{data}->at($j)))->at(0);
        $b->marker($xcp, $yp, 3, 'o', 0);
    }
}

sub _render_violin_item {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $xc   = $cmd->{xc};
    my $ys   = $cmd->{ys};
    my $kde  = $cmd->{kde};
    my $n    = $ys->nelem;

    #  x,y
    my @rx = map { $tr->x(pdl($xc + $kde->at($_)))->at(0) } 0..$n-1;
    my @ry = map { $tr->y(pdl($ys->at($_)))->at(0)        } 0..$n-1;
    #

    my @lx = map { $tr->x(pdl($xc - $kde->at($_)))->at(0) } reverse 0..$n-1;
    my @ly = map { $tr->y(pdl($ys->at($_)))->at(0)        } reverse 0..$n-1;

    my $poly_x = pdl(@rx, @lx);
    my $poly_y = pdl(@ry, @ly);

    #

    $b->set_color(@{$cmd->{color}}, 0.5);
    $b->filled_polygon($poly_x, $poly_y);
    #

    $b->set_color(@{$cmd->{color}}, 0.9);
    $b->set_linewidth(1.2);
    $b->polyline(pdl(@rx, $lx[0]), pdl(@ry, $ly[0]));
    $b->polyline(pdl(@lx, $rx[0]), pdl(@ly, $ry[0]));

    # IQR 
    if ($cmd->{showbox}) {
        my $xl  = $tr->x(pdl($xc - $kde->max * 0.15))->at(0);
        my $xr  = $tr->x(pdl($xc + $kde->max * 0.15))->at(0);
        my $yq1 = $tr->y(pdl($cmd->{q1}))->at(0);
        my $yq3 = $tr->y(pdl($cmd->{q3}))->at(0);
        $b->set_color(0.3, 0.3, 0.3, 0.9);
        $b->set_linewidth(2.5);
        $b->line_seg($tr->x(pdl($xc))->at(0), $yq1,
                     $tr->x(pdl($xc))->at(0), $yq3);
    }

    #

    if ($cmd->{showmed}) {
        my $ymed = $tr->y(pdl($cmd->{median}))->at(0);
        my $xcp  = $tr->x(pdl($xc))->at(0);
        $b->set_color(1, 1, 1);
        $b->marker($xcp, $ymed, 4, 'o', 1);
        $b->set_color(0.2, 0.2, 0.2);
        $b->marker($xcp, $ymed, 4, 'o', 0);
    }

    #

    if ($cmd->{showmean}) {
        my $ymn = $tr->y(pdl($cmd->{mean}))->at(0);
        my $xcp = $tr->x(pdl($xc))->at(0);
        $b->set_color(1, 0.2, 0.2);
        $b->marker($xcp, $ymn, 4, 'd', 1);
    }
}

1;
