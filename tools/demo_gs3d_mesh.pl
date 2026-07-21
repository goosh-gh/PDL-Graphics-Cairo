#!/usr/bin/env perl
# demo_gs3d_mesh.pl — GS3D の面(mesh)描画を giza-server で「グリグリ」確認する。
#
# 実データ(NY Head /sa/head)が無くても動くよう、合成の icosphere(閉じた凸メッシュ)を
# 頭皮に見立てて Lambert 陰影で塗り、その上に 10-20 電極を点+ラベルで重畳する。
# 凸メッシュなので画家のアルゴリズムで綺麗に出る(凹の皮質は自己遮蔽が崩れる—
# それは overlay_scalp_obj.pl → Blender の担当。ここは向き確認用途)。
#
# 実データを使う場合は --surf 経由で overlay_scalp_obj.pl のローダ(HDF5 軸転置・
# 1/0-based 自動判定)を流用し、$scene->{mesh}{verts}/{faces} に差し替えればよい。
#
# 使い方:
#   perl tools/demo_gs3d_mesh.pl                 # subdiv=2(320面)+電極、osx/xlib 自動
#   perl tools/demo_gs3d_mesh.pl --subdiv 3      # よりなめらか(1280面)
#   perl tools/demo_gs3d_mesh.pl --no-electrodes # メッシュのみ
#   perl tools/demo_gs3d_mesh.pl --wire          # 面を薄くしてワイヤ寄りに(fill_step 大)
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use PDL;
use PDL::Graphics::Cairo::Driver::GS3D;

my %opt = (subdiv => 2, electrodes => 1, radius => 90, wire => 0);
for (my $i=0; $i<@ARGV; $i++) {
    $opt{subdiv}     = $ARGV[$i+1]//2 if $ARGV[$i] eq '--subdiv';
    $opt{radius}     = $ARGV[$i+1]//90 if $ARGV[$i] eq '--radius';
    $opt{electrodes} = 0 if $ARGV[$i] eq '--no-electrodes';
    $opt{wire}       = 1 if $ARGV[$i] eq '--wire';
}

# ---------------------------------------------------------------------------
# icosphere 生成(純 Perl)。正二十面体 → 三角分割 --subdiv 回 → 単位球へ正規化。
# 返り値: (\@verts [ [x,y,z], ... ], \@faces [ [i0,i1,i2], ... ])  0-based, CCW 外向き。
# ---------------------------------------------------------------------------
sub icosphere {
    my ($subdiv, $r) = @_;
    my $t = (1 + sqrt(5)) / 2;
    my @v = (
        [-1, $t, 0],[1, $t, 0],[-1,-$t, 0],[1,-$t, 0],
        [0,-1, $t],[0, 1, $t],[0,-1,-$t],[0, 1,-$t],
        [$t, 0,-1],[$t, 0, 1],[-$t, 0,-1],[-$t, 0, 1],
    );
    my @f = (
        [0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],
        [1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],
        [3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],
        [4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1],
    );
    # 三角分割(中点キャッシュで頂点を共有)
    for (1 .. $subdiv) {
        my %mid; my @nf;
        my $midpoint = sub {
            my ($a,$b) = @_;
            my $key = $a < $b ? "$a-$b" : "$b-$a";
            return $mid{$key} if exists $mid{$key};
            my $m = [ ($v[$a][0]+$v[$b][0])/2, ($v[$a][1]+$v[$b][1])/2, ($v[$a][2]+$v[$b][2])/2 ];
            push @v, $m; my $idx = $#v; $mid{$key} = $idx; return $idx;
        };
        for my $tri (@f) {
            my ($a,$b,$c) = @$tri;
            my $ab = $midpoint->($a,$b);
            my $bc = $midpoint->($b,$c);
            my $ca = $midpoint->($c,$a);
            push @nf, [$a,$ab,$ca],[$b,$bc,$ab],[$c,$ca,$bc],[$ab,$bc,$ca];
        }
        @f = @nf;
    }
    # 単位球面へ射影 → 半径 r
    for my $p (@v) {
        my $n = sqrt($p->[0]**2 + $p->[1]**2 + $p->[2]**2) || 1;
        $_ *= $r/$n for @$p;
    }
    return (\@v, \@f);
}

my ($verts, $faces) = icosphere($opt{subdiv}, $opt{radius});
printf STDERR "icosphere: %d verts, %d faces (subdiv=%d, r=%d)\n",
    scalar(@$verts), scalar(@$faces), $opt{subdiv}, $opt{radius};

# PDL [Nv,3] / [Nf,3] へ。pdl([[列0...],[列1...],[列2...]]) で (N,3) になる規約に合わせ、
# 「成分ごとに N 個」の並びで作る(demo_gs3d_electrodes.pl と同じ)。
my $vc = pdl([
    [ map { $_->[0] } @$verts ],
    [ map { $_->[1] } @$verts ],
    [ map { $_->[2] } @$verts ],
]);
my $tri = pdl([
    [ map { $_->[0] } @$faces ],
    [ map { $_->[1] } @$faces ],
    [ map { $_->[2] } @$faces ],
])->long;

my $mesh = {
    verts   => $vc,
    faces   => $tri,                 # 0-based(自動判定でそのまま)
    color   => [0.86, 0.80, 0.72],   # 頭皮っぽい暖色
    light   => [0.3, 0.45, 1.0],
    ambient => 0.28,
    winding => 'auto',
    fill_step => $opt{wire} ? 4 : 1, # --wire は間引いて縞状=ワイヤ寄りの見え方
};

my $scene = { mesh => $mesh };

# ---- 電極重畳(点+ラベル)。理想 10-20 を半径 r 弱の球面近傍に置く ----
if ($opt{electrodes}) {
    my @E = (
        [Fp1=>-27,83,-3],[Fp2=>27,83,-3],[F7=>-71,51,-3],[F3=>-48,59,44],
        [Fz=>0,63,61],[F4=>48,59,44],[F8=>71,51,-3],[T3=>-85,-1,-4],
        [C3=>-63,-3,61],[Cz=>0,0,95],[C4=>63,-3,61],[T4=>85,-1,-4],
        [T5=>-72,-47,-4],[P3=>-49,-63,45],[Pz=>0,-70,62],[P4=>49,-63,45],
        [T6=>72,-47,-4],[O1=>-27,-84,-3],[O2=>27,-84,-3],
    );
    my (@lab,@X,@Y,@Z);
    for my $e (@E) {
        my ($name,$x,$y,$z) = @$e;
        # 電極を球面のわずか外側へ載せる(点がメッシュに埋もれないように 1.02 倍)
        my $n = sqrt($x*$x+$y*$y+$z*$z) || 1;
        my $s = $opt{radius} * 1.02 / $n;
        push @lab, $name; push @X, $x*$s; push @Y, $y*$s; push @Z, $z*$s;
    }
    my $n = scalar @lab;
    $scene->{points} = pdl([ \@X, \@Y, \@Z ]);           # [N,3]
    $scene->{colors} = pdl([ [(1.0)x$n], [(0.35)x$n], [(0.2)x$n] ]);  # 赤橙の点
    $scene->{labels} = \@lab;
}

my $drv = PDL::Graphics::Cairo::Driver::GS3D->new(
    scene  => $scene,
    width  => 720,
    height => 720,
);
$drv->run;
