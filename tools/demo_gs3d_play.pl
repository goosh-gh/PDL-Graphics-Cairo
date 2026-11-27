#!/usr/bin/env perl
# demo_gs3d_play.pl — Driver::GS3D の play(頂点の色の時間変化を窓の中で再生)を、
# 実データ無しで見るデモ。
#
# 半径 80 mm の球(UV 球)に、合成の「源パワー」を潜時 0〜500 ms(1 kHz、1 ms ごと)で
# 載せる。ピークは潜時とともに前(+Y、鼻)から頭頂を通って後ろ(−Y)へ動き、振幅は
# 潜時 250 ms で最大になる。色は灰色から赤・黄へ。play は実時間(speed 1 = 潜時 1 ms を
# 1 ms)で時刻ゼロから流し、最後まで行ったら先頭に戻る。窓の左下に今の潜時が出る。
#
# 使い方:
#   perl tools/demo_gs3d_play.pl                  # 実時間で繰り返し
#   perl tools/demo_gs3d_play.pl --speed 0.1      # 10 分の 1 の速さ
#   perl tools/demo_gs3d_play.pl --once           # 1 回で止める
#   GS3D_STAGE=A perl tools/demo_gs3d_play.pl     # 段階 A(3D_FRAME)で比べる
#
# 操作: スペース = 一時停止/再開。ドラッグ・ホイール・p・r・クリックは今までどおり。
# 色は 1 コマずつコードで作る(500 コマ分を前もって持たない)。
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use PDL;
use PDL::Graphics::Cairo::Driver::GS3D;

my %o = (speed => 1, once => 0, nu => 160, nv => 80);
GetOptions('speed=f' => \$o{speed}, 'once' => \$o{once}, 'nu=i' => \$o{nu}, 'nv=i' => \$o{nv})
    or die "usage: $0 [--speed F] [--once]\n";

# UV 球: 経度 nu × 緯度 nv の格子。頂点 (Nv,3)、面 (Nf,3)
my ($nu, $nv) = @o{qw(nu nv)};
my $lon = (sequence($nu) / $nu * 2 * 3.14159265358979)->dummy(1, $nv);
my $lat = ((sequence($nv) + 0.5) / $nv * 3.14159265358979)->dummy(0, $nu);
my $dir = cat((sin($lat) * cos($lon))->flat, (sin($lat) * sin($lon))->flat, cos($lat)->flat);  # (Nv,3) 単位
my $verts = $dir * 80;
my $i = sequence(long, $nu)->dummy(1, $nv - 1);
my $j = sequence(long, $nv - 1)->dummy(0, $nu);
my $a = ($j * $nu + $i)->flat;
my $b = ($j * $nu + ($i + 1) % $nu)->flat;
my ($c, $d) = ($a + $nu, $b + $nu);
my $faces = cat(cat($a, $c, $b), cat($b, $c, $d))->mv(2, 1)->clump(0, 1);       # (Nf,3)

# 潜時 0..500 ms。ピークの向き: 前(+Y)→ 頭頂(+Z)→ 後ろ(−Y)、振幅は 250 ms で最大
my $times = sequence(501);
my $grey  = pdl(0.55, 0.55, 0.55);
my $colors = sub {
    my ($k, $t) = @_;
    my $ang = 3.14159265358979 * $t / 500;                    # 0 → π
    my $src = pdl(0, cos($ang), sin($ang));                   # 単位ベクトル
    my $amp = sin(3.14159265358979 * $t / 500);               # 0 → 1 → 0
    my $cosd = ($dir * $src->dummy(0))->mv(1, 0)->sumover;   # 点ごとの内積(x,y,z を畳む)
    my $p   = $amp * exp(-(1 - $cosd) / 0.08);                # 0..1
    my $hot = cat(ones($p), $p->clip(0, 1) ** 0.5 * 0.9, zeroes($p));   # 赤 → 黄
    return $grey->dummy(0) * (1 - $p->dummy(1)) + $hot * $p->dummy(1);
};

my $drv = PDL::Graphics::Cairo::Driver::GS3D->new(
    scene  => { mesh => { verts => $verts, faces => $faces } },
    render => 'zbuffer', width => 720, height => 720, zoom => 2,
);
$drv->play(times => $times, colors => $colors, speed => $o{speed}, loop => !$o{once});
printf STDERR "sphere: %d vertices, %d faces; %d frames 0..500 ms, speed %g\n",
    $verts->dim(0), $faces->dim(0), $times->nelem, $o{speed};
$drv->run;
