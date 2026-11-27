use strict;
use warnings;
use Test::More;
use Test::PDL qw(is_pdl);
use PDL;
use PDL::Graphics::Cairo::Driver::GS3D;

# ==================================================================
# Driver::GS3D の zbuffer の三角形(_mesh_tris / _pack_tris_pdl)を PDL のまま組み立てる形に
# した後の確認。期待値は実装から写さず、小さなメッシュについて手で決める:
#   回転は恒等、正射影、zoom 1、100x100 の窓(cx = cy = 50)なので
#   sx = 50 - x、sy = y + 50、深度 = z。
#   winding は 'ccw'(符号 +1)。回転後の xy で反時計回りの面が表。
#   ambient 1 なので頂点色は vcolors * 255(値は (k + 0.5)/255 にして byte で k になるように)。
# 面:
#   T0  表・画面内        v0 (0,0,5)   v1 (10,0,5)  v2 (0,10,5)
#   T1  裏               v3 (20,20,-5) v4 (20,30,-5) v5 (30,20,-5)
#   T2  表・画面の外      v6 (70,0,0)  v7 (80,0,0)  v8 (70,10,0)    sx = -20, -30, -20
#   T3  表・一部だけ画面内 v9 (45,0,1)  v10 (60,0,1) v11 (45,10,1)   sx = 5, -10, 5
# 残るのは T0 と T3(この順)。
# ==================================================================

my $G = 'PDL::Graphics::Cairo::Driver::GS3D';

my @V = ([0,0,5], [10,0,5], [0,10,5],
         [20,20,-5], [20,30,-5], [30,20,-5],
         [70,0,0], [80,0,0], [70,10,0],
         [45,0,1], [60,0,1], [45,10,1]);
my @RGB = map { [ $_ * 10, $_ * 20, 255 - $_ * 7 ] } 0 .. 11;   # 頂点 i の色(0..255)

sub driver {
    my (%o) = @_;
    my $verts = pdl(\@V)->transpose;                               # (12,3)
    my $faces = pdl(long, [[0,1,2],[3,4,5],[6,7,8],[9,10,11]])->transpose;   # (4,3)
    $faces = $faces + 1 if $o{onebased};
    my $vcol  = ((pdl(\@RGB) + 0.5) / 255)->transpose;             # (12,3)
    return $G->new(scene => { mesh => { verts => $verts, faces => $faces, vcolors => $vcol,
                                        ambient => 1, winding => 'ccw' } },
                   width => 100, height => 100, render => 'zbuffer', perspective => 0, zoom => 1);
}

sub corner { my ($i) = @_; pack('f<f<f<CCC', 50 - $V[$i][0], $V[$i][1] + 50, $V[$i][2], @{ $RGB[$i] }) }

my $want = pack('S', 2) . join('', map { corner($_) } 0, 1, 2, 9, 10, 11);

# ---- 表・裏・画面外の選び分けとバイト列 ----
{
    my $d = driver();
    my $t = $d->_mesh_tris(identity(3));
    is($t->{n}, 2, 'two triangles kept (T0, T3)');
    my $got = $G->can('_pack_tris_pdl')->($t->{xyz}, $t->{rgb});
    is(length $got, 2 + 2 * 45, '45 bytes per triangle after the u16 count');
    ok($got eq $want, 'bytes match the hand-built frame');
    is_pdl($d->{_mesh_proj}{vis}, byte([1,1,1, 0,0,0, 0,0,0, 1,1,1]),
           'visible vertices: those of the kept faces');
}

# ---- 面の番号が 1 始まりでも同じ ----
{
    my $d = driver(onebased => 1);
    my $t = $d->_mesh_tris(identity(3));
    ok($G->can('_pack_tris_pdl')->($t->{xyz}, $t->{rgb}) eq $want, '1-based faces: same bytes');
}

# ---- 表裏の入れ替わりと、残る面が無い場合 ----
{
    my $d = driver();
    my $t = $d->_mesh_tris(pdl([[-1,0,0],[0,1,0],[0,0,1]]));      # x を反転: 表裏が入れ替わる
    is($t->{n}, 1, 'x mirrored: only T1 is front and on screen');
    # y 軸のまわりに 90 度: どの面も 3 頂点の z が同じなので真横から見え、面法線の z が 0
    my $t0 = driver()->_mesh_tris(pdl([[0,0,1],[0,1,0],[-1,0,0]]));
    is($t0->{n}, 0, 'every face edge-on: none kept');
}

# ---- hover / pick: 可視頂点だけから最も近いもの、同じ距離なら番号の小さい方 ----
{
    my $d = driver();
    $d->_mesh_tris(identity(3));
    my $near = $G->can('_nearest_visible');
    # (30,70) は v3(裏の面だけの頂点)の真上。可視の v1 (40,50) と v2 (50,60) はどちらも距離 sqrt(500)
    my ($i, $dist) = $near->($d->{_mesh_proj}, 30, 70);
    is($i, 1, 'hidden vertex skipped; tie goes to the lower index');
    ok(abs($dist - sqrt(500)) < 1e-9, 'distance');
    ($i) = $near->($d->{_mesh_proj}, 4, 59);
    is($i, 11, 'nearest visible vertex (v11 at 5,60)');
    my ($none, $nd) = $near->({ sx => pdl(1, 2), sy => pdl(1, 2), vis => byte(0, 0) }, 0, 0);
    is($none, -1, 'no visible vertex: -1');
    ok(!defined $nd, 'no visible vertex: distance undef');
}

# ---- line モードも同じ形(piddle)で pick 用の投影を残す ----
{
    my $d = driver();
    $d->_mesh_lines(identity(3));
    is_pdl($d->{_mesh_proj}{vis}, byte([1,1,1, 0,0,0, 0,0,0, 1,1,1]), 'line mode: same visible vertices');
    my ($i) = $G->can('_nearest_visible')->($d->{_mesh_proj}, 30, 70);
    is($i, 1, 'line mode: same pick');
}

# ---- 65535 を超えたとき: 深度が同じなら番号の小さい方を残す ----
{
    my $n   = 65537;
    my $xyz = zeroes(double, 3, 3, $n);
    $xyz->slice('(0),(0),:') .= sequence($n);                      # 三角形の番号を最初の頂点の x に
    my $rgb = zeroes(byte, 3, 3, $n);
    my @w;
    local $SIG{__WARN__} = sub { push @w, @_ };
    my $bytes = $G->can('_pack_tris_pdl')->($xyz, $rgb);
    my ($cnt) = unpack 'S', $bytes;
    is($cnt, 65535, 'equal depths: 65535 kept');
    my $first_x = unpack('f<', substr($bytes, 2 + 65534 * 45, 4));
    is($first_x, 65534, 'equal depths: the lowest indices kept, in order');
}

done_testing;
