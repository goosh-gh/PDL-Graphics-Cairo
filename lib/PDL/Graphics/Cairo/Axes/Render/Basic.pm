package PDL::Graphics::Cairo::Axes;

# Drawing of the queued plot commands: lines, markers, error bars, fills, reference lines and spans.
# Part of PDL::Graphics::Cairo::Axes, split out of Axes.pm (P:G:C31): the
# subs below are methods of the same package, and _render_cmd (Axes.pm) calls
# them through %RENDER. The API methods that queue the commands stay in Axes.pm.
# Loaded at the end of Axes.pm, after its imports and constants.

use strict;
use warnings;
no warnings "redefine";

sub _render_line {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $xd = $tr->x($cmd->{x});
    my $yd = $tr->y($cmd->{y});
    $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
    $b->set_linewidth($cmd->{lw});
    $b->set_linestyle($cmd->{linestyle}, $cmd->{lw});
    $b->polyline($xd, $yd);
    $b->set_linestyle('solid');
    # marker: marker引数が指定されていれば各点にマーカーを描く
    if (defined $cmd->{marker}) {
        my $fill = $cmd->{fill} // 1;
        my $ms   = $cmd->{ms}   // 4;
        $b->set_linewidth(0.8);
        for my $i (0 .. $cmd->{x}->nelem - 1) {
            $b->marker($xd->at($i), $yd->at($i), $ms, $cmd->{marker}, $fill);
        }
        $b->set_linewidth(1.5);
    }
}

sub _render_scatter {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $cmap  = defined($cmd->{cdata})
        ? $self->_resolve_cmap($cmd->{cmap}) : undef;
    my ($cdmin,$cdmax);
    if ($cmap) {
        ($cdmin,$cdmax) = $cmd->{cdata}->minmax;
    }
    for my $i (0 .. $cmd->{x}->nelem - 1) {
        my $xp = $tr->x(pdl($cmd->{x}->at($i)))->at(0);
        my $yp = $tr->y(pdl($cmd->{y}->at($i)))->at(0);
        my @c;
        if ($cmap) {
            @c = $cmap->rgb_norm($cmd->{cdata}->at($i), $cdmin, $cdmax);
        } else {
            @c = @{$cmd->{color}};
        }
        $b->set_color(@c, $cmd->{alpha});
        $b->set_linewidth(0.5);
        # matplotlib s = area in pt^2, radius = sqrt(s/pi)
        my $radius = sqrt($cmd->{size} / 3.14159265) || 1;
        my $fill = $cmd->{fill} // 1;
        $b->marker($xp, $yp, $radius, $cmd->{marker}, $fill);
    }
}

sub _render_errorbar {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    #

    my $xd = $tr->x($cmd->{x});
    my $yd = $tr->y($cmd->{y});
    $b->set_color(@{$cmd->{color}});
    if ($cmd->{lw} > 0) {          # lw => 0: points not joined
        $b->set_linewidth($cmd->{lw});
        $b->polyline($xd, $yd);
    }
    #

    for my $i (0 .. $cmd->{x}->nelem - 1) {
        my $fill = $cmd->{fill} // 1;
        $b->marker($xd->at($i), $yd->at($i), $cmd->{ms}, $cmd->{marker}, $fill);
    }
    #

    if (defined $cmd->{yerr}) {
        $b->set_linewidth(1.0);
        for my $i (0 .. $cmd->{x}->nelem - 1) {
            my $xe = $xd->at($i);
            my $ye = $yd->at($i);
            my $yn = $cmd->{x}->nelem;
            my $en = $cmd->{yerr}->nelem;
            # (nelem==1)broadcast2*nlo/hi
            my $elo = $en == 1          ? $cmd->{yerr}->at(0)
                    : $en == 2 * $yn    ? $cmd->{yerr}->at($i)
                    :                     $cmd->{yerr}->at($i);
            my $ehi = $en == 1          ? $cmd->{yerr}->at(0)
                    : $en == 2 * $yn    ? $cmd->{yerr}->at($yn + $i)
                    :                     $cmd->{yerr}->at($i);
            my $y_lo = $tr->y(pdl($cmd->{y}->at($i) + $ehi))->at(0);
            my $y_hi = $tr->y(pdl($cmd->{y}->at($i) - $elo))->at(0);
            $b->errorbar_y($xe, $ye,
                $ye - $y_lo,   # lo in screen
                $y_hi - $ye,   # hi in screen
                $cmd->{capsize});
        }
    }
    #  xerr  yerr

    if (defined $cmd->{xerr}) {
        $b->set_linewidth(1.0);
        for my $i (0 .. $cmd->{x}->nelem - 1) {
            my $xe = $xd->at($i);
            my $ye = $yd->at($i);
            my $xn = $cmd->{x}->nelem;
            my $en = $cmd->{xerr}->nelem;
            my $elo = $en == 1          ? $cmd->{xerr}->at(0)
                    : $en == 2 * $xn    ? $cmd->{xerr}->at($i)
                    :                     $cmd->{xerr}->at($i);
            my $ehi = $en == 1          ? $cmd->{xerr}->at(0)
                    : $en == 2 * $xn    ? $cmd->{xerr}->at($xn + $i)
                    :                     $cmd->{xerr}->at($i);
            my $x_lo = $tr->x(pdl($cmd->{x}->at($i) - $elo))->at(0);
            my $x_hi = $tr->x(pdl($cmd->{x}->at($i) + $ehi))->at(0);
            $b->errorbar_x($xe, $ye,
                $xe - $x_lo,   # lo in screen
                $x_hi - $xe,   # hi in screen
                $cmd->{capsize});
        }
    }
}

sub _render_fill_between {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    #  →  → polygon
    # mask が指定されている場合: 連続した True 区間ごとに polygon を分割して描く。
    # mask なし: 従来通り全区間を1つの polygon で描く。
    my $x  = $cmd->{x};
    my $y1 = $cmd->{y1};
    my $y2 = $cmd->{y2};
    $b->set_color(@{$cmd->{color}}, $cmd->{alpha});

    if (defined $cmd->{mask}) {
        my $mask = $cmd->{mask};
        $mask = pdl($mask) unless $mask->isa('PDL');
        my $n = $x->nelem;
        # 連続した True 区間を抽出して、それぞれ polygon を描く
        my $in_seg = 0;
        my (@seg_x, @seg_y1, @seg_y2);
        for my $i (0 .. $n-1) {
            if ($mask->at($i)) {
                push @seg_x,  $x->at($i);
                push @seg_y1, $y1->at($i);
                push @seg_y2, $y2->at($i);
                $in_seg = 1;
            } else {
                if ($in_seg && @seg_x) {
                    my $xs  = pdl(@seg_x);
                    my $ys1 = pdl(@seg_y1);
                    my $ys2 = pdl(@seg_y2);
                    my $xf  = $xs->append($xs->slice("-1:0:-1"));
                    my $yf  = $ys1->append($ys2->slice("-1:0:-1"));
                    $b->filled_polygon($tr->x($xf), $tr->y($yf));
                    @seg_x = @seg_y1 = @seg_y2 = ();
                }
                $in_seg = 0;
            }
        }
        # 末尾まで True だった区間
        if ($in_seg && @seg_x) {
            my $xs  = pdl(@seg_x);
            my $ys1 = pdl(@seg_y1);
            my $ys2 = pdl(@seg_y2);
            my $xf  = $xs->append($xs->slice("-1:0:-1"));
            my $yf  = $ys1->append($ys2->slice("-1:0:-1"));
            $b->filled_polygon($tr->x($xf), $tr->y($yf));
        }
    } else {
        # mask なし: 従来通り
        my $n  = $x->nelem;
        my $xf = $x->append($x->slice("-1:0:-1"));
        my $yf = $y1->append($y2->slice("-1:0:-1"));
        my $xd = $tr->x($xf);
        my $yd = $tr->y($yf);
        $b->filled_polygon($xd, $yd);
    }
}

sub _render_step {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    #

    my @xs = list($cmd->{x});
    my @ys = list($cmd->{y});
    my (@sx, @sy);
    if ($cmd->{where} eq 'pre') {
        for my $i (0 .. $#xs) {
            if ($i > 0) { push @sx, $xs[$i]; push @sy, $ys[$i-1]; }
            push @sx, $xs[$i]; push @sy, $ys[$i];
        }
    } else {  # post
        for my $i (0 .. $#xs) {
            push @sx, $xs[$i]; push @sy, $ys[$i];
            if ($i < $#xs) { push @sx, $xs[$i+1]; push @sy, $ys[$i]; }
        }
    }
    my $xd = $tr->x(pdl(@sx));
    my $yd = $tr->y(pdl(@sy));
    $b->set_color(@{$cmd->{color}}, 1.0);
    $b->set_linewidth($cmd->{lw});
    $b->set_linestyle($cmd->{linestyle}, $cmd->{lw});
    $b->polyline($xd, $yd);
    $b->set_linestyle('solid');
}

sub _render_stem {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $baseline_y = $tr->y(pdl(0))->at(0);
    $b->set_color(@{$cmd->{color}});
    $b->set_linewidth($cmd->{lw});
    for my $i (0 .. $cmd->{x}->nelem-1) {
        my $xp = $tr->x(pdl($cmd->{x}->at($i)))->at(0);
        my $yp = $tr->y(pdl($cmd->{y}->at($i)))->at(0);
        $b->line_seg($xp, $baseline_y, $xp, $yp);
        $b->marker($xp, $yp, $cmd->{ms}, 'o', 1);
    }
    #

    $b->set_linewidth(1.5);
    $b->line_seg($ml, $baseline_y, $mr, $baseline_y);
}

sub _render_hline {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $yp = $tr->y(pdl($cmd->{y}))->at(0);
    $b->set_color(@{$cmd->{color}});
    $b->set_linewidth($cmd->{lw});
    $b->set_linestyle($cmd->{ls}, $cmd->{lw});
    $b->line_seg($ml, $yp, $mr, $yp);
    $b->set_linestyle('solid');
}

sub _render_vline {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $xp = $tr->x(pdl($cmd->{x}))->at(0);
    $b->set_color(@{$cmd->{color}});
    $b->set_linewidth($cmd->{lw});
    $b->set_linestyle($cmd->{ls}, $cmd->{lw});
    $b->line_seg($xp, $mt, $xp, $mb);
    $b->set_linestyle('solid');
}

sub _render_vspan {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $x1p = $tr->x(pdl($cmd->{x1}))->at(0);
    my $x2p = $tr->x(pdl($cmd->{x2}))->at(0);
    $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
    $b->rect_fill($x1p, $mt, $x2p - $x1p, $mb - $mt);
}

sub _render_hspan {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $y1p = $tr->y(pdl($cmd->{y2}))->at(0);
    my $y2p = $tr->y(pdl($cmd->{y1}))->at(0);
    $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
    $b->rect_fill($ml, $y1p, $mr - $ml, $y2p - $y1p);
}

1;
