#!/usr/bin/env perl
# verify_gs3d_mesh.pl — GS3D 面描画の幾何コア(Mesh3D.pm)を headless 検証する。
#
#   * PDL / giza-server / 描画 / 目視は不要。純スカラー幾何のみを叩く
#     (overlay_scalp_obj.pl の --selftest と同じ流儀)。
#   * バッチな回転・投影は Driver::GS3D 側(PDL)の責務なのでここでは検証しない。
#     ここが固めるのは「面法線・バックフェース符号・画家順・Lambert クランプ・
#     スキャンライン被覆・面 base 判定」。
#
# 使い方:
#   perl tools/verify_gs3d_mesh.pl                 # リポジトリルートで
#   perl tools/verify_gs3d_mesh.pl --lib lib
use strict;
use warnings;
use Test::More;

my $LIB = 'lib';
for (my $i = 0; $i < @ARGV; $i++) {
    $LIB = $ARGV[$i+1] if $ARGV[$i] eq '--lib';
}
unshift @INC, $LIB;

require PDL::Graphics::Cairo::Mesh3D;
PDL::Graphics::Cairo::Mesh3D->import(qw(
    detect_face_base tri_area2 face_normal normalize3
    lambert shade_color scanline_spans painter_order
    bbox_offscreen nearest_index_2d
));

sub near { my ($a,$b,$eps)=@_; $eps//=1e-9; abs($a-$b) <= $eps }

# ---------------------------------------------------------------------------
# [1] detect_face_base: 最小 index から 0/1-based を判定
# ---------------------------------------------------------------------------
is( detect_face_base(0), 0, 'base: min index 0 -> 0-based' );
is( detect_face_base(1), 1, 'base: min index 1 -> 1-based' );
is( detect_face_base(5), 1, 'base: min index >=1 -> 1-based' );

# ---------------------------------------------------------------------------
# [2] tri_area2: 符号付き 2D 面積 ×2(ワインディング検出)
# ---------------------------------------------------------------------------
# CCW(数学正)の直角三角形 (0,0)(1,0)(0,1): 面積 0.5 → ×2 = 1
is( tri_area2(0,0, 1,0, 0,1),  1, 'area2: CCW unit tri = +1' );
# CW に反転すると符号反転
is( tri_area2(0,0, 0,1, 1,0), -1, 'area2: CW unit tri = -1' );
# 退化(共線)は 0
is( tri_area2(0,0, 1,1, 2,2),  0, 'area2: collinear = 0' );

# ---------------------------------------------------------------------------
# [3] face_normal: 外積で面法線
# ---------------------------------------------------------------------------
# XY 平面の CCW 三角形 → 法線 +Z
{
    my ($nx,$ny,$nz) = face_normal([0,0,0],[1,0,0],[0,1,0]);
    ok( near($nx,0)&&near($ny,0)&&near($nz,1), 'normal: XY CCW -> +Z' );
}
# 頂点順を入れ替えると法線反転 → -Z
{
    my ($nx,$ny,$nz) = face_normal([0,0,0],[0,1,0],[1,0,0]);
    ok( near($nx,0)&&near($ny,0)&&near($nz,-1), 'normal: XY CW -> -Z' );
}

# ---------------------------------------------------------------------------
# [4] バックフェースカリング契約:
#     回転後空間で n_z>0 = カメラ(+Z)向き = front。
#     同じ三角形を「表」向きと「裏」向きに作り、front 判定が反転することを確認。
# ---------------------------------------------------------------------------
{
    my ($nx,$ny,$nz) = face_normal([0,0,0],[1,0,0],[0,1,0]);  # +Z
    ok( $nz > 0, 'cull: front face has n_z>0' );
    my ($mx,$my,$mz) = face_normal([0,0,0],[0,1,0],[1,0,0]);  # -Z
    ok( $mz < 0, 'cull: back face has n_z<0 (would be culled)' );
}

# ---------------------------------------------------------------------------
# [5] normalize3
# ---------------------------------------------------------------------------
{
    my ($x,$y,$z) = normalize3(0,0,5);
    ok( near($x,0)&&near($y,0)&&near($z,1), 'normalize: (0,0,5)->(0,0,1)' );
    my @zero = normalize3(0,0,0);
    is_deeply( \@zero, [0,0,0], 'normalize: zero vector stays zero (no div0)' );
}

# ---------------------------------------------------------------------------
# [6] lambert: [ambient,1] にクランプ
# ---------------------------------------------------------------------------
{
    # n·L = 1(正面): I = 1
    ok( near(lambert(0,0,1, 0,0,1, 0.25), 1.0), 'lambert: face-on -> 1' );
    # n·L = 0(直交): I = ambient
    ok( near(lambert(1,0,0, 0,0,1, 0.25), 0.25), 'lambert: grazing -> ambient' );
    # n·L < 0(裏): ambient で下限クランプ(負にならない)
    ok( near(lambert(0,0,-1, 0,0,1, 0.25), 0.25), 'lambert: back-lit clamped to ambient' );
    # 中間 45°: I = 0.25 + 0.75*cos45
    my $exp = 0.25 + 0.75*(1/sqrt(2));
    ok( near(lambert(1,0,1, 0,0,1, 0.25), $exp, 1e-9), 'lambert: 45deg intermediate' );
}

# ---------------------------------------------------------------------------
# [7] shade_color: base×強度を 8bit 化、alpha 付与
# ---------------------------------------------------------------------------
{
    my $c = shade_color([1,0.5,0], 1.0, 255);
    is_deeply( $c, [255,128,0,255], 'shade: full intensity 8bit + alpha' );
    my $d = shade_color([1,1,1], 0.25, 200);
    is_deeply( $d, [64,64,64,200], 'shade: ambient grey, custom alpha' );
    # クランプ(オーバーフローしない)
    my $e = shade_color([2,2,2], 1.0, 255);
    is_deeply( $e, [255,255,255,255], 'shade: clamps >255' );
}

# ---------------------------------------------------------------------------
# [8] painter_order: depth 昇順(奥→手前)
# ---------------------------------------------------------------------------
{
    my @ord = painter_order([ 3.0, -1.0, 2.0, 0.0 ]);
    is_deeply( \@ord, [1,3,2,0], 'painter: ascending depth order' );
}

# ---------------------------------------------------------------------------
# [9] scanline_spans: 既知三角形の被覆と隙間なし
# ---------------------------------------------------------------------------
{
    # 直角三角形 (0,0)(10,0)(0,10) を step=1 で塗る。
    # y=0..10 の各行にちょうど 1 スパン、xL=0、xR は y につれて縮む(斜辺 x+y=10)。
    my @spans = scanline_spans([0,10,0],[0,0,10], 1);
    ok( @spans >= 10, 'scanline: covers full height (>=10 rows)' );
    my %seen_y;
    my $ok_left = 1; my $ok_right = 1; my $ok_single = 1;
    my %rows;
    push @{$rows{$_->[0]}}, $_ for @spans;
    for my $y (sort { $a <=> $b } keys %rows) {
        my @r = @{$rows{$y}};
        $ok_single = 0 if @r != 1;               # 各行ちょうど 1 スパン
        my ($yy,$xL,$xR) = @{$r[0]};
        $ok_left  = 0 if !near($xL, 0, 1e-6);     # 左辺は x=0
        $ok_right = 0 if $xR > 10 + 1e-6 || $xR < -1e-6;  # 斜辺の内側
        $seen_y{$y} = 1;
    }
    ok( $ok_single, 'scanline: exactly one span per row (no double-count at shared vertex)' );
    ok( $ok_left,   'scanline: left edge pinned to x=0' );
    ok( $ok_right,  'scanline: right edge within hypotenuse' );
    # y が連続(隙間なし): 最小行から最大行まで全整数が存在
    my @ys = sort { $a <=> $b } keys %seen_y;
    my $contiguous = 1;
    for my $k ($ys[0] .. $ys[-1]) { $contiguous = 0 unless $seen_y{$k}; }
    ok( $contiguous, 'scanline: rows are contiguous (no gaps)' );
}

# ---------------------------------------------------------------------------
# [10] scanline_spans: 退化(高さ 0)は空
# ---------------------------------------------------------------------------
{
    my @spans = scanline_spans([0,10,20],[5,5,5], 1);   # 全頂点 y=5
    is( scalar(@spans), 0, 'scanline: degenerate (zero-height) triangle -> empty' );
}

# ---------------------------------------------------------------------------
# [11] scanline_spans: step による間引き(u16 上限対策)
# ---------------------------------------------------------------------------
{
    my @s1 = scanline_spans([0,100,0],[0,0,100], 1);
    my @s5 = scanline_spans([0,100,0],[0,0,100], 5);
    ok( @s5 < @s1, 'scanline: larger step yields fewer spans' );
    ok( @s5 > 0,   'scanline: step decimation still produces fill' );
}

# ---------------------------------------------------------------------------
# [12] scanline_spans ビューポートクリップ: 画面外の行/列を塗らない
# ---------------------------------------------------------------------------
{
    # 三角形 (-50,0)(150,0)(50,200) を 100x100 窓にクリップ。
    # クリップ無しなら y=0..200・x=-50..150 まで塗るが、クリップで y<=99・x in [0,100]。
    my @clip = scanline_spans([-50,150,50],[0,0,200], 1, 100, 100);
    my $ok = 1;
    for my $s (@clip) {
        my ($y,$xL,$xR) = @$s;
        $ok = 0 if $y < 0 || $y > 99;          # 縦クリップ
        $ok = 0 if $xL < 0 || $xR > 100;       # 横クリップ
    }
    ok( @clip > 0 && $ok, 'scanline clip: all spans within [0,W]x[0,H]' );
    my @noclip = scanline_spans([-50,150,50],[0,0,200], 1);
    ok( @noclip > @clip, 'scanline clip: fewer spans than unclipped (offscreen trimmed)' );
}

# ---------------------------------------------------------------------------
# [13] bbox_offscreen: 完全に画面外なら真、一部でも重なれば偽
# ---------------------------------------------------------------------------
{
    ok(  bbox_offscreen([200,260,230],[10,10,60], 100,100), 'bbox: fully right of viewport -> offscreen' );
    ok(  bbox_offscreen([10,60,30],[-90,-90,-40], 100,100), 'bbox: fully above viewport -> offscreen' );
    ok( !bbox_offscreen([-10,50,20],[-10,10,40], 100,100),  'bbox: straddling edge -> on-screen' );
    ok( !bbox_offscreen([40,60,50],[40,40,60], 100,100),    'bbox: fully inside -> on-screen' );
}

# ---------------------------------------------------------------------------
# [14] nearest_index_2d: クリック位置に最も近い頂点(+eligibility)
# ---------------------------------------------------------------------------
{
    my @sx = (0, 10, 100, 100);
    my @sy = (0, 10, 100, 0);
    my ($i,$d) = nearest_index_2d(\@sx, \@sy, 12, 9);      # (10,10) が最近
    is( $i, 1, 'nearest: picks closest projected vertex' );
    ok( $d < 3, 'nearest: distance is small' );
    # eligibility で頂点1を除外 → 次に近い(0,0)が選ばれる
    my ($i2) = nearest_index_2d(\@sx, \@sy, 12, 9, [1,0,1,1]);
    is( $i2, 0, 'nearest: respects eligibility mask (front-facing only)' );
    # 候補ゼロ
    my ($i3,$d3) = nearest_index_2d(\@sx, \@sy, 12, 9, [0,0,0,0]);
    is( $i3, -1, 'nearest: no eligible -> -1' );
}

done_testing();