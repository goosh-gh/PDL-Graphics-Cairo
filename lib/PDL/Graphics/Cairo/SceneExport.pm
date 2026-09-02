package PDL::Graphics::Cairo::SceneExport;
# ============================================================================
# PDL::Graphics::Cairo::SceneExport
#   giza-server の 3D 窓が今表示しているシーン(cortex mesh + 電極 + ラベル +
#   頂点カラー)を1つの .obj / .usda に書き出す。座標は投影前の生ジオメトリ
#   (MNI mm)。Keynote 等で回す用。
#
#   書式規約は PDL::IO::NYHead と同一に揃える(実装は独立、依存なし):
#     * 頂点並び : xchg(0,1)->flat 相当の行優先 [x0,y0,z0, x1,...]
#     * OBJ 面   : 1-based (idx0 + 1)
#     * USDA 面  : 0-based (idx0) = faceVertexIndices
#     * よって OBJ 面値 - 1 == USDA index (NYHead の不変条件を踏襲)
#     * 数値     : %.6f
#   NYHead が持たない差分 = 電極(八面体)・ラベル・頂点カラー を mesh に重ねる。
#
#   USDA ヘッダには NYHead の素ヘッダと違い upAxis="Z" / metersPerUnit を付す
#   (MNI は +Z 上。付けないと Keynote 等で頭が横倒しになる)。面 index 規約は
#   不変なので NYHead 互換は保たれる。opts で素ヘッダに戻せる。
#
# ---- 入力シーン(プレーン Perl。PDL 非依存。数値は flat 配列) ---------------
#   my $scene = {
#     mesh => {
#         verts   => [x0,y0,z0, x1,y1,z1, ...],   # mm
#         faces   => [a0,b0,c0, ...],             # 0-based
#         vcolors => [r0,g0,b0, ...],             # 0-1 頂点ごと(省略可, len==verts)
#         color   => [r,g,b],                     # 0-1 基本色(vcolors 省略時に使用)
#     },
#     points  => [x0,y0,z0, ...],                 # 電極 mm(省略可)
#     pcolors => [r0,g0,b0, ...],                 # 0-1 電極ごと(省略可)
#     labels  => ['Fp1', ...],                    # 電極ラベル(省略可)
#   };
#
#   PDL の live scene($self->{scene})からの変換は normalize_pdl_scene() が行う
#   (唯一の PDL 依存箇所。呼ばれた時だけ require PDL)。
# ============================================================================
use strict;
use warnings;
use Carp;
use Exporter 'import';

our @EXPORT_OK = qw(scene_to_obj scene_to_usda write_scene normalize_pdl_scene);

# 単位八面体(中心原点・半径1)。verts 順: +X -X +Y -Y +Z(top) -Z(bot)。
# faces は 0-based・外向き CCW(上ファン4枚 + 下ファン4枚)。
my @OCTA_V = ([ 1,0,0],[-1,0,0],[0, 1,0],[0,-1,0],[0,0, 1],[0,0,-1]);
my @OCTA_F = ([4,0,2],[4,2,1],[4,1,3],[4,3,0],   # top (+Z)
              [5,2,0],[5,1,2],[5,3,1],[5,0,3]);  # bottom (-Z)

# points(flat)の重心。電極 disc の軸=頭中心→電極 の外向き方向に使う。
sub _centroid3 {
    my ($P) = @_;
    my $n = @$P / 3;
    return (0,0,0) unless $n;
    my @c = (0,0,0);
    for my $i (0 .. $n-1) { $c[0]+=$P->[3*$i]; $c[1]+=$P->[3*$i+1]; $c[2]+=$P->[3*$i+2]; }
    return ($c[0]/$n, $c[1]/$n, $c[2]/$n);
}

# 向き付き薄円柱(disc)を三角スープで返す。中心(cx,cy,cz)、軸(nx,ny,nz)、
# 半径 r、高さ h、側面分割 nseg。EEG ディスク電極用: 軸=頭皮法線(外向き)。
# 返り値: [ [[x,y,z],[x,y,z],[x,y,z]], ... ](上蓋 nseg + 下蓋 nseg + 側面 2*nseg)。
sub _disc_tris {
    my ($cx,$cy,$cz, $nx,$ny,$nz, $r, $h, $nseg) = @_;
    $nseg ||= 20;
    my $nl = sqrt($nx*$nx+$ny*$ny+$nz*$nz) || 1;
    my ($ux,$uy,$uz) = ($nx/$nl, $ny/$nl, $nz/$nl);              # 軸(単位)
    my ($ax,$ay,$az) = (abs($uz) < 0.9) ? (0,0,1) : (0,1,0);    # 軸と非平行な補助
    my ($e1x,$e1y,$e1z) = ($ay*$uz-$az*$uy, $az*$ux-$ax*$uz, $ax*$uy-$ay*$ux);  # e1 = a×axis
    my $e1l = sqrt($e1x**2+$e1y**2+$e1z**2) || 1; $e1x/=$e1l; $e1y/=$e1l; $e1z/=$e1l;
    my ($e2x,$e2y,$e2z) = ($uy*$e1z-$uz*$e1y, $uz*$e1x-$ux*$e1z, $ux*$e1y-$uy*$e1x); # e2 = axis×e1
    my $hh = $h/2;
    my $T = [ $cx+$ux*$hh, $cy+$uy*$hh, $cz+$uz*$hh ];   # 上蓋中心
    my $B = [ $cx-$ux*$hh, $cy-$uy*$hh, $cz-$uz*$hh ];   # 下蓋中心
    my (@rt, @rb);
    for my $k (0 .. $nseg-1) {
        my $th = 2*3.14159265358979 * $k / $nseg;
        my ($c,$s) = (cos($th), sin($th));
        my ($ox,$oy,$oz) = ( $r*($c*$e1x+$s*$e2x), $r*($c*$e1y+$s*$e2y), $r*($c*$e1z+$s*$e2z) );
        push @rt, [ $T->[0]+$ox, $T->[1]+$oy, $T->[2]+$oz ];
        push @rb, [ $B->[0]+$ox, $B->[1]+$oy, $B->[2]+$oz ];
    }
    my @tri;
    for my $k (0 .. $nseg-1) {
        my $k1 = ($k+1) % $nseg;
        push @tri, [ $T, $rt[$k], $rt[$k1] ];          # 上蓋
        push @tri, [ $B, $rb[$k1], $rb[$k] ];          # 下蓋(逆巻き)
        push @tri, [ $rt[$k], $rb[$k], $rb[$k1] ];     # 側面
        push @tri, [ $rt[$k], $rb[$k1], $rt[$k1] ];
    }
    return \@tri;
}

# ---------------------------------------------------------------------------
# OBJ
# ---------------------------------------------------------------------------
sub scene_to_obj {
    my ($scene, %opt) = @_;
    my $mname  = $opt{mesh_name} // 'cortex';
    # 電極マーカ = 薄い円柱(disc)。直径 8mm / 高さ 2mm / 側面 20 分割 が既定。
    my $ediam  = defined $opt{electrode_diameter} ? $opt{electrode_diameter} : 8;
    my $ehgt   = defined $opt{electrode_height}   ? $opt{electrode_height}   : 2;
    my $eseg   = $opt{electrode_segments} // 20;

    my @out;
    push @out, "# giza-server 3D scene export (OBJ)";
    push @out, "# coordinate frame: MNI mm, right-handed (+X right / +Y front / +Z up)";

    my $vbase = 0;   # OBJ 頂点 index は全 object 通し・1-based

    # ---- cortex mesh ----
    if (my $m = $scene->{mesh}) {
        my $V  = $m->{verts} or croak "mesh.verts required";
        my $F  = $m->{faces} or croak "mesh.faces required";
        my $VC = $m->{vcolors};
        my $nv = @$V / 3;
        _croak_len("mesh.verts",   $V, 3);
        _croak_len("mesh.faces",   $F, 3);
        _croak_len("mesh.vcolors", $VC, 3) if $VC;
        croak "mesh.vcolors length must match verts" if $VC && @$VC != @$V;

        push @out, "o $mname";
        if ($VC) {
            for my $i (0 .. $nv-1) {
                push @out, sprintf "v %.6f %.6f %.6f %.6f %.6f %.6f",
                    @$V[3*$i,3*$i+1,3*$i+2], @$VC[3*$i,3*$i+1,3*$i+2];
            }
        } else {
            for my $i (0 .. $nv-1) {
                push @out, sprintf "v %.6f %.6f %.6f", @$V[3*$i,3*$i+1,3*$i+2];
            }
        }
        for my $i (0 .. @$F/3 - 1) {
            # 0-based -> 1-based(+ 通し offset)
            push @out, sprintf "f %d %d %d",
                $F->[3*$i]  +1+$vbase,
                $F->[3*$i+1]+1+$vbase,
                $F->[3*$i+2]+1+$vbase;
        }
        $vbase += $nv;
    }

    # ---- 電極(薄円柱 disc。軸=頭中心からの外向き=頭皮法線) ----
    if (my $P = $scene->{points}) {
        _croak_len("points",  $P, 3);
        my $PC = $scene->{pcolors};
        _croak_len("pcolors", $PC, 3) if $PC;
        my $lab = $scene->{labels};
        my $np  = @$P / 3;
        my ($gx,$gy,$gz) = _centroid3($P);
        my $er = $ediam / 2;
        push @out, "o electrodes";
        for my $e (0 .. $np-1) {
            my @c = @$P[3*$e, 3*$e+1, 3*$e+2];
            my ($nx,$ny,$nz) = ($c[0]-$gx, $c[1]-$gy, $c[2]-$gz);   # 外向き軸
            ($nx,$ny,$nz) = (0,0,1) if sqrt($nx*$nx+$ny*$ny+$nz*$nz) < 1e-6;
            my $name = $lab ? _obj_name($lab->[$e]) : sprintf("e%d", $e);
            push @out, "g $name";
            my @col = $PC ? @$PC[3*$e,3*$e+1,3*$e+2] : ();
            my $tris = _disc_tris(@c, $nx,$ny,$nz, $er, $ehgt, $eseg);
            for my $t (@$tris) {
                my @idx;
                for my $v (@$t) {
                    if ($PC) { push @out, sprintf "v %.6f %.6f %.6f %.6f %.6f %.6f", @$v, @col; }
                    else     { push @out, sprintf "v %.6f %.6f %.6f", @$v; }
                    push @idx, ++$vbase;
                }
                push @out, sprintf "f %d %d %d", @idx;
            }
        }
    }

    # ---- ラベル(焼き込み塗り面テキスト。LabelGeom で作った world 三角) ----
    if (my $L = $scene->{labels3d}) {
        push @out, "o labels";
        for my $lab (@$L) {
            my $col = $lab->{color};
            for my $t (@{$lab->{tris}}) {
                my @idx;
                for my $v (@$t) {
                    if ($col) {
                        push @out, sprintf "v %.6f %.6f %.6f %.6f %.6f %.6f", @$v, @$col;
                    } else {
                        push @out, sprintf "v %.6f %.6f %.6f", @$v;
                    }
                    push @idx, ++$vbase;   # 全 object 通し 1-based
                }
                push @out, sprintf "f %d %d %d", @idx;
            }
        }
    }

    return join("\n", @out) . "\n";
}

# ---------------------------------------------------------------------------
# USDA
# ---------------------------------------------------------------------------
sub scene_to_usda {
    my ($scene, %opt) = @_;
    my $mname    = $opt{mesh_name} // 'cortex';
    # 電極マーカ = 薄い円柱(disc)。直径 8mm / 高さ 2mm / 側面 20 分割 が既定。
    my $ediam    = defined $opt{electrode_diameter} ? $opt{electrode_diameter} : 8;
    my $ehgt     = defined $opt{electrode_height}   ? $opt{electrode_height}   : 2;
    my $eseg     = $opt{electrode_segments} // 20;
    # NYHead は素ヘッダ。既定では MNI 用に upAxis=Z / metersPerUnit を付す。
    # opt{bare_header}=1 で NYHead と同じ素ヘッダ(メタ無し)に戻す。
    my $bare     = $opt{bare_header};
    my $upaxis   = exists $opt{usda_upaxis}          ? $opt{usda_upaxis}          : 'Z';
    my $mpu      = exists $opt{usda_meters_per_unit} ? $opt{usda_meters_per_unit} : 0.001;

    my @out;
    if ($bare) {
        push @out, "#usda 1.0";
    } else {
        push @out, "#usda 1.0";
        push @out, "(";
        push @out, "    defaultPrim = \"Scene\"";
        push @out, "    metersPerUnit = $mpu" if defined $mpu;
        push @out, "    upAxis = \"$upaxis\"" if defined $upaxis;
        push @out, ")";
    }
    push @out, "";
    push @out, "def Xform \"Scene\"";
    push @out, "{";

    # ---- cortex mesh ----
    if (my $m = $scene->{mesh}) {
        my $V  = $m->{verts} or croak "mesh.verts required";
        my $F  = $m->{faces} or croak "mesh.faces required";
        my $VC = $m->{vcolors};
        my $nv = @$V / 3;
        my $nf = @$F / 3;
        _croak_len("mesh.verts", $V, 3);
        _croak_len("mesh.faces", $F, 3);
        croak "mesh.vcolors length must match verts" if $VC && @$VC != @$V;

        push @out, "    def Mesh \"$mname\"";
        push @out, "    {";
        # ポリゴンとして表示させる(既定 catmullClark だと importer が cortex を
        # 勝手に細分してしまう)。
        push @out, "        uniform token subdivisionScheme = \"none\"";
        # extent(bbox): Model I/O 等の importer が要求することがある。
        my ($mnx,$mny,$mnz,$mxx,$mxy,$mxz);
        for my $i (0 .. $nv-1) {
            my ($x,$y,$z) = @$V[3*$i,3*$i+1,3*$i+2];
            if ($i == 0) { ($mnx,$mny,$mnz,$mxx,$mxy,$mxz) = ($x,$y,$z,$x,$y,$z) }
            else {
                $mnx = $x if $x < $mnx; $mny = $y if $y < $mny; $mnz = $z if $z < $mnz;
                $mxx = $x if $x > $mxx; $mxy = $y if $y > $mxy; $mxz = $z if $z > $mxz;
            }
        }
        push @out, sprintf "        float3[] extent = [(%.6f, %.6f, %.6f), (%.6f, %.6f, %.6f)]",
                   $mnx,$mny,$mnz,$mxx,$mxy,$mxz;
        push @out, "        int[] faceVertexCounts = [" . join(", ", (3) x $nf) . "]";
        push @out, "        int[] faceVertexIndices = [" . join(", ", @$F) . "]";  # 0-based
        push @out, "        point3f[] points = ["
                 . join(", ", map { sprintf "(%.6f, %.6f, %.6f)",
                        @$V[3*$_,3*$_+1,3*$_+2] } 0..$nv-1) . "]";
        # 属性メタデータ ( ) は値の後ろに置く(USD 文法。前置は Sdf パースエラー)。
        if ($VC) {
            push @out, "        color3f[] primvars:displayColor = ["
                     . join(", ", map { sprintf "(%.6f, %.6f, %.6f)",
                            @$VC[3*$_,3*$_+1,3*$_+2] } 0..$nv-1)
                     . "] (interpolation = \"vertex\")";
        } elsif (my $c = $m->{color}) {
            push @out, "        color3f[] primvars:displayColor = ["
                     . sprintf("(%.6f, %.6f, %.6f)", @$c[0,1,2])
                     . "] (interpolation = \"constant\")";
        }
        push @out, "    }";
    }

    # ---- 電極(薄円柱 disc の Mesh。軸=頭中心からの外向き=頭皮法線) ----
    if (my $P = $scene->{points}) {
        _croak_len("points", $P, 3);
        my $PC  = $scene->{pcolors};
        my $lab = $scene->{labels};
        my $np  = @$P / 3;
        my ($gx,$gy,$gz) = _centroid3($P);
        my $er = $ediam / 2;
        my %seen;
        push @out, "    def Xform \"electrodes\"";
        push @out, "    {";
        for my $e (0 .. $np-1) {
            my @c   = @$P[3*$e,3*$e+1,3*$e+2];
            my ($nx,$ny,$nz) = ($c[0]-$gx, $c[1]-$gy, $c[2]-$gz);
            ($nx,$ny,$nz) = (0,0,1) if sqrt($nx*$nx+$ny*$ny+$nz*$nz) < 1e-6;
            my $raw = $lab ? $lab->[$e] : "e$e";
            my $nm  = _usd_name($raw, \%seen);
            my @col = $PC ? @$PC[3*$e,3*$e+1,3*$e+2] : (0.8,0.8,0.8);
            my $tris = _disc_tris(@c, $nx,$ny,$nz, $er, $ehgt, $eseg);
            my (@pts, @cnt, @idx); my $k = 0;
            for my $t (@$tris) {
                for my $v (@$t) { push @pts, sprintf("(%.6f, %.6f, %.6f)", @$v); push @idx, $k++; }
                push @cnt, 3;
            }
            push @out, "        # electrode: $raw";
            push @out, "        def Mesh \"$nm\"";
            push @out, "        {";
            push @out, "            uniform token subdivisionScheme = \"none\"";
            push @out, "            uniform bool doubleSided = true";
            push @out, "            int[] faceVertexCounts = [" . join(", ", @cnt) . "]";
            push @out, "            int[] faceVertexIndices = [" . join(", ", @idx) . "]";
            push @out, "            point3f[] points = [" . join(", ", @pts) . "]";
            push @out, sprintf "            color3f[] primvars:displayColor = [(%.6f, %.6f, %.6f)] (interpolation = \"constant\")", @col;
            push @out, "        }";
        }
        push @out, "    }";
    }

    # ---- ラベル(焼き込み塗り面テキスト。同色をまとめて Mesh 化) ----
    if (my $L = $scene->{labels3d}) {
        my (%by, @order);
        for my $lab (@$L) {
            my $key = join(',', @{ $lab->{color} // [1,1,1] });
            push @order, $key unless exists $by{$key};
            push @{ $by{$key} }, @{ $lab->{tris} };
        }
        push @out, "    def Xform \"labels\"";
        push @out, "    {";
        my $li = 0;
        for my $key (@order) {
            my (@pts, @cnt, @idx);
            my $k = 0;
            for my $t (@{ $by{$key} }) {
                for my $v (@$t) {
                    push @pts, sprintf("(%.6f, %.6f, %.6f)", @$v);
                    push @idx, $k++;
                }
                push @cnt, 3;
            }
            my @c = split /,/, $key;
            push @out, "        def Mesh \"L$li\"";
            push @out, "        {";
            push @out, "            uniform token subdivisionScheme = \"none\"";
            push @out, "            uniform bool doubleSided = true";   # 平板テキストを両面表示(裏からも見える)
            push @out, "            int[] faceVertexCounts = [" . join(", ", @cnt) . "]";
            push @out, "            int[] faceVertexIndices = [" . join(", ", @idx) . "]";
            push @out, "            point3f[] points = [" . join(", ", @pts) . "]";
            push @out, sprintf "            color3f[] primvars:displayColor = [(%.6f, %.6f, %.6f)] (interpolation = \"constant\")", @c;
            push @out, "        }";
            $li++;
        }
        push @out, "    }";
    }

    push @out, "}";
    return join("\n", @out) . "\n";
}

# ---------------------------------------------------------------------------
# ファイルへ書く(format 分岐)
# ---------------------------------------------------------------------------
sub write_scene {
    my ($scene, $format, $out, %opt) = @_;
    $format = lc $format;
    my $text = $format eq 'obj'  ? scene_to_obj($scene, %opt)
             : $format eq 'usda' ? scene_to_usda($scene, %opt)
             : croak "write_scene: unknown format '$format' (obj|usda)";
    my $fh;
    if (ref $out) { $fh = $out }
    else { open($fh, '>', $out) or croak "cannot write '$out': $!" }
    print $fh $text;
    close $fh unless ref $out;
    return $out;
}

# ---------------------------------------------------------------------------
# PDL の live scene -> プレーン scene(唯一の PDL 依存。呼ばれた時のみ require)
#   in : GS3D の $self->{scene} = { mesh=>{verts,faces,vcolors,color},
#                                   points, colors, labels }
#         verts [Nv,3] / faces [Nf,3] (0/1-based) / vcolors [Nv,3] /
#         points [N,3] / colors [N,3] / labels \@
#   out: 上記プレーン scene(flat 配列)
# ---------------------------------------------------------------------------
sub normalize_pdl_scene {
    my ($ps) = @_;
    require PDL;
    my %out;

    if (my $m = $ps->{mesh}) {
        my $vc  = $m->{verts};
        my $tri = $m->{faces};
        # 面の 0/1-based を min で判定して 0-based へ(NYHead/GS3D と同じ流儀)
        my $fmin = $tri->min;
        my $tri0 = ($fmin >= 1) ? ($tri - $fmin) : $tri;  # 通常 min は 0 か 1
        $out{mesh} = {
            verts => [ $vc ->xchg(0,1)->flat->list ],
            faces => [ $tri0->xchg(0,1)->flat->list ],
        };
        $out{mesh}{vcolors} = [ $m->{vcolors}->xchg(0,1)->flat->list ] if defined $m->{vcolors};
        $out{mesh}{color}   = $m->{color} if defined $m->{color};   # [r,g,b] は既にプレーン
    }

    if (defined $ps->{points}) {
        $out{points}  = [ $ps->{points}->xchg(0,1)->flat->list ];
        $out{pcolors} = [ $ps->{colors}->xchg(0,1)->flat->list ] if defined $ps->{colors};
        $out{labels}  = $ps->{labels} if defined $ps->{labels};    # \@ は既にプレーン
    }

    return \%out;
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
sub _croak_len {
    my ($what, $aref, $k) = @_;
    croak "$what must be a flat arrayref" unless ref $aref eq 'ARRAY';
    croak "$what length must be a multiple of $k (got ".scalar(@$aref).")"
        if @$aref % $k;
}

# OBJ の o/g 名は空白不可。ラベルの空白のみ潰す(NYHead 電極名は英数中心)。
sub _obj_name {
    my ($s) = @_;
    $s = 'e' unless defined $s && length $s;
    $s =~ s/\s+//g;
    return $s;
}

# USD prim 名は [A-Za-z_][A-Za-z0-9_]* のみ。無効文字は _ に、先頭数字は E_ 前置。
# 同名は _2,_3.. で一意化。
sub _usd_name {
    my ($raw, $seen) = @_;
    my $s = defined $raw ? "$raw" : '';
    $s =~ s/[^A-Za-z0-9_]/_/g;
    $s = "E_$s" if $s eq '' || $s =~ /^[0-9]/;
    my $base = $s;
    my $n = 2;
    $s = $base . '_' . $n++ while $seen->{$s}++;
    return $s;
}

1;
