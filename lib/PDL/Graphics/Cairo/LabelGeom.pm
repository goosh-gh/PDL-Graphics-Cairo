package PDL::Graphics::Cairo::LabelGeom;
# ============================================================================
# PDL::Graphics::Cairo::LabelGeom
#   電極ラベルを「エクスポート時のカメラ向きに焼き込んだ塗り面テキスト」として
#   出すための幾何ユーティリティ(PDL 非依存・純 Perl・ヘッドレス検証可)。
#
#   giza-server はラベルを画面 2D に貼り付ける(常に正面=ビルボード)が、静的な
#   .obj/.usda では「常にカメラを向く」を保持できない。そこでエクスポート時の
#   カメラ基底(right,up)を使い、各ラベルの 2D アウトライン(cairo text_path で
#   得た Helvetica グリフ)をその平面に配置=その角度では画面と一致する。
#
#   本モジュールが担うのは環境非依存の2つ:
#     * tessellate(\@contours)     穴あき多角形 → 三角形(earcut)
#     * billboard_tris(...)        2D 三角 → カメラ平面上のワールド三角
#   グリフの 2D アウトライン抽出(Helvetica)は cairo に依存するため Mac 側で
#   行い、その contours を tessellate に渡す(下記 SYNOPSIS)。
#
#   contours 形式: 各輪郭は [[x,y],[x,y],...](閉路。最後に始点を繰り返さない)。
#   1グリフ = 最大面積の輪郭を outer、その内側に含まれる輪郭を hole とみなす
#   (O,0,p,8,A 等の穴に対応)。i/j のような分離した2塊は非対応(EEG ラベルには
#   出ない)。複数グリフはグリフ単位で tessellate して連結する。
# ============================================================================
use strict;
use warnings;
use Carp;
use Exporter 'import';

our @EXPORT_OK = qw(tessellate tessellate_text billboard_tris label_to_world_tris signed_area);

# ---- 符号付き面積(CCW>0) ----
sub signed_area {
    my ($ring) = @_;
    my $a = 0;
    my $n = @$ring;
    for my $i (0 .. $n-1) {
        my $p = $ring->[$i];
        my $q = $ring->[($i+1) % $n];
        $a += $p->[0]*$q->[1] - $q->[0]*$p->[1];
    }
    return $a / 2;
}

# ---- 点が輪郭内(ray casting) ----
sub _point_in_ring {
    my ($x, $y, $ring) = @_;
    my $in = 0;
    my $n  = @$ring;
    for (my $i = 0, my $j = $n-1; $i < $n; $j = $i++) {
        my ($xi,$yi) = @{$ring->[$i]};
        my ($xj,$yj) = @{$ring->[$j]};
        if ( (($yi > $y) != ($yj > $y))
          && ($x < ($xj-$xi)*($y-$yi)/(($yj-$yi)||1e-30) + $xi) ) {
            $in = !$in;
        }
    }
    return $in;
}

# ============================================================
# tessellate_text(\@contours) -> \@tris
#   複数グリフ("Cz" 等)の輪郭群を包含関係でグリフ単位にまとめて三角化する。
#   各輪郭について「自身を含む最小面積の輪郭」を親とし、親を持たない輪郭を
#   outer(グリフ本体)、親を持つ輪郭をその hole とみなす(O/8/p の穴に対応、
#   隣接グリフは互いに含まないので別グループ)。i/j のような分離2塊は
#   別々の outer として正しく出る(この関数では非対応の縛りは無い)。
# ============================================================
sub tessellate_text {
    my ($contours) = @_;
    return [] unless $contours && @$contours;
    my @area = map { abs(signed_area($_)) } @$contours;
    my (@is_outer, @holes_of);
    for my $i (0 .. $#$contours) {
        my ($px,$py) = @{ $contours->[$i][0] };
        my ($best,$barea) = (-1, 1e30);
        for my $j (0 .. $#$contours) {
            next if $j == $i;
            next unless _point_in_ring($px, $py, $contours->[$j]);
            ($best,$barea) = ($j,$area[$j]) if $area[$j] < $barea;
        }
        if ($best < 0) { $is_outer[$i] = 1 }
        else           { push @{ $holes_of[$best] }, $i }
    }
    my @tris;
    for my $i (0 .. $#$contours) {
        next unless $is_outer[$i];
        my @group = ( $contours->[$i], map { $contours->[$_] } @{ $holes_of[$i] // [] } );
        push @tris, @{ tessellate(\@group) };
    }
    return \@tris;
}

# ============================================================
#   1グリフ分の輪郭群を三角化。outer=最大面積、hole=outer に含まれる輪郭。
#   outer を CCW、hole を CW に正規化して earcut に渡す。
# ============================================================
sub tessellate {
    my ($contours) = @_;
    return [] unless $contours && @$contours;

    # outer = |面積|最大
    my ($oi, $omax) = (0, -1);
    for my $i (0 .. $#$contours) {
        my $ar = abs(signed_area($contours->[$i]));
        ($oi, $omax) = ($i, $ar) if $ar > $omax;
    }
    my @outer = @{ $contours->[$oi] };
    @outer = reverse @outer if signed_area(\@outer) < 0;    # CCW へ

    my @holes;
    for my $i (0 .. $#$contours) {
        next if $i == $oi;
        my $h = $contours->[$i];
        # outer 内にある輪郭だけ hole 扱い(重心で判定)
        my ($cx,$cy) = (0,0);
        $cx += $_->[0] for @$h; $cy += $_->[1] for @$h;
        $cx /= @$h; $cy /= @$h;
        next unless _point_in_ring($cx, $cy, \@outer);
        my @hh = @$h;
        @hh = reverse @hh if signed_area(\@hh) > 0;         # hole は CW へ
        push @holes, \@hh;
    }

    return _earcut_with_holes(\@outer, \@holes);
}

# ---- earcut(穴ブリッジ + 耳刈り。z-order 最適化は省略) ----
# 参考: mapbox/earcut のアルゴリズム構造を Perl へ素直に移植。
sub _earcut_with_holes {
    my ($outer, $holes) = @_;
    my $outerNode = _linked_list($outer, 0, 1);   # CCW
    return [] unless $outerNode;
    $outerNode = _eliminate_holes($holes, $outerNode) if $holes && @$holes;

    my @tris;
    _earcut_linked($outerNode, \@tris);
    return \@tris;
}

# ノード: {x,y,prev,next,i,steiner}
sub _node { my ($i,$x,$y)=@_; my $n={ i=>$i, x=>$x, y=>$y, prev=>undef, next=>undef, steiner=>0 }; return $n; }

sub _linked_list {
    my ($ring, $start_i, $ccw) = @_;   # ccw: 1=そのまま CCW を期待
    my $n = @$ring;
    return undef if $n < 3;
    my $last;
    my $area = signed_area($ring);
    # CCW にしたい(outer)。すでに呼び出し側で向きを揃えてあるので順方向で連結。
    for my $k (0 .. $n-1) {
        my $p = $ring->[$k];
        $last = _insert_node($start_i + $k, $p->[0], $p->[1], $last);
    }
    # 連結を閉じる
    if ($last && _equals($last, $last->{next})) {
        _remove_node($last);
        $last = $last->{next};
    }
    return $last;
}

sub _insert_node {
    my ($i, $x, $y, $last) = @_;
    my $p = _node($i, $x, $y);
    if (!$last) { $p->{prev} = $p; $p->{next} = $p; }
    else {
        $p->{next} = $last->{next};
        $p->{prev} = $last;
        $last->{next}{prev} = $p;
        $last->{next} = $p;
    }
    return $p;
}
sub _remove_node {
    my ($p) = @_;
    $p->{next}{prev} = $p->{prev};
    $p->{prev}{next} = $p->{next};
}
sub _equals { my ($a,$b)=@_; return $a->{x}==$b->{x} && $a->{y}==$b->{y}; }

sub _earcut_linked {
    my ($ear, $tris) = @_;
    return unless $ear;
    my $stop = $ear;
    my ($prev, $next);
    my $guard = 0;
    while ($ear->{prev} != $ear->{next}) {
        $prev = $ear->{prev};
        $next = $ear->{next};
        if (_is_ear($ear)) {
            push @$tris, [ [$prev->{x},$prev->{y}], [$ear->{x},$ear->{y}], [$next->{x},$next->{y}] ];
            _remove_node($ear);
            $ear  = $next->{next};
            $stop = $next->{next};
            next;
        }
        $ear = $next;
        if ($ear == $stop) {
            last;   # 進展なし(数値縮退)→打ち切り
        }
    }
}

sub _is_ear {
    my ($ear) = @_;
    my $a = $ear->{prev}; my $b = $ear; my $c = $ear->{next};
    return 0 if _area($a,$b,$c) >= 0;   # reflex(CCW 前提で凸のみ耳候補)
    # 三角内に他頂点が無いこと
    my $p = $ear->{next}{next};
    while ($p != $ear->{prev}) {
        if (_point_in_tri($a->{x},$a->{y},$b->{x},$b->{y},$c->{x},$c->{y},$p->{x},$p->{y})
            && _area($p->{prev},$p,$p->{next}) >= 0) {
            return 0;
        }
        $p = $p->{next};
    }
    return 1;
}

sub _area { my ($p,$q,$r)=@_; return ($q->{y}-$p->{y})*($r->{x}-$q->{x}) - ($q->{x}-$p->{x})*($r->{y}-$q->{y}); }

sub _point_in_tri {
    my ($ax,$ay,$bx,$by,$cx,$cy,$px,$py) = @_;
    return (($cx-$px)*($ay-$py) - ($ax-$px)*($cy-$py)) >= 0
        && (($ax-$px)*($by-$py) - ($bx-$px)*($ay-$py)) >= 0
        && (($bx-$px)*($cy-$py) - ($cx-$px)*($by-$py)) >= 0;
}

# ---- 穴を outer にブリッジして1本の輪にする ----
sub _eliminate_holes {
    my ($holes, $outerNode) = @_;
    my @queue;
    for my $h (@$holes) {
        my $list = _linked_list($h, 0, 0);
        next unless $list;
        push @queue, _leftmost($list);
    }
    @queue = sort { $a->{x} <=> $b->{x} or $a->{y} <=> $b->{y} } @queue;
    for my $hole (@queue) {
        $outerNode = _eliminate_hole($hole, $outerNode);
    }
    return $outerNode;
}
sub _leftmost {
    my ($start) = @_;
    my $p = $start; my $left = $start;
    do { $left = $p if $p->{x} < $left->{x} || ($p->{x}==$left->{x} && $p->{y}<$left->{y});
         $p = $p->{next}; } while ($p != $start);
    return $left;
}
sub _eliminate_hole {
    my ($hole, $outerNode) = @_;
    my $bridge = _find_bridge($hole, $outerNode);
    return $outerNode unless $bridge;
    my $bridgeReverse = _split_bridge($bridge, $hole);
    return $outerNode;
}
# outer 上で hole とブリッジ可能な可視頂点を探す(hole の最左点から +x 方向)
sub _find_bridge {
    my ($hole, $outerNode) = @_;
    my $p = $outerNode;
    my $hx = $hole->{x}; my $hy = $hole->{y};
    my $qx = -1e30; my $m;
    do {
        my $a = $p; my $b = $p->{next};
        if ($hy <= $a->{y} && $hy >= $b->{y} && $b->{y} != $a->{y}) {
            my $x = $a->{x} + ($hy-$a->{y})*($b->{x}-$a->{x})/($b->{y}-$a->{y});
            if ($x <= $hx && $x > $qx) { $qx = $x; $m = ($a->{x} < $b->{x}) ? $a : $b; }
        }
        $p = $p->{next};
    } while ($p != $outerNode);
    return $m;
}
sub _split_bridge {
    my ($a, $b) = @_;
    # a(outer) と b(hole) を2本の辺で繋ぎ、hole を outer に取り込む
    my $a2 = _node($a->{i}, $a->{x}, $a->{y});
    my $b2 = _node($b->{i}, $b->{x}, $b->{y});
    my $an = $a->{next};
    my $bp = $b->{prev};
    $a->{next} = $b;  $b->{prev} = $a;
    $b2->{next} = $a2; $a2->{prev} = $b2;
    $an->{prev} = $a2; $a2->{next} = $an;
    $b2->{prev} = $bp; $bp->{next} = $b2;
    return $b2;
}

# ============================================================
# billboard_tris(\@tris2d, $origin, $right, $up) -> \@tris3d
#   2D 三角(グリフ平面, mm) を origin + x*right + y*up でワールドへ。
#   right,up はエクスポート時のカメラ基底(単位ベクトル, 直交)。
#   $tri3d = [[X,Y,Z],[X,Y,Z],[X,Y,Z]]
# ============================================================
sub billboard_tris {
    my ($tris2d, $origin, $right, $up) = @_;
    my ($ox,$oy,$oz) = @$origin;
    my ($rx,$ry,$rz) = @$right;
    my ($ux,$uy,$uz) = @$up;
    my @out;
    for my $t (@$tris2d) {
        my @v3;
        for my $v (@$t) {
            my ($x,$y) = @$v;
            push @v3, [ $ox + $x*$rx + $y*$ux,
                        $oy + $x*$ry + $y*$uy,
                        $oz + $x*$rz + $y*$uz ];
        }
        push @out, \@v3;
    }
    return \@out;
}

# 便宜: 1グリフ(または連結済み contours) -> ワールド三角
sub label_to_world_tris {
    my ($contours, $origin, $right, $up) = @_;
    my $tris2d = tessellate($contours);
    return billboard_tris($tris2d, $origin, $right, $up);
}

1;

__END__

=encoding utf-8

=head1 SYNOPSIS (Mac 側: cairo で Helvetica アウトライン抽出 → 本モジュールで配置)

    use Cairo;
    use PDL::Graphics::Cairo::LabelGeom qw(label_to_world_tris);

    # 1) cairo に "Helvetica" で text_path を積み、パスを contours に落とす
    my $surf = Cairo::ImageSurface->create('argb32', 1, 1);
    my $cr   = Cairo::Context->create($surf);
    $cr->select_font_face('Helvetica', 'normal', 'normal');
    $cr->set_font_size($cap_mm);          # mm を単位に使う(後でスケール調整可)
    $cr->new_path; $cr->move_to(0,0);
    $cr->text_path($label_text);          # 例 'Cz'
    my $path = $cr->copy_path_flat;       # ベジエを線分に平坦化

    # 2) path -> contours (move_to で新輪郭、line_to で点、close_path で確定)
    #    cairo の y は下向きなので y を反転して y-up の mm 平面にする
    my (@contours, @cur);
    for my $seg (@{ $path->{path} }) {
        if    ($seg->{type} eq 'move-to') { push @contours, [@cur] if @cur; @cur = ([$seg->{points}[0][0], -$seg->{points}[0][1]]); }
        elsif ($seg->{type} eq 'line-to') { push @cur, [$seg->{points}[0][0], -$seg->{points}[0][1]]; }
        elsif ($seg->{type} eq 'close-path') { push @contours, [@cur] if @cur; @cur = (); }
    }
    push @contours, [@cur] if @cur;

    # 3) カメラ基底(エクスポート時の回転から)で電極位置へ配置
    my $tris = label_to_world_tris(\@contours, [$ex,$ey,$ez], $right, $up);
    #    -> SceneExport の scene->{labels3d} に { tris=>$tris, color=>[r,g,b] } で渡す

グリフを個別に扱う場合は 1グリフずつ text_path→contours→tessellate し、
x 送り(advance)分だけ平行移動して連結する。

=cut
