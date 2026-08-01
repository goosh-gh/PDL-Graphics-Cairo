use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use PDL::Graphics::Cairo::SceneExport qw(scene_to_obj scene_to_usda);

# --- 合成シーン: 三角錐 mesh(4頂点 4面)+ 頂点カラー + 電極2個(ラベル/色付) ---
my $scene = {
    mesh => {
        verts => [ 0,0,0,  10,0,0,  0,10,0,  0,0,10 ],           # 4 verts
        faces => [ 0,1,2,  0,1,3,  0,2,3,  1,2,3 ],              # 4 tri, 0-based
        vcolors => [ 1,0,0,  0,1,0,  0,0,1,  1,1,0 ],            # per-vertex
    },
    points  => [ 5,5,50,   -5,-5,-50 ],                          # 2 electrodes
    pcolors => [ 1,0,0,     0.8,0.8,0.8 ],
    labels  => [ 'Cz', 'Fp1' ],
};

my $obj  = scene_to_obj($scene);
my $usda = scene_to_usda($scene);

# ---- OBJ: mesh 頂点/面を抽出(電極は "o electrodes" 以降なので mesh 部だけ見る) ----
my @obj_lines = split /\n/, $obj;
my (@obj_mesh_v, @obj_mesh_f);
my $in_mesh = 0;
for (@obj_lines) {
    if (/^o cortex\b/)      { $in_mesh = 1; next }
    if (/^o electrodes\b/)  { $in_mesh = 0; next }
    next unless $in_mesh;
    push @obj_mesh_v, $_ if /^v /;
    push @obj_mesh_f, $_ if /^f /;
}
is(scalar @obj_mesh_v, 4, "OBJ mesh: 4 vertices");
is(scalar @obj_mesh_f, 4, "OBJ mesh: 4 faces");
like($obj_mesh_v[0], qr/^v 0\.000000 0\.000000 0\.000000 1\.000000 0\.000000 0\.000000$/,
     "OBJ vertex carries r g b color");

# OBJ 面は 1-based
my @obj_face0 = $obj_mesh_f[0] =~ /^f (\d+) (\d+) (\d+)$/;
is_deeply(\@obj_face0, [1,2,3], "OBJ first face is 1-based (0,1,2 -> 1,2,3)");

# ---- USDA: faceVertexIndices を抽出 ----
my ($usda_idx_str) = $usda =~ /faceVertexIndices = \[([^\]]*)\]/;
ok(defined $usda_idx_str, "USDA has faceVertexIndices");
my @usda_idx = map { s/\s//gr } split /,/, $usda_idx_str;
is(scalar @usda_idx, 12, "USDA: 4 tri * 3 = 12 indices");
is_deeply([@usda_idx[0..2]], [0,1,2], "USDA first face is 0-based");

# ---- 不変条件: OBJ 面値 - 1 == USDA index (mesh 部) ----
my @obj_all_idx;
for my $f (@obj_mesh_f) {
    push @obj_all_idx, ($f =~ /^f (\d+) (\d+) (\d+)$/);
}
my @obj_minus1 = map { $_ - 1 } @obj_all_idx;
is_deeply(\@obj_minus1, \@usda_idx, "invariant: OBJ face - 1 == USDA index (mesh)");

# ---- USDA: 頂点数一致 & 色 & ヘッダ ----
my ($pts_str) = $usda =~ /point3f\[\] points = \[([^\]]*)\]/;
my @pts = $pts_str =~ /\(/g;
is(scalar @pts, 4, "USDA mesh: 4 points (== OBJ mesh vertices)");
like($usda, qr/upAxis = "Z"/,        "USDA header declares upAxis Z (MNI)");
like($usda, qr/metersPerUnit = 0\.001/, "USDA header declares mm via metersPerUnit");
like($usda, qr/primvars:displayColor = \[.*\] \(interpolation = "vertex"\)/,
     "USDA mesh has per-vertex displayColor (metadata AFTER value)");
like($usda, qr/uniform token subdivisionScheme = "none"/,
     "USDA mesh sets subdivisionScheme none (no auto Catmull-Clark)");
like($usda, qr/float3\[\] extent = \[\(/, "USDA mesh has extent (bbox)");
# 回帰ガード: メタデータを '=' の前に置く USD 文法違反が無いこと(旧バグ)。
unlike($usda, qr/displayColor\s*\(interpolation/, "no attribute metadata before '=' (Sdf-valid)");

# ---- 電極: ラベルが両フォーマットに出る ----
like($obj,  qr/\bg Cz\b/,   "OBJ electrode group named Cz");
like($obj,  qr/\bg Fp1\b/,  "OBJ electrode group named Fp1");
like($usda, qr/def Mesh "Cz"/,  "USDA electrode disc named Cz");
like($usda, qr/def Mesh "Fp1"/, "USDA electrode disc named Fp1");
like($usda, qr/def Xform "electrodes"/, "USDA electrodes group present");
# 電極 disc: 各電極 4*nseg 三角(既定 nseg=20 → 80 tri)。頂点は三角スープで 3/tri。
my $obj_e_v = () = $obj =~ /^v /mg;   # mesh(4) + 電極2枚 disc
is($obj_e_v, 4 + 2 * (4*20*3), "OBJ verts = 4 mesh + 2 discs (nseg=20)");

# ---- mesh 単色(vcolors 無し)分岐 ----
my $scene2 = { mesh => { verts=>[0,0,0,1,0,0,0,1,0], faces=>[0,1,2], color=>[0.85,0.78,0.70] } };
my $usda2 = scene_to_usda($scene2);
like($usda2, qr/primvars:displayColor = \[.*\] \(interpolation = "constant"\)/,
     "mesh with base color -> constant displayColor (metadata after value)");
my $obj2 = scene_to_obj($scene2);
like($obj2, qr/^v 0\.000000 0\.000000 0\.000000$/m, "no vcolors -> plain xyz vertex");

# ---- 電極のみ(mesh 無し)でも落ちない ----
my $scene3 = { points=>[0,0,0], labels=>['T7'] };
ok( scene_to_obj($scene3)  =~ /g T7/,        "electrode-only OBJ ok");
ok( scene_to_usda($scene3) =~ /def Mesh "T7"/, "electrode-only USDA ok");

# ---- bare_header(NYHead 素ヘッダ)に戻せる ----
my $usda_bare = scene_to_usda($scene, bare_header=>1);
unlike($usda_bare, qr/upAxis/, "bare_header omits upAxis (NYHead-compatible header)");

done_testing();
