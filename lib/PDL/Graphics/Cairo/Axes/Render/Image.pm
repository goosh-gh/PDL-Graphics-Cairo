package PDL::Graphics::Cairo::Axes;

# Drawing of the queued plot commands: images, meshes, contours, hexbin and spectrograms.
# Part of PDL::Graphics::Cairo::Axes, split out of Axes.pm (P:G:C31): the
# subs below are methods of the same package, and _render_cmd (Axes.pm) calls
# them through %RENDER. The API methods that queue the commands stay in Axes.pm.
# Loaded at the end of Axes.pm, after its imports and constants.

use strict;
use warnings;
no warnings "redefine";

sub _render_specgram {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $spec   = $cmd->{spec};
    my $times  = $cmd->{times};
    my $freqs  = $cmd->{freqs};
    my $vmin   = $cmd->{vmin};
    my $vmax   = $cmd->{vmax};
    my $cmap   = $self->_resolve_cmap($cmd->{cmap});

    my $nframes = scalar @$times;
    my $nfreqs  = scalar @$freqs;

    # Draw each cell as a filled rectangle
    # Time runs left-right (x), Frequency runs bottom-top (y)
    for my $fi (0 .. $nframes - 1) {
        for my $fqi (0 .. $nfreqs - 1) {
            my $val = $spec->at($fqi, $fi);
            my $t   = ($vmax > $vmin)
                ? ($val - $vmin) / ($vmax - $vmin) : 0.5;
            $t = 0 if $t < 0; $t = 1 if $t > 1;
            my @rgb = $cmap->rgb_at($t);
            $b->set_color(@rgb);

            # Pixel coordinates for this cell
            my $t0 = $times->[$fi];
            my $t1 = ($fi < $nframes - 1) ? $times->[$fi+1]
                   : $t0 + ($t0 - ($fi > 0 ? $times->[$fi-1] : $t0));
            my $f0 = $freqs->[$fqi];
            my $f1 = ($fqi < $nfreqs - 1) ? $freqs->[$fqi+1]
                   : $f0 + ($f0 - ($fqi > 0 ? $freqs->[$fqi-1] : $f0));

            my $px0 = $tr->x(pdl($t0))->at(0);
            my $px1 = $tr->x(pdl($t1))->at(0);
            my $py0 = $tr->y(pdl($f0))->at(0);
            my $py1 = $tr->y(pdl($f1))->at(0);

            # Ensure correct order (y increases downward in screen)
            my ($lx, $rx) = $px0 < $px1 ? ($px0,$px1) : ($px1,$px0);
            my ($ty, $by) = $py0 < $py1 ? ($py0,$py1) : ($py1,$py0);

            next if $rx < $ml || $lx > $mr;
            next if $by < $mt || $ty > $mb;

            $lx = $ml if $lx < $ml; $rx = $mr if $rx > $mr;
            $ty = $mt if $ty < $mt; $by = $mb if $by > $mb;

            $b->filled_rect($lx, $ty, $rx - $lx, $by - $ty);
        }
    }
}

sub _render_hexbin {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my ($nx, $xmin, $xmax) = ($cmd->{gridsize},
        $self->xmin, $self->xmax);
    my ($ymin, $ymax) = ($self->ymin, $self->ymax);
    my $dx   = ($xmax - $xmin) / $nx;
    # hex geometry: width=dx, height=dx/cos(30deg) approx
    my $asp  = ($ymax - $ymin) / ($xmax - $xmin);
    my $ny   = int($nx * $asp * 0.8660) + 1;  # sqrt(3)/2
    my $dy   = ($ymax - $ymin) / $ny;

    # Count points per hexagon
    my %counts;
    my $xs = $cmd->{x};
    my $ys = $cmd->{y};
    for my $i (0 .. $xs->nelem - 1) {
        my ($xv, $yv) = ($xs->at($i), $ys->at($i));
        next if $xv < $xmin || $xv > $xmax;
        next if $yv < $ymin || $yv > $ymax;
        # offset rows for hex packing
        my $row  = int(($yv - $ymin) / $dy);
        my $xoff = ($row % 2) ? $dx * 0.5 : 0;
        my $col  = int(($xv - $xmin - $xoff) / $dx);
        $counts{"$row,$col"}++;
    }

    my $mincnt = $cmd->{mincnt};
    my @cnts   = grep { $_ >= $mincnt } values %counts;
    my $cmax   = $cmd->{vmax} // (@cnts ? do { my $m = $cnts[0]; for (@cnts) { $m = $_ if $_ > $m } $m } : 1);
    my $cmin   = $cmd->{vmin} // $mincnt;
    $self->_colorbar({ cmap => $self->_resolve_cmap($cmd->{cmap}),
                       vmin => $cmin, vmax => $cmax });

    my $cmap = $self->_resolve_cmap($cmd->{cmap});
    $b->set_alpha($cmd->{alpha});

    # 行・列の順に描く。隣の六角形とふちの画素が重なるので、ハッシュの
    # 順(実行ごとに変わる)で描くと、図が実行のたびに少し変わっていた。
    # (この sub では $b がバックエンドなので、sort { $a <=> $b } は使えない。
    #  桁をそろえた文字列にして、既定の sort で並べる。)
    my %by_pos = map { my ($r, $c) = split /,/; (sprintf('%010d,%010d', $r, $c) => $_) }
                 keys %counts;
    for my $key (map { $by_pos{$_} } sort keys %by_pos) {
        my $cnt = $counts{$key};
        next if $cnt < $mincnt;
        my ($row, $col) = split /,/, $key;
        my $xoff = ($row % 2) ? $dx * 0.5 : 0;
        my $cx   = $xmin + ($col + 0.5) * $dx + $xoff;
        my $cy   = $ymin + ($row + 0.5) * $dy;

        my $t    = ($cmax > $cmin) ? ($cnt - $cmin) / ($cmax - $cmin) : 1;
        $t = 0 if $t < 0; $t = 1 if $t > 1;
        my @col_rgb = $cmap->rgb_at($t);
        $b->set_color(@col_rgb);

        # Draw filled hexagon
        my $pxcx = $tr->x(pdl($cx))->at(0);
        my $pycy = $tr->y(pdl($cy))->at(0);
        my $rx   = abs($tr->x(pdl($cx + $dx*0.5))->at(0) - $pxcx);
        my $ry   = abs($tr->y(pdl($cy + $dy*0.5))->at(0) - $pycy);
        # 6 vertices of flat-top hexagon
        my @vx = map { $pxcx + $rx * cos($_ * 3.14159265/3) } 0..5;
        my @vy = map { $pycy + $ry * sin($_ * 3.14159265/3) } 0..5;
        $b->filled_polygon_xy(\@vx, \@vy);
    }
    $b->set_alpha(1.0);
}

sub _render_imshow {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my $data = $cmd->{data};
    my @dims = $data->dims;
    my $ndims = scalar @dims;
    my $pw = ($mr - $ml) / $dims[1];
    my $ph = ($mb - $mt) / $dims[0];
    my $upper  = ($cmd->{origin} // 'upper') eq 'upper';
    my $rows   = $dims[0];
    my $cols   = $dims[1];
    my $is_rgb = ($ndims == 3 && $dims[2] == 3);

    # Fast path: the whole image in one call. $data is (rows, cols[, 3]);
    # image_rgb wants (cols, rows) with row 0 at the top.
    if ($b->can('image_rgb')) {
        my ($rr, $gg, $bb);
        if ($is_rgb) {
            ($rr, $gg, $bb) = map { $data->slice(":,:,($_)") } 0 .. 2;
        }
        elsif ($cmd->{cmap}->can('rgb_norm_pdl')) {
            ($rr, $gg, $bb) = $cmd->{cmap}->rgb_norm_pdl(
                $data, $cmd->{vmin}, $cmd->{vmax});
        }
        else {                      # a colormap object without rgb_norm_pdl
            ($rr, $gg, $bb) = map { zeroes(double, $rows, $cols) } 1 .. 3;
            for my $r (0 .. $rows-1) {
                for my $c (0 .. $cols-1) {
                    my @rgb = $cmd->{cmap}->rgb_norm(
                        $data->at($r,$c), $cmd->{vmin}, $cmd->{vmax});
                    $rr->set($r,$c,$rgb[0]);
                    $gg->set($r,$c,$rgb[1]);
                    $bb->set($r,$c,$rgb[2]);
                }
            }
        }
        my @img = map { my $p = $_->xchg(0, 1);           # (cols, rows)
                        $upper ? $p : $p->slice(':,-1:0') } ($rr, $gg, $bb);
        $b->image_rgb($ml, $mt, $cols*$pw, $rows*$ph, @img, $cmd->{alpha});
    }
    elsif ($is_rgb) {
        # RGB画像 [H, W, 3]
        for my $r (0 .. $rows-1) {
            my $rd = $upper ? $r : $rows-1-$r;
            for my $c (0 .. $cols-1) {
                my $rv = $data->at($rd,$c,0);
                my $gv = $data->at($rd,$c,1);
                my $bv = $data->at($rd,$c,2);
                $b->colored_rect(
                    $ml + $c*$pw, $mt + $r*$ph, $pw+0.5, $ph+0.5,
                    $rv, $gv, $bv, $cmd->{alpha}
                );
            }
        }

    } else {
        # グレースケール [H, W]
        for my $r (0 .. $rows-1) {
            my $rd = $upper ? $r : $rows-1-$r;
            for my $c (0 .. $cols-1) {
                my $v = $data->at($rd,$c);
                my ($rv,$gv,$bv) = $cmd->{cmap}->rgb_norm($v, $cmd->{vmin}, $cmd->{vmax});
                $b->colored_rect(
                    $ml + $c*$pw, $mt + $r*$ph, $pw+0.5, $ph+0.5,
                    $rv,$gv,$bv, $cmd->{alpha}
                );
            }
        }
    }
}

sub _render_contour {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    my @xs      = list($cmd->{x});
    my @ys      = list($cmd->{y});
    my $z       = $cmd->{z};
    my $nr      = scalar @ys;
    my $nc      = scalar @xs;
    my @levels  = @{ $cmd->{levels} };
    my $colors  = $cmd->{colors};
    my $lws     = $cmd->{linewidths};
    my $lss     = $cmd->{linestyles};

    for my $li (0 .. $#levels) {
        my $level = $levels[$li];

        my @lc;
        if (ref($colors) eq 'ARRAY') {
            @lc = @{ $self->_parse_color($colors->[$li % scalar(@$colors)]) };
        } else {
            @lc = @{ $self->_parse_color($colors) };
        }
        my $lw = ref($lws) eq 'ARRAY' ? $lws->[$li % scalar(@$lws)] : $lws;
        my $ls = ref($lss) eq 'ARRAY' ? $lss->[$li % scalar(@$lss)] : $lss;

        $b->set_color(@lc, $cmd->{alpha});
        $b->set_linewidth($lw);
        $b->set_linestyle($ls);

        for my $r (0 .. $nr - 2) {
            for my $c (0 .. $nc - 2) {
                my $v00 = $z->at($r,   $c);
                my $v01 = $z->at($r,   $c+1);
                my $v10 = $z->at($r+1, $c);
                my $v11 = $z->at($r+1, $c+1);

                my $case = (($v00 >= $level) ? 8 : 0)
                         | (($v01 >= $level) ? 4 : 0)
                         | (($v11 >= $level) ? 2 : 0)
                         | (($v10 >= $level) ? 1 : 0);
                next if $case == 0 || $case == 15;

                my $x0d = $xs[$c];   my $x1d = $xs[$c+1];
                my $y0d = $ys[$r];   my $y1d = $ys[$r+1];

                # Linear interp on each edge
                # A=bottom(y0) B=right(x1) C=top(y1) D=left(x0)
                my $tA = ($v01!=$v00) ? ($level-$v00)/($v01-$v00) : 0.5;
                my ($xA,$yA) = ($x0d+$tA*($x1d-$x0d), $y0d);
                my $tB = ($v11!=$v01) ? ($level-$v01)/($v11-$v01) : 0.5;
                my ($xB,$yB) = ($x1d, $y0d+$tB*($y1d-$y0d));
                my $tC = ($v11!=$v10) ? ($level-$v10)/($v11-$v10) : 0.5;
                my ($xC,$yC) = ($x0d+$tC*($x1d-$x0d), $y1d);
                my $tD = ($v10!=$v00) ? ($level-$v00)/($v10-$v00) : 0.5;
                my ($xD,$yD) = ($x0d, $y0d+$tD*($y1d-$y0d));

                my ($pxA,$pyA) = ($tr->x(pdl($xA))->at(0), $tr->y(pdl($yA))->at(0));
                my ($pxB,$pyB) = ($tr->x(pdl($xB))->at(0), $tr->y(pdl($yB))->at(0));
                my ($pxC,$pyC) = ($tr->x(pdl($xC))->at(0), $tr->y(pdl($yC))->at(0));
                my ($pxD,$pyD) = ($tr->x(pdl($xD))->at(0), $tr->y(pdl($yD))->at(0));

                # Marching Squares line segments
                # bits: 8=BL(v00) 4=BR(v01) 2=TR(v11) 1=TL(v10)
                if    ($case==1||$case==14) { $b->line_seg($pxC,$pyC,$pxD,$pyD) }
                elsif ($case==2||$case==13) { $b->line_seg($pxB,$pyB,$pxC,$pyC) }
                elsif ($case==3||$case==12) { $b->line_seg($pxB,$pyB,$pxD,$pyD) }
                elsif ($case==4||$case==11) { $b->line_seg($pxA,$pyA,$pxB,$pyB) }
                elsif ($case==5           ) { $b->line_seg($pxA,$pyA,$pxB,$pyB);
                                              $b->line_seg($pxC,$pyC,$pxD,$pyD) }
                elsif ($case==6||$case==9 ) { $b->line_seg($pxA,$pyA,$pxC,$pyC) }
                elsif ($case==7||$case==8 ) { $b->line_seg($pxA,$pyA,$pxD,$pyD) }
                elsif ($case==10          ) { $b->line_seg($pxA,$pyA,$pxB,$pyB);
                                              $b->line_seg($pxC,$pyC,$pxD,$pyD) }
            }
        }
    }
    $b->set_linestyle('solid');
    $b->set_linewidth(1.5);
}

sub _render_contourf {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    # bilinear
    my @xs  = list($cmd->{x});
    my @ys  = list($cmd->{y});
    my $z   = $cmd->{z};
    my $nr  = scalar @ys;
    my $nc  = scalar @xs;
    my $vmin = $cmd->{vmin};
    my $vmax = $cmd->{vmax};

    for my $r (0 .. $nr - 2) {
        for my $c (0 .. $nc - 2) {
            my $v  = ($z->at($r,$c) + $z->at($r,$c+1)
                    + $z->at($r+1,$c) + $z->at($r+1,$c+1)) / 4;
            my ($rv,$gv,$bv) = $cmd->{cmap}->rgb_norm($v, $vmin, $vmax);
            my $x1p = $tr->x(pdl($xs[$c]))->at(0);
            my $x2p = $tr->x(pdl($xs[$c+1]))->at(0);
            my $y1p = $tr->y(pdl($ys[$r+1]))->at(0);
            my $y2p = $tr->y(pdl($ys[$r]))->at(0);
            $b->colored_rect($x1p, $y1p, $x2p-$x1p+0.5, $y2p-$y1p+0.5,
                $rv, $gv, $bv, $cmd->{alpha});
        }
    }
}

sub _render_pcolormesh {
    my ($self, $b, $tr, $cmd, $ml,$mt,$mr,$mb) = @_;
    # 不均一グリッドの疑似カラー表示。$x/$y はセル境界座標(1次元)、
    # $z は各セルの値。contourf と異なり頂点の補間は行わず、
    # セルごとの単一値をそのまま塗る(matplotlib pcolormesh と同じ
    # 挙動)。
    my @xs = list($cmd->{x});
    my @ys = list($cmd->{y});
    my $z  = $cmd->{z};
    my $vmin = $cmd->{vmin};
    my $vmax = $cmd->{vmax};

    my $nx_edges = scalar @xs;
    my $ny_edges = scalar @ys;
    my $n_cols   = $nx_edges - 1;  # セル数(X方向)
    my $n_rows   = $ny_edges - 1;  # セル数(Y方向)

    # PDLのdims()は[列,行]の順(列優先)を返す。$zの形状チェック自体は
    # 行わず、$z->at($r,$c)が範囲外ならPDL自体がエラーを出すため、
    # 形状不一致は自然に検出される。

    # 利便性のため、$z が (n_rows, n_cols) のセル値そのものでも
    # (ny_edges, nx_edges) の境界点と同じ形状(imshow/contourf流の
    # 簡易指定)でも受け付ける。後者の場合、$z->at($r,$c) は
    # (0..n_rows-1, 0..n_cols-1) の範囲でアクセスすれば自然に
    # 先頭の(n_rows, n_cols)個だけを使うことになり、最後の行・列
    # (本来は使われない余剰データ)を無視した形になる。

    for my $r (0 .. $n_rows - 1) {
        for my $c (0 .. $n_cols - 1) {
            my $v = $z->at($r, $c);
            my ($rv,$gv,$bv) = $cmd->{cmap}->rgb_norm($v, $vmin, $vmax);
            my $x1p = $tr->x(pdl($xs[$c]))->at(0);
            my $x2p = $tr->x(pdl($xs[$c+1]))->at(0);
            my $y1p = $tr->y(pdl($ys[$r+1]))->at(0);
            my $y2p = $tr->y(pdl($ys[$r]))->at(0);
            $b->colored_rect($x1p, $y1p, $x2p-$x1p+0.5, $y2p-$y1p+0.5,
                $rv, $gv, $bv, $cmd->{alpha});
        }
    }
}

1;
