package PDL::Graphics::Cairo::Axes;

# Drawing of the queued plot commands: bars, histograms and pies.
# Part of PDL::Graphics::Cairo::Axes, split out of Axes.pm (P:G:C31): the
# subs below are methods of the same package, and _render_cmd (Axes.pm) calls
# them through %RENDER. The API methods that queue the commands stay in Axes.pm.
# Loaded at the end of Axes.pm, after its imports and constants.

use strict;
use warnings;
no warnings "redefine";

sub _render_bar {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $n = $cmd->{x}->nelem;
    for my $i (0 .. $n-1) {
        my $xc = $cmd->{x}->at($i);
        my $h  = $cmd->{height}->at($i);
        my $w  = ref($cmd->{width}) ? $cmd->{width}->at($i) : $cmd->{width};
        my $bo = ref($cmd->{bottom})? $cmd->{bottom}->at($i): $cmd->{bottom};

        my $xp = $tr->x(pdl($xc - $w/2))->at(0);
        my $yp = $tr->y(pdl($bo + $h))->at(0);
        my $wp = $tr->x(pdl($xc + $w/2))->at(0) - $xp;
        my $hp = $tr->y(pdl($bo))->at(0)         - $yp;

        $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
        $b->rect_fill($xp, $yp, $wp, $hp);
        $b->set_color(@{$cmd->{edge}});
        $b->set_linewidth(0.5);
        $b->rect_stroke($xp, $yp, $wp, $hp);

        # yerr: バー上端(bottom+height)を中心に誤差バーを描く。
        # errorbar()と同じ Driver::Cairo::errorbar_y() を再利用する。
        if (defined $cmd->{yerr_lo} && defined $cmd->{yerr_hi}) {
            my $ylo_v = $cmd->{yerr_lo}->nelem > 1 ? $cmd->{yerr_lo}->at($i) : $cmd->{yerr_lo}->at(0);
            my $yhi_v = $cmd->{yerr_hi}->nelem > 1 ? $cmd->{yerr_hi}->at($i) : $cmd->{yerr_hi}->at(0);
            # データ座標でのバー上端
            my $bar_top_data = $bo + $h;
            # 画面座標に変換した、上端・下端それぞれの誤差バー先端位置
            my $cx_screen = $tr->x(pdl($xc))->at(0);
            my $y_top_screen = $tr->y(pdl($bar_top_data))->at(0);
            my $y_lo_screen  = $tr->y(pdl($bar_top_data - $ylo_v))->at(0);
            my $y_hi_screen  = $tr->y(pdl($bar_top_data + $yhi_v))->at(0);
            # errorbar_y は (xp, yp, ye_lo, ye_hi, capw) を画面座標の
            # オフセット(px)として受け取るため、ここでpx差分に変換する。
            my $ye_lo_px = $y_lo_screen - $y_top_screen;  # 下方向（正値）
            my $ye_hi_px = $y_top_screen - $y_hi_screen;  # 上方向（正値）
            $b->set_color(0,0,0);
            $b->set_linewidth(1.5);
            $b->errorbar_y($cx_screen, $y_top_screen, $ye_lo_px, $ye_hi_px, $cmd->{capsize});
        }
    }
}

sub _render_barh {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $n = $cmd->{y}->nelem;
    for my $i (0 .. $n-1) {
        my $yc = $cmd->{y}->at($i);
        my $wv = $cmd->{width}->at($i);
        my $hv = ref($cmd->{height})? $cmd->{height}->at($i): $cmd->{height};
        my $lo = ref($cmd->{left})  ? $cmd->{left}->at($i)  : $cmd->{left};

        my $xp = $tr->x(pdl($lo))->at(0);
        my $yp = $tr->y(pdl($yc + $hv/2))->at(0);
        my $wp = $tr->x(pdl($lo + $wv))->at(0) - $xp;
        my $hp = $tr->y(pdl($yc - $hv/2))->at(0) - $yp;

        $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
        $b->rect_fill($xp, $yp, $wp, $hp);
        $b->set_color(@{$cmd->{edge}});
        $b->set_linewidth(0.5);
        $b->rect_stroke($xp, $yp, $wp, $hp);
    }
}

sub _render_hist {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $n = $cmd->{edges}->nelem - 1;
    for my $i (0 .. $n-1) {
        my $x0 = $tr->x(pdl($cmd->{edges}->at($i)))->at(0);
        my $x1 = $tr->x(pdl($cmd->{edges}->at($i+1)))->at(0);
        my $y0 = $tr->y(pdl(0))->at(0);
        my $y1 = $tr->y(pdl($cmd->{counts}->at($i)))->at(0);
        $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
        $b->rect_fill($x0, $y1, $x1-$x0, $y0-$y1);
        $b->set_color(0,0,0);
        $b->set_linewidth(0.5);
        $b->rect_stroke($x0, $y1, $x1-$x0, $y0-$y1);
    }
}

sub _render_pie {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    # pie  tr
    my $cx = ($ml + $mr) / 2;
    my $cy = ($mt + $mb) / 2;
    my $r  = (PDL::Graphics::Cairo::Axes::_min($mr-$ml, $mb-$mt) / 2) * 0.85;

    my @colors = (
        [0.122,0.467,0.706],[1.000,0.498,0.055],[0.173,0.627,0.173],
        [0.839,0.153,0.157],[0.580,0.404,0.741],[0.549,0.337,0.294],
        [0.890,0.467,0.761],[0.498,0.498,0.498],[0.737,0.741,0.133],
        [0.090,0.745,0.812],
    );

    my $pi    = 3.14159265358979;
    my $angle = $cmd->{startangle} * $pi / 180;
    my $total = $cmd->{total};

    for my $i (0 .. $#{ $cmd->{sizes} }) {
        my $frac  = $cmd->{sizes}[$i] / $total;
        my $sweep = $frac * 2 * $pi;
        my $exp   = $cmd->{explode}[$i] // 0;
        my $mid   = $angle + $sweep / 2;
        my $ecx   = $cx + $exp * $r * cos($mid);
        my $ecy   = $cy - $exp * $r * sin($mid);

        my @c = @{ $colors[$i % scalar @colors] };
        $b->set_color(@c, 0.85);

        #

        my $n_seg = int($sweep / (2*$pi) * 60) + 3;
        $n_seg = 3 if $n_seg < 3;
        my @px = ($ecx);
        my @py = ($ecy);
        for my $k (0 .. $n_seg) {
            my $a = $angle + $k * $sweep / $n_seg;
            push @px, $ecx + $r * cos($a);
            push @py, $ecy - $r * sin($a);
        }
        push @px, $ecx; push @py, $ecy;
        $b->filled_polygon(pdl(@px), pdl(@py));

        #

        $b->set_color(1,1,1);
        $b->set_linewidth(1.5);
        my @bx = ($ecx);
        my @by = ($ecy);
        for my $k (0 .. $n_seg) {
            my $a = $angle + $k * $sweep / $n_seg;
            push @bx, $ecx + $r * cos($a);
            push @by, $ecy - $r * sin($a);
        }
        push @bx, $ecx; push @by, $ecy;
        $b->polyline(pdl(@bx), pdl(@by));

        #

        if ($cmd->{labels}[$i] ne '') {
            my $la = $angle + $sweep/2;
            my $lx = $ecx + ($r * 1.12) * cos($la);
            my $ly = $ecy - ($r * 1.12) * sin($la);
            my $ha = cos($la) > 0 ? 'left' : 'right';
            $b->set_color(0,0,0);
            $b->set_font(size => 10);
            $b->text($lx, $ly, $cmd->{labels}[$i],
                align => $ha, valign => 'middle');
        }

        # autopct
        if ($cmd->{autopct} ne '') {
            my $pct_str = sprintf($cmd->{autopct}, $frac * 100);
            my $la  = $angle + $sweep/2;
            my $plx = $ecx + $r * 0.6 * cos($la);
            my $ply = $ecy - $r * 0.6 * sin($la);
            $b->set_color(1,1,1);
            $b->set_font(size => 9, weight => 'bold');
            $b->text($plx, $ply, $pct_str, align=>'center', valign=>'middle');
        }

        $angle += $sweep;
    }
}

1;
