package PDL::Graphics::Cairo::Axes;

# Everything drawn around the plot rectangle: grid, frame, tick marks and
# numbers, twin axes, title and axis labels, legend and colorbar, and the
# measurement tight_layout uses for them (_label_room, _twin_yaxis_room).
# Part of PDL::Graphics::Cairo::Axes, split out of Axes.pm (P:G:C31): the
# subs below are methods and functions of the same package. Loaded at the
# end of Axes.pm, after its imports and constants.

use strict;
use warnings;
no warnings "redefine";

# ------------------------------------------------------------------
sub _draw_grid {
    my ($self, $b, $tr, $ml,$mt,$mr,$mb) = @_;
    my @xtks = $self->_xticks
        ? @{ $self->_xticks }
        : nice_ticks($self->xmin, $self->xmax, 6);
    my @ytks = $self->_yticks
        ? @{ $self->_yticks }
        : nice_ticks($self->ymin, $self->ymax, 6);

    for my $v (@xtks) {
        my $xp = $tr->x(pdl($v))->at(0);
        $b->grid_line_v($xp, $mt, $mb, $self->grid_color);
    }
    for my $v (@ytks) {
        my $yp = $tr->y(pdl($v))->at(0);
        $b->grid_line_h($ml, $mr, $yp, $self->grid_color);
    }
}


# ------------------------------------------------------------------
# _draw_twin_yaxis — twinx Y
# ------------------------------------------------------------------
# ------------------------------------------------------------------
# _draw_twin_xaxis — twiny 用: 上端に第2X軸目盛りを描画
# ------------------------------------------------------------------
sub _draw_twin_xaxis {
    my ($self, $b, $tr, $ml,$mt,$mr,$mb) = @_;

    warn sprintf("[DEBUG _draw_twin_xaxis] mt=%s xlabel='%s'\n",
        $mt, $self->xlabel) if $ENV{PGC_DEBUG_LABELS};

    $b->set_color(0,0,0);
    $b->set_linewidth(1.0);
    $b->set_linestyle('solid');

    # 上端ライン
    $b->line_seg($ml, $mt, $mr, $mt);

    # X 目盛り計算
    my @xtks;
    if ($self->_xticks) {
        @xtks = @{ $self->_xticks };
    } elsif ($self->xscale eq 'log') {
        my $sc = PDL::Graphics::Cairo::Scale::Log->new;
        @xtks = $sc->nice_ticks($self->xmin, $self->xmax);
    } else {
        @xtks = nice_ticks($self->xmin, $self->xmax, 6);
    }
    my @xlbs = $self->_xticklabels ? @{ $self->_xticklabels }
        : ($self->xscale eq 'log')
            ? do { my $sc = PDL::Graphics::Cairo::Scale::Log->new;
                   map { $sc->fmt_tick($_) } @xtks }
            : map { _fmt_tick($_) } @xtks;

    $b->set_font(size => 10);
    my $prev_xp_right = -9999;  # 直前に描いたラベルの右端(px)
    for my $i (0 .. $#xtks) {
        my $v   = $xtks[$i];
        my $eps = ($self->xmax - $self->xmin) * 0.001 + 0.001;
        next if $v < $self->xmin - $eps || $v > $self->xmax + $eps;
        my $xp = $tr->x(pdl($v))->at(0);
        next if $xp < $ml - 1 || $xp > $mr + 1;

        # ラベル幅に基づく重なり判定。 [PGC10-ROUND3-XTICK-FIX]
        # 固定24px間隔ではなく、実際の文字列幅(text_width)から
        # 「中心からの半幅+左右余白」を計算し、直前ラベルの右端と
        # 比較する。log軸では桁が増えるほど文字数が増える
        # (例: "100000" は "1" より明らかに幅が広い) ため、
        # 固定幅判定だと長いラベルが重なって判読不能になる。
        my $label_w   = eval { $b->text_width($xlbs[$i]) } // 16;
        my $half_w    = $label_w / 2;
        my $label_pad = 4;   # ラベル間の最小余白(px)
        my $xp_left   = $xp - $half_w;
        next if $xp_left < $prev_xp_right + $label_pad;

        # 上向き tick (mt から外側へ)
        $b->line_seg($xp, $mt, $xp, $mt - 4);
        $b->set_color(_fg());
        $b->text($xp, $mt - 6, $xlbs[$i], align=>'center', valign=>'bottom');
        $prev_xp_right = $xp + $half_w;
    }

    # 上X軸ラベル
    if ($self->xlabel ne '') {
        $b->set_font(size => 11);
        $b->text(($ml+$mr)/2, $mt - 28, $self->xlabel,
            align=>'center', valign=>'bottom');
    }
}

# Right axis of a twinx: tick numbers at mr+TWIN_YTICK_X, label past them.
use constant { TWIN_YTICK_FS => 10, TWIN_YTICK_X => 6,
               TWIN_YLABEL_FS => 11, TWIN_YLABEL_GAP => 6 };
sub _draw_twin_yaxis {
    my ($self, $b, $tr, $ml,$mt,$mr,$mb) = @_;

    $b->set_color(0,0,0);
    $b->set_linewidth(1.0);
    $b->set_linestyle('solid');

    #

    $b->line_seg($mr, $mt, $mr, $mb);

    # Y 
    my @ytks;
    if ($self->_yticks) {
        @ytks = @{ $self->_yticks };
    } elsif ($self->yscale eq 'log') {
        my $sc = PDL::Graphics::Cairo::Scale::Log->new;
        @ytks = $sc->nice_ticks($self->ymin, $self->ymax);
    } else {
        @ytks = nice_ticks($self->ymin, $self->ymax, 6);
    }
    my @ylbs;
    if ($self->_yticklabels) {
        @ylbs = @{ $self->_yticklabels };
    } elsif ($self->_yformatter) {
        my $fmt = $self->_yformatter;
        @ylbs = map { $fmt->($ytks[$_], $_) } 0..$#ytks;
    } elsif ($self->yscale eq 'log') {
        my $sc = PDL::Graphics::Cairo::Scale::Log->new;
        @ylbs = map { $sc->fmt_tick($_) } @ytks;
    } else {
        @ylbs = map { _fmt_tick($_) } @ytks;
    }

    my $min_ygap = 14;
    my ($ylo, $yhi) = ($self->ymin, $self->ymax);
    my $prev_yp = $self->{_y_reversed} ? -9999 : 9999;
    my $wmax = 0;     # widest tick number drawn: the right label goes past it
    $b->set_font(size => TWIN_YTICK_FS);
    for my $i (0 .. $#ytks) {
        my $v   = $ytks[$i];
        my $eps = ($yhi - $ylo) * 0.001 + 0.001;
        next if $v < $ylo - $eps || $v > $yhi + $eps;
        my $yp = $tr->y(pdl($v))->at(0);
        next if $yp < $mt - 1 || $yp > $mb + 1;

        $b->set_color(_fg());
        $b->line_seg($mr, $yp, $mr+4, $yp);

        # label overlap guard (same logic as _draw_frame Y section)
        # abs() で正順・逆順どちらの yticks 配列にも対応
        next if abs($yp - $prev_yp) < $min_ygap;
        $b->text($mr + TWIN_YTICK_X, $yp, $ylbs[$i], align=>'left', valign=>'middle');
        my $w = eval { $b->text_width($ylbs[$i]) } // 0;
        $wmax = $w if $w > $wmax;
        $prev_yp = $yp;
    }

    # 右の Y ラベル(set_right_ylabel、無ければ twin の ylabel)。
    # angle=>90(正)を使う。-90だと文字が上から下に読む向きになり、
    # 通常のylabel(_draw_labels内、angle=>$rot、デフォルト90)と
    # 反転して見えてしまう(ユーザー指摘により発覚)。
    # 目盛り数字の右端から TWIN_YLABEL_GAP 空けた位置を文字の上端にする
    # (valign=>'top': 縦書きの上端は左側なので、文字は右へ伸びる)。
    # 0.42 までは数字の幅を見ずに mr+20 を下端にしていたため、文字が左へ
    # 伸びて目盛り数字に重なっていた。_twin_yaxis_room が同じ式で余白を見積もる。
    my $rlab = $self->_twin_ylabel_text;
    if ($rlab ne '') {
        $b->set_color(_fg());
        $b->set_font(size => TWIN_YLABEL_FS);
        $b->text($mr + TWIN_YTICK_X + $wmax + TWIN_YLABEL_GAP, ($mt+$mb)/2, $rlab,
            align=>'center', valign=>'top', angle=>90);
    }
}

# The label drawn on the right of a twinx: set_right_ylabel, else its ylabel.
sub _twin_ylabel_text {
    my ($self) = @_;
    for my $l ($self->{_right_ylabel}, $self->ylabel) {
        return $l if defined $l && $l ne '';
    }
    return '';
}

# _twin_yaxis_room($m): room (px) right of the plot rectangle that a twinx
# needs for its tick numbers and right label, measured with $m the same way
# _draw_twin_yaxis places them. Used by Figure::tight_layout on the parent.
sub _twin_yaxis_room {
    my ($self, $m) = @_;
    my @user = ($self->xmin, $self->xmax, $self->ymin, $self->ymax);
    $self->_finalize_range;
    my ($ylo, $yhi) = ($self->ymin, $self->ymax);
    my ($ytks, $ylbs) = $self->_ytick_list;
    $self->xmin($user[0]); $self->xmax($user[1]);
    $self->ymin($user[2]); $self->ymax($user[3]);

    $m->set_font(size => TWIN_YTICK_FS);
    my $eps  = ($yhi - $ylo) * 0.001 + 0.001;
    my $wmax = 0;
    for my $i (0 .. $#$ytks) {
        next if $ytks->[$i] < $ylo - $eps || $ytks->[$i] > $yhi + $eps;
        my ($w) = _text_wh($m, $ylbs->[$i] // '');
        $wmax = $w if $w > $wmax;
    }
    my $room = TWIN_YTICK_X + $wmax;
    my $lab  = $self->_twin_ylabel_text;
    if ($lab ne '') {
        $m->set_font(size => TWIN_YLABEL_FS);
        my (undef, $h) = _text_wh($m, $lab);
        $room += TWIN_YLABEL_GAP + $h;
    }
    # 2 px so the outermost pixels of the glyphs stay inside the figure
    return int($room + 0.999) + 2;
}

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
sub _draw_frame {
    my ($self, $b, $tr, $ml,$mt,$mr,$mb) = @_;

    # セルが極端に小さくなったとき mt>=mb / ml>=mr になり Cairo が壊れた矩形を
    # 描いて全面塗りつぶし（"真っ青"等）になるのを防ぐ
    return if $mt >= $mb - 4 || $ml >= $mr - 4;

    # pgbox 
    my $pb   = $self->{_pgbox};
    my $xopt = $pb ? uc($pb->{xopt}) : 'BCNST';
    my $yopt = $pb ? uc($pb->{yopt}) : 'BCNST';
    my @fc   = ($pb && $pb->{color}) ? @{$pb->{color}} : (_fg());

    $b->set_linewidth(1.5);
    $b->set_linestyle('solid');

    # ============================================================
    # A: y=0 x=0 
    # ============================================================
    my ($x0p, $y0p);

    if ($xopt =~ /A/ && $self->ymin <= 0 && $self->ymax >= 0) {
        $y0p = $tr->y(pdl(0))->at(0);
        if ($y0p >= $mt - 1 && $y0p <= $mb + 1) {
            $b->set_color(@fc);
            $b->line_seg($ml, $y0p, $mr, $y0p);
        }
    }
    $y0p //= $mb;

    if ($yopt =~ /A/ && $self->xmin <= 0 && $self->xmax >= 0) {
        $x0p = $tr->x(pdl(0))->at(0);
        if ($x0p >= $ml - 1 && $x0p <= $mr + 1) {
            $b->set_color(@fc);
            # X(mb+2) mb-1 
            $b->line_seg($x0p, $mt, $x0p, $mb);
        }
    }
    $x0p //= $ml;

    # B/C: 
    if (!$pb || $xopt =~ /[BC]/ || $yopt =~ /[BC]/) {
        $b->set_color(@fc);
        $b->rect_stroke($ml, $mt, $mr-$ml, $mb-$mt);
    }

    # ============================================================
    # X 
    # ============================================================
    my ($xtks_r, $xlbs_r) = $self->_xtick_list;
    my @xtks = @$xtks_r;
    my @xlbs = @$xlbs_r;

    my ($xlo, $xhi) = ($self->xmin, $self->xmax);
    my $prev_xp_right = -9999;  # 直前に描いたラベルの右端(px)。固定24px間隔ではなく
                                 # 実測文字幅に基づく重なり判定に使う（下記参照）。

    for my $i (0 .. $#xtks) {
        my $v    = $xtks[$i];
        my $xeps = ($self->xmax - $self->xmin) * 0.001 + 0.001;
        next if $v < $self->xmin - $xeps || $v > $self->xmax + $xeps;
        my $xp = $tr->x(pdl($v))->at(0);
        next if $xp < $ml - 1 || $xp > $mr + 1;

        # ラベル幅に基づく重なり判定。
        # 固定24px間隔ではなく、実際の文字列幅(text_width)から
        # 「中心からの半幅+左右余白」を計算し、直前ラベルの右端と比較する。
        # log軸では桁が増えるほど文字数が増える(例:"100000"は"1"より明らかに
        # 幅が広い)ため、固定幅判定だと長いラベルが重なって判読不能になる。
        my $label_w   = eval { $b->text_width($xlbs[$i]) } // 16;
        my $half_w    = $label_w / 2;
        my $label_pad = 4;   # ラベル間の最小余白(px)
        my $xp_left   = $xp - $half_w;
        my $overlaps  = $xp_left < $prev_xp_right + $label_pad;

        # T/S: ticks  y=0
        if ($xopt =~ /[TS]/) {
            my $tp     = $self->_tick_params;
            my $tlen   = $tp->{x_length}    // (($xopt =~ /T/) ? 5 : 3);
            my $twid   = $tp->{x_width}     // 1.0;
            my $tdir   = $tp->{x_direction} // 'out';
            my $show_b = $tp->{x_bottom}    // 1;
            my $show_t = $tp->{x_top}       // 0;
            my @tc     = defined($tp->{x_color})
                ? @{ $self->_parse_color($tp->{x_color}) }
                : @fc;
            $b->set_color(@tc);
            $b->set_linewidth($twid);
            my $ya = ($y0p >= $mt && $y0p <= $mb) ? $y0p : $mb;
            if ($show_b) {
                my ($y1,$y2) = $tdir eq 'in'    ? ($ya, $ya - $tlen)
                             : $tdir eq 'inout'  ? ($ya - $tlen/2, $ya + $tlen/2)
                             :                     ($ya, $ya + $tlen);
                $b->line_seg($xp, $y1, $xp, $y2);
            }
            if ($show_t) {
                my $yt = $mt;
                my ($y1,$y2) = $tdir eq 'in'    ? ($yt, $yt + $tlen)
                             : $tdir eq 'inout'  ? ($yt - $tlen/2, $yt + $tlen/2)
                             :                     ($yt, $yt - $tlen);
                $b->line_seg($xp, $y1, $xp, $y2);
            }
            $b->set_linewidth(1.5);
        }

        # N: (mb)
        next if $overlaps;
        if ($xopt =~ /N/) {
            my $tp       = $self->_tick_params;
            my $lsize    = $tp->{x_labelsize}     // 10;
            my $lshow    = $tp->{x_labelbottom}   // 1;
            my $lshow_t  = $tp->{x_labeltop}      // 0;
            # pad: 目盛り線の先端からラベルまでの隙間(px)。
            # matplotlibのデフォルト(xtick.major.pad=3.5pt≈4-5px)相当に
            # 合わせる。以前は16→10だったが、Driver::Cairo::text()の
            # valign='top'実装バグ(2026-06-19修正)により、修正前は
            # ラベルが意図せず上にせり出して詰まって見えていた。
            # バグ修正後は計算式通りの位置に描かれるようになったため、
            # 同じ見た目の隙間を保つには pad 自体を縮める必要がある。
            my $pad      = $tp->{x_pad}           // 4;
            my $rot      = $tp->{x_labelrotation} // $self->{_xtick_rot} // 0;
            my @lc       = defined($tp->{x_labelcolor})
                ? @{ $self->_parse_color($tp->{x_labelcolor}) }
                : @fc;
            my $tlen_eff = $tp->{x_length} // (($xopt =~ /T/) ? 5 : 3);
            my $tdir     = $tp->{x_direction} // 'out';
            my $tick_ext = $tdir eq 'out' ? $tlen_eff
                         : $tdir eq 'inout' ? $tlen_eff/2 : 0;
            if ($lshow) {
                $b->set_color(@lc);
                $b->set_font(size => $lsize);
                $self->_text_ml($b, $xp, $mb + $tick_ext + $pad + 2, $xlbs[$i],
                    align=>'center', valign=>'top', angle=>$rot, size=>$lsize);
            }
            if ($lshow_t) {
                $b->set_color(@lc);
                $b->set_font(size => $lsize);
                $self->_text_ml($b, $xp, $mt - $tick_ext - $pad - 2, $xlbs[$i],
                    align=>'center', valign=>'bottom', angle=>$rot, size=>$lsize);
            }
        }
        $prev_xp_right = $xp + $half_w;
    }

    # ============================================================
    # X minor ticks
    # ============================================================
    if ($self->_minor_ticks_on && $xopt =~ /[TS]/) {
        my $tp     = $self->_tick_params;
        my $tdir   = $tp->{x_direction}    // 'out';
        my $show_b = $tp->{x_bottom}        // 1;
        my $show_t = $tp->{x_top}            // 0;
        my @tc     = defined($tp->{x_color})
            ? @{ $self->_parse_color($tp->{x_color}) } : @fc;
        my $tlen   = $tp->{x_minor_length}
                  // ($tp->{x_length} ? $tp->{x_length} * 0.5 : 2);
        my $twid   = $tp->{x_minor_width}
                  // ($tp->{x_width}  ? $tp->{x_width}  * 0.6 : 0.6);
        my @xminors;

        if ($self->xscale eq 'log') {
            my $lo = POSIX::floor(log(($xlo > 0 ? $xlo : 1e-10))/log(10));
            my $hi = POSIX::floor(log($xhi > 0 ? $xhi : 1)/log(10)) + 1;
            for my $e ($lo .. $hi) {
                for my $m (2..9) {
                    my $v = $m * (10 ** $e);
                    push @xminors, $v
                        if $v > $xlo * 1.001 && $v < $xhi * 0.999;
                }
            }
        } else {
            @xminors = minor_ticks($xlo, $xhi, $self->_minor_n, @xtks);
        }

        $b->set_linewidth($twid);
        $b->set_color(@tc);
        for my $v (@xminors) {
            my $xp = $tr->x(pdl($v))->at(0);
            next if $xp < $ml || $xp > $mr;
            my $ya = ($y0p >= $mt && $y0p <= $mb) ? $y0p : $mb;
            if ($show_b) {
                my ($y1,$y2) = $tdir eq 'in'   ? ($ya, $ya - $tlen)
                             : $tdir eq 'inout' ? ($ya - $tlen/2, $ya + $tlen/2)
                             :                    ($ya, $ya + $tlen);
                $b->line_seg($xp, $y1, $xp, $y2);
            }
            if ($show_t) {
                my $yt = $mt;
                my ($y1,$y2) = $tdir eq 'in'   ? ($yt, $yt + $tlen)
                             : $tdir eq 'inout' ? ($yt - $tlen/2, $yt + $tlen/2)
                             :                    ($yt, $yt - $tlen);
                $b->line_seg($xp, $y1, $xp, $y2);
            }
        }
        $b->set_linewidth(1.5);
    }

    # ============================================================
    # Y 
    # ============================================================
    my ($ytks_r, $ylbs_r) = $self->_ytick_list;
    my @ytks = @$ytks_r;
    my @ylbs = @$ylbs_r;

    my $min_ygap = 14;
    my ($ylo, $yhi) = ($self->ymin, $self->ymax);
    my $prev_yp = $self->{_y_reversed} ? -9999 : 9999;
    for my $i (0 .. $#ytks) {
        my $v   = $ytks[$i];
        my $eps = ($yhi - $ylo) * 0.001 + 0.001;
        next if $v < $ylo - $eps || $v > $yhi + $eps;
        my $yp = $tr->y(pdl($v))->at(0);
        next if $yp < $mt - 1 || $yp > $mb + 1;

        # T/S: ticks  x=0
        if ($yopt =~ /[TS]/) {
            my $tp     = $self->_tick_params;
            my $tlen   = $tp->{y_length}    // (($yopt =~ /T/) ? 5 : 3);
            my $twid   = $tp->{y_width}     // 1.0;
            my $tdir   = $tp->{y_direction} // 'out';
            my $show_l = $tp->{y_left}      // 1;
            my $show_r = $tp->{y_right}     // 0;
            my @tc     = defined($tp->{y_color})
                ? @{ $self->_parse_color($tp->{y_color}) }
                : @fc;
            $b->set_color(@tc);
            $b->set_linewidth($twid);
            my $xa = ($x0p >= $ml && $x0p <= $mr) ? $x0p : $ml;
            if ($show_l) {
                my ($x1,$x2) = $tdir eq 'in'    ? ($xa, $xa + $tlen)
                             : $tdir eq 'inout'  ? ($xa - $tlen/2, $xa + $tlen/2)
                             :                     ($xa, $xa - $tlen);
                $b->line_seg($x1, $yp, $x2, $yp);
            }
            if ($show_r) {
                my $xr = $mr;
                my ($x1,$x2) = $tdir eq 'in'    ? ($xr, $xr - $tlen)
                             : $tdir eq 'inout'  ? ($xr - $tlen/2, $xr + $tlen/2)
                             :                     ($xr, $xr + $tlen);
                $b->line_seg($x1, $yp, $x2, $yp);
            }
            $b->set_linewidth(1.5);
        }

        # N: (ml)
        # abs() で正順・逆順どちらの yticks 配列にも対応
        next if abs($yp - $prev_yp) < $min_ygap;
        if ($yopt =~ /N/) {
            my $tp      = $self->_tick_params;
            my $lsize   = $tp->{y_labelsize}     // 10;
            my $lshow_l = $tp->{y_labelleft}     // 1;
            my $lshow_r = $tp->{y_labelright}    // 0;
            my $pad     = $tp->{y_pad}           // 10;
            my $rot     = $tp->{y_labelrotation} // $self->{_ytick_rot} // 0;
            my @lc      = defined($tp->{y_labelcolor})
                ? @{ $self->_parse_color($tp->{y_labelcolor}) }
                : @fc;
            my $tlen_eff = $tp->{y_length} // (($yopt =~ /T/) ? 5 : 3);
            my $tdir     = $tp->{y_direction} // 'out';
            my $tick_ext = $tdir eq 'out' ? $tlen_eff
                         : $tdir eq 'inout' ? $tlen_eff/2 : 0;
            my $txt_y    = $yp;
            if ($lshow_l) {
                $b->set_color(@lc);
                $b->set_font(size => $lsize);
                $self->_text_ml($b, $ml - $tick_ext - $pad - 2, $txt_y, $ylbs[$i],
                    align=>'right', valign=>'middle', angle=>$rot, size=>$lsize);
                # ylabel 配置時の重なり防止用に、回転なしラベルの最大幅を記録する。
                # 複数行 ("name\n(scale)") では最長行の幅を採る (_text_width_ml)。
                # rot!=0（縦書き等）の場合は左方向の占有幅が変わるため対象外とする。
                if ($rot == 0) {
                    my $w = $self->_text_width_ml($b, $ylbs[$i]);
                    $self->{_y_ticklabel_maxw} = $w
                        if !defined($self->{_y_ticklabel_maxw})
                        || $w > $self->{_y_ticklabel_maxw};
                }
            }
            if ($lshow_r) {
                $b->set_color(@lc);
                $b->set_font(size => $lsize);
                $self->_text_ml($b, $mr + $tick_ext + $pad + 2, $txt_y, $ylbs[$i],
                    align=>'left', valign=>'middle', angle=>$rot, size=>$lsize);
            }
        }
        $prev_yp = $yp;
    }
    # ============================================================
    # Y minor ticks
    # ============================================================
    if ($self->_minor_ticks_on && $yopt =~ /[TS]/) {
        my $tp     = $self->_tick_params;
        my $tdir   = $tp->{y_direction}   // 'out';
        my $show_l = $tp->{y_left}         // 1;
        my $show_r = $tp->{y_right}         // 0;
        my @tc     = defined($tp->{y_color})
            ? @{ $self->_parse_color($tp->{y_color}) } : @fc;
        my $tlen   = $tp->{y_minor_length}
                  // ($tp->{y_length} ? $tp->{y_length} * 0.5 : 2);
        my $twid   = $tp->{y_minor_width}
                  // ($tp->{y_width}  ? $tp->{y_width}  * 0.6 : 0.6);
        my @yminors;

        if ($self->yscale eq 'log') {

            my $lo = POSIX::floor(log(($ylo > 0 ? $ylo : 1e-10))/log(10));
            my $hi = POSIX::floor(log( $yhi > 0 ? $yhi : 1  )/log(10)) + 1;

            for my $e ($lo .. $hi) {
                for my $m (2..9) {
                    my $v = $m * (10 ** $e);
                    push @yminors, $v
                        if $v > $ylo * 1.001 && $v < $yhi * 0.999;
                }
            }



        } else {
            @yminors = minor_ticks($self->ymin, $self->ymax, $self->_minor_n, @ytks);
        }
        $b->set_linewidth($twid);
        $b->set_color(@tc);
        for my $v (@yminors) {
            my $yp = $tr->y(pdl($v))->at(0);
            next if $yp < $mt || $yp > $mb;
            my $xa = ($x0p >= $ml && $x0p <= $mr) ? $x0p : $ml;
            if ($show_l) {
                my ($x1,$x2) = $tdir eq 'in'   ? ($xa, $xa + $tlen)
                             : $tdir eq 'inout' ? ($xa - $tlen/2, $xa + $tlen/2)
                             :                    ($xa, $xa - $tlen);
                $b->line_seg($x1, $yp, $x2, $yp);
            }
            if ($show_r) {
                my $xr = $mr;
                my ($x1,$x2) = $tdir eq 'in'   ? ($xr, $xr - $tlen)
                             : $tdir eq 'inout' ? ($xr - $tlen/2, $xr + $tlen/2)
                             :                    ($xr, $xr + $tlen);
                $b->line_seg($x1, $yp, $x2, $yp);
            }
        }
        $b->set_linewidth(1.5);
    }
}

# ------------------------------------------------------------------
# Tick values and their label strings for the current (finalized) range.
# Used by _draw_frame and, before drawing, by _label_room (tight_layout).
# ------------------------------------------------------------------
sub _xtick_list {
    my ($self) = @_;
    my @xtks;
    my $date_step;  # 日付軸の場合のみ使用(fmt_date_tickに渡す目盛り間隔)
    if ($self->_xticks) {
        @xtks = @{ $self->_xticks };
    } elsif ($self->_xaxis_is_date) {
        @xtks = nice_date_ticks($self->xmin, $self->xmax, 6);
        $date_step = (@xtks >= 2) ? ($xtks[1] - $xtks[0]) : 86400;
    } elsif ($self->xscale eq 'log') {
        my $sc = PDL::Graphics::Cairo::Scale::Log->new;
        @xtks = $sc->nice_ticks($self->xmin, $self->xmax);
    } else {
        @xtks = nice_ticks($self->xmin, $self->xmax, 6);
    }
    my @xlbs;
    if ($self->_xticklabels) {
        @xlbs = @{ $self->_xticklabels };
    } elsif ($self->_xformatter) {
        my $fmt = $self->_xformatter;
        @xlbs = map { $fmt->($xtks[$_], $_) } 0..$#xtks;
    } elsif ($self->_xaxis_is_date) {
        @xlbs = map { fmt_date_tick($_, $date_step) } @xtks;
    } elsif ($self->xscale eq 'log') {
        my $sc = PDL::Graphics::Cairo::Scale::Log->new;
        @xlbs = map { $sc->fmt_tick($_) } @xtks;
    } else {
        @xlbs = map { _fmt_tick($_) } @xtks;
    }
    return (\@xtks, \@xlbs);
}

sub _ytick_list {
    my ($self) = @_;
    my @ytks;
    if ($self->_yticks) {
        @ytks = @{ $self->_yticks };
    } elsif ($self->yscale eq 'log') {
        my $sc = PDL::Graphics::Cairo::Scale::Log->new;
        @ytks = $sc->nice_ticks($self->ymin, $self->ymax);
    } else {
        @ytks = nice_ticks($self->ymin, $self->ymax, 6);
    }
    my @ylbs = $self->_yticklabels ? @{ $self->_yticklabels }
        : ($self->yscale eq 'log')
            ? do { my $sc = PDL::Graphics::Cairo::Scale::Log->new;
                   map { $sc->fmt_tick($_) } @ytks }
            : map { _fmt_tick($_) } @ytks;
    return (\@ytks, \@ylbs);
}

# Distance (px) from the left edge of the plot rectangle to the right edge
# of the y tick numbers: tick length outside the frame + y_pad + 2.
# _draw_frame places the numbers there; _draw_labels and _label_room use it.
sub _ytick_label_offset {
    my ($self) = @_;
    my $pb   = $self->{_pgbox};
    my $yopt = $pb ? uc($pb->{yopt}) : 'BCNST';
    my $tp   = $self->_tick_params;
    my $tlen = $tp->{y_length} // (($yopt =~ /T/) ? 5 : 3);
    my $tdir = $tp->{y_direction} // 'out';
    my $ext  = $tdir eq 'out' ? $tlen : $tdir eq 'inout' ? $tlen/2 : 0;
    return $ext + ($tp->{y_pad} // 10) + 2;
}

my %LABEL_ROOM_CACHE;   # key => [left, bottom, top]; see _label_room

# _label_room($m, $level): room (px) that the tick numbers, xlabel, ylabel
# title and a legend outside the frame need outside the plot rectangle,
# measured with $m (set_font/text_size: tight_layout's TextMeasure, or a
# Driver::Cairo). Returns (left, bottom, top, right). $level is the label size
# level that _draw_labels will use (0 = normal, 1 = compact).
# It mirrors where _draw_frame, _draw_labels and _draw_legend put the text,
# for the range the next draw() will use. The user's xlim/ylim are restored.
sub _label_room {
    my ($self, $m, $level) = @_;
    $level //= 0;
    return (0, 0, 0, 0) if $self->{_axis_off};

    my @user = ($self->xmin, $self->xmax, $self->ymin, $self->ymax);
    $self->_finalize_range;
    my ($xlo, $xhi, $ylo, $yhi) = ($self->xmin, $self->xmax, $self->ymin, $self->ymax);

    # The result depends only on what goes into the key; panels of a grid
    # usually share it, and show_interactive asks again on every frame.
    # An axis with a formatter coderef is not cached (its output is unknown).
    my $key;
    unless ($self->_xformatter) {
        my $tp = $self->_tick_params;
        my $pb = $self->{_pgbox};
        $key = join "\x1f", $level, ref($m),
            ($m->can('cache_tag') ? $m->cache_tag : 'nocache'),
            $xlo, $xhi, $ylo, $yhi, $self->xscale, $self->yscale,
            ($self->_xaxis_is_date ? 1 : 0),
            map({ $_ ? join("\x1e", @$_) : '' }
                $self->_xticks, $self->_yticks,
                $self->_xticklabels, $self->_yticklabels),
            join("\x1e", map { "$_=" . ($tp->{$_} // '') } sort keys %$tp),
            ($pb ? uc($pb->{xopt}) . '/' . uc($pb->{yopt}) : ''),
            $self->xlabel, $self->ylabel, $self->title,
            $self->ylabel_rotation // 90,
            $self->{_xtick_rot} // '', $self->{_ytick_rot} // '',
            ($self->_is_twin ? $self->_twin_type // 'x' : ''),
            $self->_legend_place, $self->width,
            join("\x1e", map { $_->{label} // '' } @{ $self->_legends });
        if (my $hit = $LABEL_ROOM_CACHE{$key}) {
            $self->xmin($user[0]); $self->xmax($user[1]);
            $self->ymin($user[2]); $self->ymax($user[3]);
            return @$hit;
        }
    }

    my ($xtks, $xlbs) = $self->_xtick_list;
    my ($ytks, $ylbs) = $self->_ytick_list;
    $self->xmin($user[0]); $self->xmax($user[1]);
    $self->ymin($user[2]); $self->ymax($user[3]);
    my @room = $self->_label_room_measure($m, $level,
        $xlo, $xhi, $ylo, $yhi, $xtks, $xlbs, $ytks, $ylbs);
    if (defined $key && $m->can('cache_tag')) {
        %LABEL_ROOM_CACHE = () if keys %LABEL_ROOM_CACHE > 5000;
        $LABEL_ROOM_CACHE{$key} = \@room;
    }
    return @room;
}

sub _label_room_measure {
    my ($self, $m, $level, $xlo, $xhi, $ylo, $yhi, $xtks, $xlbs, $ytks, $ylbs) = @_;

    my $pb   = $self->{_pgbox};
    my $xopt = $pb ? uc($pb->{xopt}) : 'BCNST';
    my $yopt = $pb ? uc($pb->{yopt}) : 'BCNST';
    my $tp   = $self->_tick_params;
    my $pi   = 3.14159265358979;

    # extent of a rotated text box along x (horizontal) or y (vertical)
    my $ext = sub {
        my ($w, $h, $deg, $along_x) = @_;
        my $r = $deg * $pi / 180;
        return $along_x ? abs($w * cos($r)) + abs($h * sin($r))
                        : abs($w * sin($r)) + abs($h * cos($r));
    };

    # ---- left: y tick numbers and ylabel ----
    my $ytick_w = 0;      # what _draw_labels will add for the numbers
    my $left    = 0;
    my $yoff    = $self->_ytick_label_offset;
    if ($yopt =~ /N/ && ($tp->{y_labelleft} // 1)) {
        my $rot = $tp->{y_labelrotation} // $self->{_ytick_rot} // 0;
        $m->set_font(size => $tp->{y_labelsize} // 10);
        my $eps = ($yhi - $ylo) * 0.001 + 0.001;
        my $wmax = 0;
        for my $i (0 .. $#$ytks) {
            next if $ytks->[$i] < $ylo - $eps || $ytks->[$i] > $yhi + $eps;
            for my $ln (split /\n/, $ylbs->[$i] // '', -1) {
                my ($w, $h) = $m->text_size($ln);
                my $e = $ext->($w, $h, $rot, 1);
                $wmax = $e if $e > $wmax;
            }
        }
        $ytick_w = $wmax if $rot == 0;
        $left = $yoff + $wmax;
    }
    if ($self->ylabel ne '' && !($self->_is_twin && ($self->_twin_type // '') ne 'y')) {
        my $rot = $self->ylabel_rotation // 90;
        $m->set_font(size => 11);
        my ($w, $h) = $m->text_size($self->ylabel);
        my $need = $rot == 0
            ? $yoff + $ytick_w + 6 + $w
            : $yoff + $ytick_w + 5 + $ext->($w, $h, $rot, 1);
        $left = $need if $need > $left;
    }

    # ---- bottom: x tick numbers and xlabel ----
    my $bottom = 0;
    if ($xopt =~ /N/ && ($tp->{x_labelbottom} // 1)) {
        my $rot  = $tp->{x_labelrotation} // $self->{_xtick_rot} // 0;
        my $tlen = $tp->{x_length} // (($xopt =~ /T/) ? 5 : 3);
        my $tdir = $tp->{x_direction} // 'out';
        my $text = $tdir eq 'out' ? $tlen : $tdir eq 'inout' ? $tlen/2 : 0;
        $m->set_font(size => $tp->{x_labelsize} // 10);
        my $eps  = ($xhi - $xlo) * 0.001 + 0.001;
        my $hmax = 0;
        for my $i (0 .. $#$xtks) {
            next if $xtks->[$i] < $xlo - $eps || $xtks->[$i] > $xhi + $eps;
            my ($w, $h) = $m->text_size($xlbs->[$i] // '');
            my $e = $ext->($w, $h, $rot, 0);
            $hmax = $e if $e > $hmax;
        }
        $bottom = $text + ($tp->{x_pad} // 4) + 2 + $hmax;
    }
    if ($self->xlabel ne '' && !($self->_is_twin && ($self->_twin_type // '') eq 'y')) {
        $m->set_font(size => ($level == 1 ? 9 : 11));
        my (undef, $h) = $m->text_size($self->xlabel);
        my $need = ($level == 1 ? 38 : 40) + $h;
        $bottom = $need if $need > $bottom;
    }

    # ---- top: title ----
    my $top = 0;
    my $toff = $level == 1 ? 11 : 14;
    my $th = 0;
    if ($self->title ne '') {
        $m->set_font(size => ($level == 1 ? 11 : 13), weight => 'bold');
        (undef, $th) = $m->text_size($self->title);
        $top = $toff + $th;
    }

    # ---- legend outside the frame: top row or right column ----
    my $right = 0;
    my $place = $self->_legend_place;
    if ($place eq 'top') {
        # the plot width is not known yet: estimate it from the Axes width
        my $ml_est = $left > 56 ? $left : 56;
        my $pw_est = $self->width - $ml_est - 18;
        my $lt = $self->_legend_top_layout($m, 0, $pw_est, 0, $level);
        my $need = $self->title eq '' || $lt->{title_up}
            ? 4 + LEG_LH                        # own row just above the frame
            : $toff + $th / 2 + LEG_LH / 2;     # centred on the title
        $top += $lt->{title_up} if $lt->{title_up};
        $top = $need if $need > $top;
    } elsif ($place eq 'right') {
        $right = LEG_GAP + $self->_legend_geom($m)->{col_w} + 4;
    }

    # 2 px so the outermost pixels of the glyphs stay inside the figure
    return map { $_ > 0 ? int($_ + 0.999) + 2 : 0 } ($left, $bottom, $top, $right);
}

sub _fmt_tick {
    my ($v) = @_;
    return "0" if $v == 0;
    my $abs = abs($v);
    if ($abs >= 1e4 || ($abs > 0 && $abs < 1e-3)) {
        return sprintf("%.2e", $v);
    }
    #

    #

    my $rounded = $v >= 0 ? int($v + 0.5) : int($v - 0.5);
    if (abs($v - $rounded) < 0.001) {
        return sprintf("%d", $rounded);
    }
    # 整数でない値は、有効数字 6 桁までで値をそのまま表す(1.25 → "1.25")。
    # 以前は 1 以上を "%.1f"、1 未満を "%.2g" にしていたため、刻み 0.25 や
    # 0.00025 の目盛りが 1.2 / 0.0013 のように隣の目盛りとずれた数字になっていた。
    return sprintf("%.6g", $v);
}

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
sub _draw_labels {
    my ($self, $b, $ml,$mt,$mr,$mb) = @_;

    warn sprintf("[DEBUG _draw_labels] title='%s' xlabel='%s' compact=%s mt=%s mb=%s ml=%s mr=%s\n",
        $self->title, $self->xlabel, $self->_compact_labels // 'undef', $mt, $mb, $ml, $mr)
        if $ENV{PGC_DEBUG_LABELS};

    # PGPLOT互換層は背景色(_PDLCAIRO_PGBG、デフォルトwhite)を
    # 黒に設定できる(cpgopenの bg=>'black' 等)。その場合、軸線や
    # 数値ラベルは _ci_to_rgb 経由で白に切り替わるが、title/xlabel/ylabel
    # はこれまで固定で黒(0,0,0)に描いていたため、黒背景時に文字が
    # 完全に見えなくなっていた(背景=文字色で同化)。
    # ここでも同じ背景判定を使い、黒背景なら白、それ以外は黒で描く。
    my $bg_black = (lc($ENV{_PDLCAIRO_PGBG} // 'white') eq 'black');
    my @label_fg = $bg_black ? (1,1,1) : (0,0,0);

    $b->set_color(@label_fg);

    # _compact_labels: 0=通常(単一figure), 1=compact(matplotlib風tight_layout
    # のuniform_margins), 2=pgplot(PGPLOT互換層、mb/mt自体が約半分の固定値
    # しかないため、compactよりさらに詰めたオフセット/フォントが必要)。
    my $level = $self->_compact_labels || 0;

    #

    if ($self->title ne '') {
        # level1: フォント13pt→11pt、オフセット-14→-11px。
        # level2(pgplot): フォント13pt→9pt、オフセット-14→-8px。
        my $fsize = $level == 2 ? 9  : $level == 1 ? 11 : 13;
        my $toff  = $level == 2 ? 8  : $level == 1 ? 11 : 14;
        # colorbar_location=>'top' の場合、mt自体がcolorbar用に拡張
        # されており、colorbar本体は mt-pad-cw 付近に描かれる。titleを
        # 通常の mt-toff のままにすると、colorbarの帯に埋もれて見えなく
        # なるため、colorbarの外側（さらに上）にtitleを配置する。
        my $title_y = $mt - $toff;
        if ($self->_colorbar && ($self->colorbar_location // '') eq 'top') {
            my $cb_pad = $self->colorbar_pad;
            my $cb_w   = $self->colorbar_width;
            my $cb_has_label = ($self->colorbar_label // '') ne '';
            # colorbar本体の上端(外側)は mt-pad-cw。さらにlabelがあれば
            # その分(横書きで上方向に約16px)も避ける必要がある。
            # _draw_colorbar側の cb_label_y 計算
            # (top配置: label_y(=cy-14) - 16 = cy-30 = mt-pad-cw-30)
            # と正確に対応させ、さらにtitle用のフォント分の余白(18px)を
            # 追加で確保する。
            my $cb_outer = $mt - $cb_pad - $cb_w - ($cb_has_label ? 30 + 18 : 0);
            $title_y = $cb_outer - $toff;
        }
        elsif (my @twins = grep { ($_->_twin_type // '') eq 'y' } @{ $self->_twin_axes }) {
            # twiny() が呼ばれている場合、上に第2X軸の目盛り・ラベルが
            # 描かれる(_draw_twin_xaxis)。titleをその外側(さらに上)に
            # 配置しないと、第2X軸のラベルとtitleが重なってしまう。
            # _twin_axes には twinx()/twiny() 両方のtwinが入りうるため、
            # twin_type='y'(twiny)のものだけを抜き出す。
            my $twin = $twins[0];
            # _draw_twin_xaxis の描画位置: 上向きtick(mt-4) +
            # 数値ラベル(mt-6から上、フォント10pt相当で約12px) +
            # xlabelがあれば追加で mt-28 から上にフォント11pt分。
            my $twin_outer = ($twin->xlabel ne '') ? ($mt - 28 - 14) : ($mt - 18);
            $title_y = $twin_outer - $toff;
            warn sprintf("[DEBUG title twiny] mt=%s twin_outer=%s title_y=%s\n",
                $mt, $twin_outer, $title_y) if $ENV{PGC_DEBUG_LABELS};
        }
        $b->set_font(size => $fsize, weight => 'bold');
        # legend(loc=>'outside top') が同じ行にあるとき、タイトルは左寄せ
        # または上へずらす(_legend_top_layout が決める)。
        my $lt = $self->{_legend_top_now};
        if ($lt && $lt->{title_align} eq 'left') {
            $b->text($ml, $title_y - $lt->{title_up}, $self->title,
                align=>'left', valign=>'bottom');
        } else {
            $b->text(($ml+$mr)/2, $title_y - ($lt ? $lt->{title_up} : 0),
                $self->title, align=>'center', valign=>'bottom');
        }
    }

    # X 
    # twiny() が作った twin オブジェクト(_is_twin かつ _twin_type='y')の
    # xlabel は、_draw_twin_xaxis() がすでに上端の専用位置に描画して
    # いるため、ここで通常の下軸ラベル位置(mb+xoff)に重複して描かない
    # ようにする。以前はこのガードが無く、上軸ラベルと下軸ラベルの
    # テキストが同じ場所(下)に二重描画されて重なって見える不具合が
    # あった。
    if ($self->xlabel ne '' && !($self->_is_twin && ($self->_twin_type // '') eq 'y')) {
        # level1: フォント11pt→9pt、オフセット+40→+38px。
        # level2(pgplot): フォント11pt→8pt、PGPLOTのmb(26px程度)に収まる
        # よう数値ラベル直下にぴったり詰めたオフセット+22pxを使う。
        my $fsize = $level == 2 ? 8  : $level == 1 ? 9  : 11;
        my $xoff  = $level == 2 ? 23 : $level == 1 ? 38 : 40;
        $b->set_font(size => $fsize);
        $b->text(($ml+$mr)/2, $mb + $xoff, $self->xlabel,
            align=>'center', valign=>'top');
    }

    # Y ラベル（ylabel_rotation=90で縦書き、0で横書き）
    # twinx() が作った twin オブジェクト(_is_twin かつ _twin_type が
    # 'y'以外、すなわちtwinx扱い)の ylabel は、_draw_twin_yaxis() が
    # すでに右端の専用位置に描画しているため、ここで通常の左軸ラベル
    # 位置(ml-gap)に重複して描かないようにする。xlabelで起きたのと
    # 同じ種類の二重描画バグで、左Y軸ラベルと右Y軸ラベルのテキストが
    # 同じ場所(左)に重なって見える不具合があった。
    if ($self->ylabel ne '' && !($self->_is_twin && ($self->_twin_type // '') ne 'y')) {
        # title/xlabelと同様、PGPLOT(level2)の極小margin_left(22-30px程度)
        # に合わせてフォント・gapを縮小する。以前はylabelだけlevel別調整が
        # 欠けていたため、PGPLOT経路でylabel('uV'等)がmargin_left範囲を
        # 超えてプロット枠の内側に描かれてしまっていた(枠内にラベルが
        # 侵入して見える不具合)。
        my $ysize = $level == 2 ? 8 : 11;
        $b->set_font(size => $ysize);
        my $rot = $self->ylabel_rotation // 90;
        # tick数値ラベルは $ml - tick_ext - pad - 2 を右端にして左へ伸びる。
        # その実測最大幅 (_y_ticklabel_maxw) より内側に ylabel が来ないよう
        # 固定オフセットへ動的なマージンを上乗せする。
        my $tick_w = $self->{_y_ticklabel_maxw} // 0;
        # 目盛り数字の右端は枠から _ytick_label_offset (既定 5+10+2=17 px)。
        # ylabel はその左端(さらに tick_w 左)から 5〜6 px 離す。
        # _label_room(tight_layout の余白見積り)も同じ式を使う。
        my $yoff = $self->_ytick_label_offset;
        if ($rot == 0) {
            # 横書き: 目盛り数字の左、縦中央、右寄せ
            # (以前は 8+tick_w で、数字の左端より 9 px 内側に重なっていた)
            my $gap = $level == 2 ? (9 + $tick_w) : ($yoff + $tick_w + 6);
            warn sprintf("[DEBUG ylabel] rot=0 ml=%s gap=%s text_x=%s text_y=%s\n",
                $ml, $gap, $ml-$gap, ($mt+$mb)/2) if $ENV{PGC_DEBUG_LABELS};
            $b->text($ml - $gap, ($mt+$mb)/2, $self->ylabel,
                align=>'right', valign=>'center', angle=>0);
        } else {
            # 縦書き（デフォルト動作を維持）
            # 縦書きテキストの幅は概ねフォントサイズ分(11px)なので
            # tick数値ラベル幅 + 余白(8px) + 縦書き文字幅(約14px) を確保する。
            # level2: 数値ラベル自体(pad6+tick_ext3+2=11px)+その文字幅
            # (8pt数値2-3文字≈6px)+ylabel文字幅(8pt≈10px)+安全余白(2px)
            # ≈ 19px。以前の14pxでは数値ラベルとylabelの文字が重なって
            # 見える(差がわずか3pxしかなかった)不具合があったため調整。
            my $gap = $level == 2 ? (19 + $tick_w) : ($yoff + 5 + $tick_w);
            warn sprintf("[DEBUG ylabel] rot=%s ml=%s gap=%s tick_w=%s text_x=%s text_y=%s\n",
                $rot, $ml, $gap, $tick_w, $ml-$gap, ($mt+$mb)/2) if $ENV{PGC_DEBUG_LABELS};
            $b->text($ml - $gap, ($mt+$mb)/2, $self->ylabel,
                align=>'center', valign=>'bottom', angle=>$rot);
        }
    }
}

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
sub _draw_legend {
    my ($self, $b, $ml,$mt,$mr,$mb) = @_;
    my @legs = @{ $self->_legends };
    return unless @legs;

    # 枠の外の凡例(箱なし)
    my $place = $self->_legend_place;
    if ($place eq 'top') {
        my $lt = $self->{_legend_top_now}
            // $self->_legend_top_layout($b, $ml, $mr, $mt, $self->_compact_labels || 0);
        my $x = $lt->{x0};
        for my $i (0 .. $#legs) {
            $self->_draw_legend_entry($b, $legs[$i], $x, $lt->{yc});
            $x += $lt->{entry_w}[$i] + LEG_SEP;
        }
        return;
    }
    if ($place eq 'right') {
        my $g  = $self->_legend_geom($b);
        # tight_layout が margin_right に凡例の列を含めているので、セルの
        # 右端に寄せる(colorbar や twinx の目盛りより外側になる)。
        my $lx = $self->fig_x + $self->width - $g->{col_w} - 4;
        $lx = $mr + LEG_GAP if $lx < $mr + LEG_GAP;
        for my $i (0 .. $#legs) {
            $self->_draw_legend_entry($b, $legs[$i], $lx,
                $mt + 2 + $i * LEG_LH + LEG_LH / 2);
        }
        return;
    }

    my $fs   = 11;
    my $lh   = 20;
    my $pw   = 24;
    my $pad  = 8;

    $b->set_font(size => $fs);
    my $max_tw = 0;
    for my $lg (@legs) {
        my $tw = $b->text_width($lg->{label});
        $max_tw = $tw if $tw > $max_tw;
    }
    my $box_w = $pw + $pad*3 + $max_tw;
    my $box_h = $lh * scalar(@legs) + $pad;

    #

    my $loc = $self->{_legend_loc} // 'upper right';
    my ($lx,$ly);
    if    ($loc eq 'upper right')  { $lx = $mr - $box_w - 6; $ly = $mt + 6 }
    elsif ($loc eq 'upper left')   { $lx = $ml + 6;           $ly = $mt + 6 }
    elsif ($loc eq 'lower right')  { $lx = $mr - $box_w - 6; $ly = $mb - $box_h - 6 }
    elsif ($loc eq 'lower left')   { $lx = $ml + 6;           $ly = $mb - $box_h - 6 }
    else                           { $lx = $mr - $box_w - 6; $ly = $mt + 6 }

    #

    $b->set_color(1,1,1, 0.85);
    $b->rect_fill($lx, $ly, $box_w, $box_h);
    $b->set_color(0.6,0.6,0.6);
    $b->set_linewidth(1.5);
    $b->rect_stroke($lx, $ly, $box_w, $box_h);

    for my $i (0 .. $#legs) {
        $self->_draw_legend_entry($b, $legs[$i], $lx + $pad,
            $ly + $pad/2 + $i * $lh + $lh/2);
    }
}

# One legend entry: the patch (line, marker, rect or fill) from x0, then the
# label; both centred on y0.
sub _draw_legend_entry {
    my ($self, $b, $lg, $x0, $y0) = @_;
    my ($fs, $pw, $pad) = (LEG_FS, LEG_PW, LEG_PAD);
    {
        $b->set_color(@{$lg->{color}});

        if ($lg->{type} eq 'line') {
            $b->set_linewidth($lg->{lw} // 1.5);
            $b->line_seg($x0, $y0, $x0 + $pw, $y0);
        }
        elsif ($lg->{type} eq 'marker') {
            $b->marker($x0 + $pw/2, $y0, 4, $lg->{marker}//'o', 1);
        }
        elsif ($lg->{type} eq 'rect') {
            $b->rect_fill($x0, $y0-6, $pw, 12);
            $b->set_color(0,0,0);
            $b->set_linewidth(0.5);
            $b->rect_stroke($x0, $y0-6, $pw, 12);
        }
        elsif ($lg->{type} eq 'fill') {
            # fill_between の凡例: 半透明の塗りパッチ
            $b->set_color(@{$lg->{color}}, $lg->{alpha} // 0.3);
            $b->rect_fill($x0, $y0-6, $pw, 12);
            $b->set_color(@{$lg->{color}}, 1.0);
            $b->set_linewidth(0.5);
            $b->rect_stroke($x0, $y0-6, $pw, 12);
        }

        $b->set_color(0,0,0);
        $b->set_font(size => $fs);
        $b->text($x0 + $pw + $pad, $y0, $lg->{label},
            align=>'left', valign=>'middle');
    }
}

# ------------------------------------------------------------------
#

# ------------------------------------------------------------------
# Tick values of the colorbar. $len_px: length of the bar in pixels along its
# axis; $label_px: room one tick number needs along that axis.
sub _colorbar_ticks {
    my ($self, $len_px, $label_px) = @_;
    my $cb = $self->_colorbar;
    my ($lo, $hi) = @$cb{qw(vmin vmax)};
    ($lo, $hi) = ($hi, $lo) if $lo > $hi;
    my $step = $self->colorbar_tick_step;
    return nice_ticks($lo, $hi, 5) unless defined $step && $step > 0 && $hi > $lo;
    my $k = 1;
    if (defined $len_px && $len_px > 0) {
        my $px = $len_px * $step / ($hi - $lo);            # pixels between two ticks
        $k = POSIX::ceil(($label_px // 10) / $px) if $px < ($label_px // 10);
    }
    my $eps = 1e-9 * $step;
    my ($i0, $i1) = (POSIX::ceil(($lo - $eps) / ($step * $k)), POSIX::floor(($hi + $eps) / ($step * $k)));
    return map { my $v = $_ * $step * $k; abs($v) < $eps ? 0 : $v } $i0 .. $i1;
}

# true when draw() will draw the colorbar
sub _colorbar_shown {
    my ($self) = @_;
    return $self->_colorbar && (!$self->{_axis_off} || $self->{_colorbar_force}) ? 1 : 0;
}

sub _draw_colorbar {
    my ($self, $b, $ml, $mr, $mt, $mb) = @_;
    my $cb  = $self->_colorbar;
    return unless $cb;

    # colorbar(label=>'...') で設定されたラベルを _colorbar ハッシュに
    # 反映する。_colorbar 自体は imshow/scatter(c=>...) 等の描画コマンドが
    # cmap/vmin/vmax を保存する場所であり、colorbar() メソッドの label
    # オプションとは別経路でセットされるため、ここで合成する。
    $cb->{label} = $self->colorbar_label if ($self->colorbar_label // '') ne '';

    my $loc  = $self->colorbar_location;
    my $cw   = $self->colorbar_width;
    my $pad  = $self->colorbar_pad;
    my $frac = $self->colorbar_length;
    my $n    = 200;

    if ($loc eq 'right' || $loc eq 'left') {
        #

        my $full_h = $mb - $mt;
        my $h      = $full_h * $frac;
        my $y0     = $mt + ($full_h - $h) / 2;

        my ($cx, $label_x, $label_align, $tick_x0, $tick_x1);
        if ($loc eq 'right') {
            $cx         = $mr + $pad;
            $tick_x0    = $cx + $cw;
            $tick_x1    = $cx + $cw + 4;
            $label_x    = $cx + $cw + 7;
            $label_align = 'left';
        } else {  # left
            # 以前は cx = ml - pad - cw としていたが、これは ml の内側
            # （プロット領域）に直接めり込む計算だった。left配置のcolorbar
            # はY軸数値ラベル(おおよそ ml-21 の位置から左に20px程度の
            # 文字幅で伸びる)よりさらに外側(左)に置く必要があるため、
            # 固定オフセット47pxを追加で確保する。
            # （tight_layout側でも colorbar_location=>'left' 指定時に
            #   margin_left を+68px拡張しているので、この47pxはその
            #   拡張分の範囲内に収まる設計になっている）
            $cx         = $ml - 47 - $pad - $cw;
            $tick_x0    = $cx - 4;
            $tick_x1    = $cx;
            $label_x    = $cx - 7;
            $label_align = 'right';
        }

        #

        for my $i (0 .. $n-1) {
            my $v  = $i / ($n - 1);
            my ($r,$g,$bv) = $cb->{cmap}->rgb_at($v);
            my $yp = $y0 + $h - $v * $h;
            $b->colored_rect($cx, $yp - $h/$n, $cw, $h/$n + 1, $r, $g, $bv);
        }
        $b->set_color(0,0,0);
        $b->set_linewidth(1.5);
        $b->rect_stroke($cx, $y0, $cw, $h);

        #

        $b->set_font(size => 9);
        my @tks = $self->_colorbar_ticks($h, 10);
        my $span = $cb->{vmax} - $cb->{vmin};
        for my $v (@tks) {
            # vmin == vmax (hexbin でどの六角形も同じ数など): 中央に 1 本
            my $f  = $span ? ($v - $cb->{vmin}) / $span : 0.5;
            my $yp = $y0 + $h - $f * $h;
            $b->line_seg($tick_x0, $yp, $tick_x1, $yp);
            $b->text($label_x, $yp, _fmt_tick($v),
                align=>$label_align, valign=>'middle');
        }

        # colorbar全体のラベル（例: 'intensity'）。ティックラベルとは別に、
        # カラーバー本体の外側に縦書きで配置する。ティックラベルの最大幅を
        # 考慮しないため固定オフセットだが、ティックラベルとの重なりは
        # 通常のフォントサイズ・ティック数値の桁数では起きにくい。
        # angle=>90(正)を使う。-90だと文字が上から下に読む向きになり、
        # 通常のylabelと反転して見えてしまう(ユーザー指摘により発覚)。
        if ($cb->{label} // '' ne '') {
            $b->set_font(size => 10);
            my $cb_label_x = ($loc eq 'right')
                ? $cx + $cw + 40
                : $cx - 40;
            warn sprintf("[DEBUG colorbar] loc=%s ml=%s mr=%s cx=%s cw=%s cb_label_x=%s\n",
                $loc, $ml, $mr, $cx, $cw, $cb_label_x) if $ENV{PGC_DEBUG_LABELS};
            $b->text($cb_label_x, $y0 + $h/2, $cb->{label},
                align=>'center', valign=>'middle', angle=>90);
        }
    }
    else {
        #  (top / bottom)
        my $full_w = $mr - $ml;
        my $w      = $full_w * $frac;
        my $x0     = $ml + ($full_w - $w) / 2;

        my ($cy, $label_y, $label_valign, $tick_y0, $tick_y1);
        if ($loc eq 'bottom') {
            $cy          = $mb + $pad;
            $tick_y0     = $cy + $cw;
            $tick_y1     = $cy + $cw + 4;
            $label_y     = $cy + $cw + 14;
            $label_valign = 'top';
        } else {  # top
            $cy          = $mt - $pad - $cw;
            $tick_y0     = $cy - 4;
            $tick_y1     = $cy;
            $label_y     = $cy - 14;
            $label_valign = 'bottom';
        }

        #

        for my $i (0 .. $n-1) {
            my $v  = $i / ($n - 1);
            my ($r,$g,$bv) = $cb->{cmap}->rgb_at($v);
            my $xp = $x0 + $v * $w;
            $b->colored_rect($xp, $cy, $w/$n + 1, $cw, $r, $g, $bv);
        }
        $b->set_color(0,0,0);
        $b->set_linewidth(1.5);
        $b->rect_stroke($x0, $cy, $w, $cw);

        #

        $b->set_font(size => 9);
        my @tks = $self->_colorbar_ticks($w, 26);
        my $span = $cb->{vmax} - $cb->{vmin};
        for my $v (@tks) {
            # vmin == vmax (hexbin でどの六角形も同じ数など): 中央に 1 本
            my $f  = $span ? ($v - $cb->{vmin}) / $span : 0.5;
            my $xp = $x0 + $f * $w;
            $b->line_seg($xp, $tick_y0, $xp, $tick_y1);
            $b->text($xp, $label_y, _fmt_tick($v),
                align=>'center', valign=>$label_valign);
        }

        # colorbar全体のラベル（例: 'intensity'）。top/bottom配置時は
        # ティックラベルのさらに外側に横書きで配置する。
        if ($cb->{label} // '' ne '') {
            $b->set_font(size => 10);
            my $cb_label_y = ($loc eq 'bottom')
                ? $label_y + 16
                : $label_y - 16;
            my $cb_label_valign = ($loc eq 'bottom') ? 'top' : 'bottom';
            $b->text($x0 + $w/2, $cb_label_y, $cb->{label},
                align=>'center', valign=>$cb_label_valign);
        }
    }
}

1;
