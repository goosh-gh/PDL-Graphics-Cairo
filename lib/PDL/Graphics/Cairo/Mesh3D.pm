package PDL::Graphics::Cairo::Mesh3D;
# ============================================================================
# PDL::Graphics::Cairo::Mesh3D
#
# GS3D に面(三角メッシュ)を足すためのソフトウェアレンダリング幾何コア。
# Cairo/giza-server には z バッファが無いので、面の可視化は Perl 側で
#   頂点投影 → バックフェースカリング → 面デプスソート(画家のアルゴリズム)
#   → 単一方向光 Lambert(flat)→ スキャンライン塗り
# の順に組み立てる。
#
# 設計方針(P:EEG18):
#   * ここは「純スカラー幾何」だけを持ち、PDL に一切依存しない。バッチな
#     回転・投影(rot x pts / _project)は呼び出し側(Driver::GS3D)が PDL で
#     済ませ、その結果(スクリーン座標・回転後座標)を配列で渡す。
#   * よって本モジュールは PDL 不在の環境でも load / テストできる
#     (overlay_scalp_obj.pl の --selftest と同じ流儀。giza-server 接続も不要)。
#   * 検証は tools/verify_gs3d_mesh.pl(Test::More、PDL 不要)。
#
# 座標規約(Driver::GS3D と一致):
#   * 回転後 world 座標の +Z がカメラ手前(near)。_project の遠近では
#     w = fov/(fov - z + 200) なので z 大 = w 大 = 近い。点群は depth 昇順
#     (奥→手前)で送る。面も同じく face-depth 昇順で送れば画家順になる。
#   * screen-x は _project 側で反転(cx - x)される。バックフェース判定は
#     screen 空間の符号ではなく「回転後 3D 法線の z 成分」で行うので、この
#     反転の影響を受けない(向きが変わっても正しく front/back が入れ替わる)。
#   * 光源 L は view 空間固定(ヘッドランプ的)。法線も回転後空間で評価する
#     ので、オブジェクトを回すと陰影が自然に追従する。
# ============================================================================
use strict;
use warnings;

our $VERSION = '0.2';

use Exporter 'import';
our @EXPORT_OK = qw(
    detect_face_base
    tri_area2
    face_normal
    normalize3
    lambert
    shade_color
    scanline_spans
    painter_order
    bbox_offscreen
    nearest_index_2d
);

# ----------------------------------------------------------------------------
# detect_face_base($min_vertex_index) -> 0 | 1
#   tri が 0-based か 1-based かを最小インデックスから判定。overlay_scalp_obj.pl
#   と同じ流儀(NY Head の tri は 1-based、自作メッシュは 0-based のことが多い)。
#   最小 index が 0 なら 0-based、1 以上(かつ頂点数以下)なら 1-based とみなす。
# ----------------------------------------------------------------------------
sub detect_face_base {
    my ($min_idx) = @_;
    return 0 if !defined $min_idx;
    return $min_idx <= 0 ? 0 : 1;
}

# ----------------------------------------------------------------------------
# tri_area2($ax,$ay,$bx,$by,$cx,$cy) -> 符号付き面積 ×2 (2D スクリーン空間)
#   >0 と <0 でスクリーン上のワインディング向きが分かる。退化三角形は 0。
# ----------------------------------------------------------------------------
sub tri_area2 {
    my ($ax,$ay,$bx,$by,$cx,$cy) = @_;
    return ($bx-$ax)*($cy-$ay) - ($cx-$ax)*($by-$ay);
}

# ----------------------------------------------------------------------------
# normalize3($x,$y,$z) -> ($x,$y,$z) 正規化(長さ 0 は 0 のまま返す)
# ----------------------------------------------------------------------------
sub normalize3 {
    my ($x,$y,$z) = @_;
    my $n = sqrt($x*$x + $y*$y + $z*$z);
    return (0,0,0) if $n == 0;
    return ($x/$n, $y/$n, $z/$n);
}

# ----------------------------------------------------------------------------
# face_normal(\@v0,\@v1,\@v2) -> ($nx,$ny,$nz)  (回転後 3D 座標での面法線)
#   n = (v1-v0) × (v2-v0)。正規化はしない(呼び出し側で必要なら normalize3)。
#   各 \@vi は [x,y,z]。
# ----------------------------------------------------------------------------
sub face_normal {
    my ($v0,$v1,$v2) = @_;
    my ($ux,$uy,$uz) = ($v1->[0]-$v0->[0], $v1->[1]-$v0->[1], $v1->[2]-$v0->[2]);
    my ($wx,$wy,$wz) = ($v2->[0]-$v0->[0], $v2->[1]-$v0->[1], $v2->[2]-$v0->[2]);
    return ( $uy*$wz - $uz*$wy,
             $uz*$wx - $ux*$wz,
             $ux*$wy - $uy*$wx );
}

# ----------------------------------------------------------------------------
# lambert($nx,$ny,$nz, $lx,$ly,$lz, $ambient) -> 強度 [0,1]
#   I = ambient + (1-ambient) * max(0, n̂·L̂)。n と L は内部で正規化。
#   ambient は既定 0.25。裏返り面(n·L<0)は ambient で下限クランプ。
# ----------------------------------------------------------------------------
sub lambert {
    my ($nx,$ny,$nz, $lx,$ly,$lz, $ambient) = @_;
    $ambient = 0.25 unless defined $ambient;
    ($nx,$ny,$nz) = normalize3($nx,$ny,$nz);
    ($lx,$ly,$lz) = normalize3($lx,$ly,$lz);
    my $d = $nx*$lx + $ny*$ly + $nz*$lz;
    $d = 0 if $d < 0;
    my $I = $ambient + (1 - $ambient) * $d;
    $I = 0 if $I < 0;
    $I = 1 if $I > 1;
    return $I;
}

# ----------------------------------------------------------------------------
# shade_color(\@rgb01, $intensity, $alpha) -> [R,G,B,A]  各 0-255 整数
#   base(0-1)に強度を掛けて 8bit 化。$alpha 既定 255。
# ----------------------------------------------------------------------------
sub shade_color {
    my ($rgb, $I, $alpha) = @_;
    $alpha = 255 unless defined $alpha;
    my @out;
    for my $c (0..2) {
        my $v = int($rgb->[$c] * $I * 255 + 0.5);
        $v = 0   if $v < 0;
        $v = 255 if $v > 255;
        push @out, $v;
    }
    push @out, $alpha;
    return \@out;
}

# ----------------------------------------------------------------------------
# scanline_spans(\@sx, \@sy, $step, $W, $H) -> ( [y,xL,xR], ... )
#   スクリーン座標の三角形(3 頂点)を水平スパンに分解する。標準的な
#   スキャンライン多角形塗り。各エッジを半開区間 [lo,hi) で交差判定する
#   ことで、頂点共有点での二重カウント/隙間を防ぐ(=ちょうど 2 交点)。
#   $step: 走査ピクセル間隔(既定 1)。大きくすると本数を間引ける(u16 上限
#          対策)。塗り線幅は呼び出し側で $step に合わせること。
#   $W,$H: 与えると **ビューポート [0,W]×[0,H] にクリップ**する(強拡大で
#          画面外まで塗って本数が爆発するのを防ぐ)。省略時はクリップ無し。
#   退化三角形(高さ 0)や画面外は空リストを返す。
# ----------------------------------------------------------------------------
sub scanline_spans {
    my ($sx, $sy, $step, $W, $H) = @_;
    $step = 1 unless $step && $step > 0;

    my $ymin = $sy->[0]; my $ymax = $sy->[0];
    for my $i (1,2) {
        $ymin = $sy->[$i] if $sy->[$i] < $ymin;
        $ymax = $sy->[$i] if $sy->[$i] > $ymax;
    }
    my $y0 = _ceil($ymin);
    my $y1 = _floor($ymax);
    if (defined $H) {                        # 縦クリップ
        $y0 = 0      if $y0 < 0;
        $y1 = $H - 1 if $y1 > $H - 1;
    }
    return () if $y1 < $y0;

    my @edges = ([0,1],[1,2],[2,0]);
    my @spans;
    for (my $y = $y0; $y <= $y1; $y += $step) {
        my @xs;
        for my $e (@edges) {
            my ($p,$q) = @$e;
            my ($ya,$yb) = ($sy->[$p], $sy->[$q]);
            next if $ya == $yb;                    # 水平エッジは無視
            my ($lo,$hi,$xa,$dy,$dx);
            if ($ya < $yb) { $lo=$ya; $hi=$yb; $xa=$sx->[$p]; $dy=$yb-$ya; $dx=$sx->[$q]-$sx->[$p]; }
            else           { $lo=$yb; $hi=$ya; $xa=$sx->[$q]; $dy=$ya-$yb; $dx=$sx->[$p]-$sx->[$q]; }
            next unless $y >= $lo && $y < $hi;      # 半開 [lo,hi)
            push @xs, $xa + ($y - $lo) / $dy * $dx;
        }
        next if @xs < 2;
        @xs = sort { $a <=> $b } @xs;
        my ($xL, $xR) = ($xs[0], $xs[-1]);
        if (defined $W) {                    # 横クリップ
            $xL = 0  if $xL < 0;
            $xR = $W if $xR > $W;
            next if $xR <= $xL;              # 画面外
        }
        push @spans, [ $y, $xL, $xR ];
    }
    return @spans;
}

# ----------------------------------------------------------------------------
# bbox_offscreen(\@sx, \@sy, $W, $H) -> bool
#   三角形の投影バウンディングボックスがビューポート [0,W]×[0,H] の外に
#   完全に出ていれば真(=カリング対象)。強拡大時に画面外の巨大面を
#   スキャンライン化しないための早期棄却。
# ----------------------------------------------------------------------------
sub bbox_offscreen {
    my ($sx, $sy, $W, $H) = @_;
    my ($minx,$maxx) = ($sx->[0],$sx->[0]);
    my ($miny,$maxy) = ($sy->[0],$sy->[0]);
    for my $i (1,2) {
        $minx = $sx->[$i] if $sx->[$i] < $minx;
        $maxx = $sx->[$i] if $sx->[$i] > $maxx;
        $miny = $sy->[$i] if $sy->[$i] < $miny;
        $maxy = $sy->[$i] if $sy->[$i] > $maxy;
    }
    return ($maxx < 0 || $minx > $W || $maxy < 0 || $miny > $H) ? 1 : 0;
}

# ----------------------------------------------------------------------------
# nearest_index_2d(\@sx, \@sy, $px, $py, \@eligible) -> ($index, $dist)
#   スクリーン座標 (px,py) に投影が最も近い頂点の index と距離を返す。
#   \@eligible(省略可): 真の要素だけを候補にする(例: front-facing のみ)。
#   クリック pick 用。候補が無ければ (-1, undef)。
# ----------------------------------------------------------------------------
sub nearest_index_2d {
    my ($sx, $sy, $px, $py, $elig) = @_;
    my ($best, $bd) = (-1, undef);
    for my $i (0 .. $#$sx) {
        next if $elig && !$elig->[$i];
        my $d = ($sx->[$i]-$px)**2 + ($sy->[$i]-$py)**2;
        if (!defined $bd || $d < $bd) { $bd = $d; $best = $i; }
    }
    return ($best, defined $bd ? sqrt($bd) : undef);
}

# ----------------------------------------------------------------------------
# painter_order(\@depths) -> @indices  (depth 昇順 = 奥→手前)
#   安定ソート。GS3D の点群と同じ「奥から先に描く」順。
# ----------------------------------------------------------------------------
sub painter_order {
    my ($depths) = @_;
    return sort { $depths->[$a] <=> $depths->[$b] } 0 .. $#$depths;
}

# ---- 内部: PDL/POSIX 非依存の ceil/floor -----------------------------------
sub _floor { my $x = shift; my $i = int($x); return ($x < $i) ? $i - 1 : $i; }
sub _ceil  { my $x = shift; my $i = int($x); return ($x > $i) ? $i + 1 : $i; }

1;

__END__

=encoding utf-8

=head1 NAME

PDL::Graphics::Cairo::Mesh3D - GS3D 面描画のためのソフトウェア幾何コア

=head1 DESCRIPTION

Cairo/giza-server には z バッファが無いため、三角メッシュの面(faces)を
可視化するには Perl 側でソフトウェアパイプラインを組む必要がある。本モジュールは
そのうち PDL に依存しないスカラー幾何(バックフェース判定・面デプスソート・
Lambert 陰影・スキャンライン塗り)だけを提供する。バッチな回転・投影は
呼び出し側(L<PDL::Graphics::Cairo::Driver::GS3D>)が PDL で行い、その結果を
本モジュールに配列で渡す。この分離により、PDL/giza-server 不在の環境でも
L<tools/verify_gs3d_mesh.pl> で幾何を headless 検証できる。

=head1 SEE ALSO

L<PDL::Graphics::Cairo::Driver::GS3D>, F<tools/verify_gs3d_mesh.pl>

=cut
