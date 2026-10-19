package PDL::Graphics::Cairo::Axes;

# Drawing of the queued plot commands: text, annotations and the PGPLOT-compatible text and ticks.
# Part of PDL::Graphics::Cairo::Axes, split out of Axes.pm (P:G:C31): the
# subs below are methods of the same package, and _render_cmd (Axes.pm) calls
# them through %RENDER. The API methods that queue the commands stay in Axes.pm.
# Loaded at the end of Axes.pm, after its imports and constants.

use strict;
use warnings;
no warnings "redefine";

sub _render_annot {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    $b->set_color(@{$cmd->{color}});
    $b->set_font(size => $cmd->{size});
    my $xd = $tr->x(pdl($cmd->{x}))->at(0);
    my $yd = $tr->y(pdl($cmd->{y}))->at(0);
    # 複数行対応: "a\nb" は _text_ml が行分割・行送り・valign 縦センタリング
    # まで面倒を見る。単一行はそのまま backend text() に素通し(後方互換)。
    $self->_text_ml($b, $xd, $yd, $cmd->{str},
        align        => $cmd->{align},
        valign       => $cmd->{valign},
        angle        => $cmd->{angle},
        size         => $cmd->{size},
        line_spacing => $cmd->{line_spacing});
}

sub _render_pgmtxt {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    # PGPLOT pgmtxt :
    # side: T=, B=, L=, R=
    # disp: =, =
    # coord:  0()1()
    # fjust:  0= coord , 0.5=, 1.0= coord 
    my $side  = $cmd->{side};
    my $coord = $cmd->{coord} // 0.5;
    my $fjust = $cmd->{fjust} // 0.5;
    my $disp  = $cmd->{disp} // 0;
    my $ch    = $cmd->{ch}   // 1.0;
    #

    # pgsch(1)=, pgsch(2)=, pgsch(4)=
    # 6x6 160px: ch=1→8px, ch=2→9px, ch=4→11px 
    my $pw_px = $mr - $ml;
    my $ph_px = $mb - $mt;
    my $panel_min = $pw_px < $ph_px ? $pw_px : $ph_px;
    # pgsch(ch) → 
    # ch=1: 8px, ch=2: 9px, ch=4: 11px 
    # (6x6)
    my $panel_scale = $panel_min > 150 ? 1.0 : $panel_min / 150.0;
    my $fs_base = 8;
    my $fs = int($fs_base + ($ch - 1) * $panel_scale * 1.0);
    $fs = 7  if $fs < 7;
    $fs = 10 if $fs > 10;

    # fjust → Cairo  align
    # fjust: 0=, 0.5=, 1=  coord 
    # → Cairo  align 
    my $align = $fjust < 0.25 ? 'left' : $fjust > 0.75 ? 'right' : 'center';

    my ($xp, $yp, $valign);
    my $pw = $mr - $ml;
    my $ph = $mb - $mt;

    if ($side eq 'T') {
        # PGPLOT: side=T 2:
        # 1) : pgmtxt("TR", -1, 0.1, 1.0, $ch)
        #    → coord=0.1(), fjust=1.0()
        # 2) : pgmtxt("T", -1/-2/-3/-4, 0, 0.0, text)
        #    → coord=0, fjust=0()
        #    → disp=-N  N
        # : fs + 3px
        my $line_h = $fs + 3;
        if ($fjust < 0.1 && $coord < 0.05) {
            # : disp 
            # disp=-1 → 1(), disp=-2 → 2...
            my $row = abs($disp) - 1;
            $xp     = $ml + 2;
            $align  = 'left';
            #  ()
            $yp     = $mt + $row * $line_h + 2;
            $valign = 'top';
        } else {
            # : 
            $xp     = $ml + 2;
            $align  = 'left';
            $yp     = $mt - 1;
            $valign = 'bottom';
        }
    } elsif ($side eq 'B') {
        $xp = $ml + $pw * $coord;
        $align  = $fjust < 0.25 ? 'left' : $fjust > 0.75 ? 'right' : 'center';
        $yp = $mb - abs($disp) * ($fs + 1);
        $valign = 'bottom';
    } elsif ($side eq 'L') {
        $yp = $mb - $ph * $coord;
        $xp = $ml + abs($disp) * ($fs + 1);
        $align  = $fjust < 0.25 ? 'left' : $fjust > 0.75 ? 'right' : 'center';
        $valign = 'middle';
    } elsif ($side eq 'R') {
        $yp = $mb - $ph * $coord;
        $xp = $mr - abs($disp) * ($fs + 1);
        $align  = $fjust < 0.25 ? 'right' : $fjust > 0.75 ? 'left' : 'center';
        $valign = 'middle';
    } else {
        $xp = ($ml+$mr)/2; $yp = ($mt+$mb)/2;
        $align = 'center'; $valign = 'middle';
    }
    $b->set_color(@{$cmd->{color}});
    $b->set_font(size => $fs);
    $b->text($xp, $yp, $cmd->{text},
        align  => $align,
        valign => $valign,
    );
}

sub _render_pgtick {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    # PGPLOT cpgtick: ワールド軸 (x1,y1)-(x2,y2) 上の割合 v の位置に、
    # デバイス上で軸に直交する目盛りを描く。tikl/tikr/disp は文字高
    # (=ラベルのフォントサイズ px)の倍率。
    my $ch = $cmd->{ch} // 1.0;
    # 文字高(px)は pgmtxt と同じ算出でラベル・目盛り長を揃える
    my $pw_px = $mr - $ml;
    my $ph_px = $mb - $mt;
    my $panel_min = $pw_px < $ph_px ? $pw_px : $ph_px;
    my $panel_scale = $panel_min > 150 ? 1.0 : $panel_min / 150.0;
    my $fs = int(8 + ($ch - 1) * $panel_scale * 1.0);
    $fs = 7  if $fs < 7;
    $fs = 10 if $fs > 10;
    my $chh = $fs;   # 文字高 ≈ フォントサイズ(px)

    # 軸端点と目盛り位置(デバイスpx)
    my $X1 = $tr->x(pdl($cmd->{x1}))->at(0);
    my $Y1 = $tr->y(pdl($cmd->{y1}))->at(0);
    my $X2 = $tr->x(pdl($cmd->{x2}))->at(0);
    my $Y2 = $tr->y(pdl($cmd->{y2}))->at(0);
    my $v  = $cmd->{v};
    my $Px = $X1 + $v * ($X2 - $X1);
    my $Py = $Y1 + $v * ($Y2 - $Y1);

    # デバイス空間の単位進行方向と法線
    #   right 法線 = (-uy, ux)  … 左→右水平軸なら下側
    #   left  法線 = ( uy,-ux)  … 同上で上側
    my $Dx = $X2 - $X1;
    my $Dy = $Y2 - $Y1;
    my $len = sqrt($Dx*$Dx + $Dy*$Dy) || 1;
    my $ux = $Dx / $len;
    my $uy = $Dy / $len;
    my ($nrx, $nry) = (-$uy,  $ux);   # right
    my ($nlx, $nly) = ( $uy, -$ux);   # left

    my $tl = ($cmd->{tikl} // 0) * $chh;
    my $tr_ = ($cmd->{tikr} // 0) * $chh;
    my $ax_ = $Px + $tl  * $nlx;  my $ay_ = $Py + $tl  * $nly;   # 左端
    my $bx_ = $Px + $tr_ * $nrx;  my $by_ = $Py + $tr_ * $nry;   # 右端

    $b->set_color(@{$cmd->{color}});
    $b->set_linewidth($cmd->{lw} // 1.0);
    $b->polyline(pdl($ax_, $bx_), pdl($ay_, $by_));

    # ラベル（str が非空のとき）: right 側に disp だけ変位、orient 回転
    my $str = $cmd->{str};
    if (defined $str && $str ne '') {
        my $dp = ($cmd->{disp} // 0) * $chh + $tr_ + 2;  # 目盛り先端の少し外
        my $lx = $Px + $dp * $nrx;
        my $ly = $Py + $dp * $nry;
        $b->set_font(size => $fs);
        $b->text($lx, $ly, $str,
            align  => 'center',
            valign => 'middle',
            angle  => ($cmd->{orient} // 0),
        );
    }
}

sub _render_annotate {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $axp = $tr->x(pdl($cmd->{ax}))->at(0);
    my $ayp = $tr->y(pdl($cmd->{ay}))->at(0);
    my $txp = $tr->x(pdl($cmd->{tx}))->at(0);
    my $typ = $tr->y(pdl($cmd->{ty}))->at(0);

    # テキストと矢印の重なりを避けるため、テキストの少し外側
    # (xy から離れる方向) にマージンを置き、矢印はそこから始める。
    # 矢印の先端側も xy にぴったり着けず、矢じり分だけ手前で止める。
    my $dx_full = $axp - $txp;
    my $dy_full = $ayp - $typ;
    my $dist    = sqrt($dx_full**2 + $dy_full**2) || 1;
    my $ux      = $dx_full / $dist;
    my $uy      = $dy_full / $dist;

    my $text_gap  = 6;    # テキスト基準点と矢印開始点の隙間(px)
    my $arrow_gap = 10;   # 矢印先端とデータ点の隙間(px、矢じり分)

    my $arrow_start_x = $txp + $ux * $text_gap;
    my $arrow_start_y = $typ + $uy * $text_gap;
    my $arrow_end_x   = $axp - $ux * $arrow_gap;
    my $arrow_end_y   = $ayp - $uy * $arrow_gap;

    #

    if ($cmd->{arrow}) {
        $b->set_color(@{$cmd->{color}});
        $b->set_linewidth(1.0);
        $b->line_seg($arrow_start_x, $arrow_start_y, $arrow_end_x, $arrow_end_y);
        #

        my $pi  = 3.14159265358979;
        my $ang = atan2($arrow_end_y - $arrow_start_y, $arrow_end_x - $arrow_start_x);
        my $hs  = 8;
        my $ha  = 0.4;
        my @hx  = ($arrow_end_x,
                    $arrow_end_x - $hs*cos($ang-$ha),
                    $arrow_end_x - $hs*cos($ang+$ha));
        my @hy  = ($arrow_end_y,
                    $arrow_end_y - $hs*sin($ang-$ha),
                    $arrow_end_y - $hs*sin($ang+$ha));
        $b->set_color(@{$cmd->{color}});
        $b->filled_polygon(pdl(@hx), pdl(@hy));
    }

    #

    $b->set_color(@{$cmd->{color}});
    $b->set_font(size => $cmd->{size});
    $b->text($txp, $typ, $cmd->{text}, align=>'left', valign=>'bottom');
}

1;
