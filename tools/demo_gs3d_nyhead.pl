#!/usr/bin/env perl
# demo_gs3d_nyhead.pl — 実 New York Head サーフェスを GS3D で面表示(グリグリ)。
#
# sa_nyhead.mat(MATLAB v7.3 = HDF5)の <surf>/vc + <surf>/tri を読み、
# $scene->{mesh}{verts}/{faces} に差し込むだけ。ローダ(_as_Nx3 / _face_base /
# load_surface)は PDL-EEG の examples/overlay_scalp_obj.pl から流用(HDF5 軸転置
# {3,N}→(N,3)、tri の 1/0-based 自動判定)。PDL::EEG 本体は触らない。
#
# 面パイプライン(投影→カリング→画家ソート→Lambert→スキャンライン線分化)は
# giza-server 無改変。凸の /sa/head(≈1082頂点)は綺麗。凹の /sa/cortex75K は
# (a)自己遮蔽が画家法で崩れる (b)面数が u16 塗り予算を超え縞状に間引かれる ——
# つまり「Option 1(この方式)がどこまで実用か」を実データで体感するためのデモ。
#
# 使い方:
#   perl tools/demo_gs3d_nyhead.pl                          # /sa/head + 内蔵19電極+ラベル
#   perl tools/demo_gs3d_nyhead.pl --no-electrodes          # メッシュのみ
#   perl tools/demo_gs3d_nyhead.pl --surf /sa/cortex2K --no-electrodes    # 皮質(軽い・連続メッシュ)
#   perl tools/demo_gs3d_nyhead.pl --surf /sa/cortex5K --no-electrodes    # やや細かい皮質
#   perl tools/demo_gs3d_nyhead.pl --surf /sa/cortex75K --no-electrodes   # 皮質フル(重い/縞出る=速度確認)
#   perl tools/demo_gs3d_nyhead.pl --elc ~/src/NYHead/standard_1020.elc    # 実 .elc で正確配置(推奨)
#   perl tools/demo_gs3d_nyhead.pl --elc ~/src/NYHead/standard_1020.elc --snap   # 頭皮にスナップ表示
#   PDLCAIRO_DEBUG=1 perl tools/demo_gs3d_nyhead.pl --surf /sa/cortex75K   # front面数/塗り本数を表示
#
# 操作: ドラッグ=回転、面クリック=シード追加(色分け+HO area 名ラベル)、
#       'u'=直前シード取消、'c'=全消去、'r'=視点リセット。マウスを面上に載せると
#       左上に x,y,z + HO area 名をライブ表示(クリック前の確認)。--ho-labels <file>
#       で area 名供給(1行1名, HO_labels{1} が先頭行)。無ければ HO index を表示。
#
# 依存: PDL::IO::HDF5(サーフェス読み込み)。--elc 使用時のみ PDL::EEG::IO::ASA。
use strict;
use warnings;
use FindBin;
use File::Basename qw(dirname);
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use PDL;
use PDL::Graphics::Cairo::Driver::GS3D;

my %o = (
    mat        => "$ENV{HOME}/src/NYHead/sa_nyhead.mat",
    surf       => '/sa/head',
    elc        => undef,
    electrodes => 1,            # 内蔵 19 電極+ラベルを既定で重畳(--no-electrodes で off)
    forward    => 0,            # pick→forward projection: sa 231ch モデル電極を V_fem_normal で着色
    ho_labels  => undef,        # Harvard-Oxford area 名の表(1行1名, index 0 始まり)
    max_faces  => 0,            # >0 なら面を間引いて負荷を段階的に測る(cortex 速度確認用)
    snap       => 0,            # 電極を最近傍頭皮頂点へスナップ+法線方向に持ち上げ(表示用)
    proud      => 3,            # スナップ時に外向きへ持ち上げる量(mm)。埋もれ防止
    zoom       => 1.0,
    fill_step  => 1,
    wire       => 0,
    width      => 720,
    height     => 720,
    source_power => undef,   # --source-power FILE: 皮質を源パワーで着色(nyhead_inverse.pl --out)
    cmap       => q{inferno}, # --cmap inferno|viridis|hot
    power_clip => 100,        # --power-clip P: 正規化上限の百分位(既定100=単純max)
    power_gamma=> 1.0,        # --power-gamma g: t**g で低値を持ち上げ
    render     => undef,      # --render line|zbuffer(源パワーONなら既定 zbuffer=滑らか)
    overlay    => 1,          # 源パワー時: 灰色解剖皮質ベース+閾値以上だけカラーを重ねる。--no-overlay で従来の cmap 直塗り
    threshold  => 0.25,       # --threshold t: 正規化値 t<閾値 は灰(未活動=解剖色)、以上でカラー
    base_grey  => 0.55,       # --base-grey g: 灰ベースの albedo(0..1; Lambert 陰影が別途乗る)
    colorbar   => 1,          # 源パワー時: 画面右にカラーバー HUD(cmap/オーバレイと一致)。--no-colorbar で消す
);
GetOptions(
    'mat=s'       => \$o{mat},
    'surf=s'      => \$o{surf},
    'elc|elec=s'  => \$o{elc},   # --elec は電極ファイル指定の別名(--electrodes への誤略語化を防ぐ)
    'electrodes!' => \$o{electrodes},   # --electrodes / --no-electrodes
    'forward!'    => \$o{forward},      # pick→頭皮 forward projection をライブ表示
    'ho-labels=s' => \$o{ho_labels},    # Harvard-Oxford area 名テーブル(1行1名)
    'max-faces=i' => \$o{max_faces},
    'snap!'       => \$o{snap},
    'proud=f'     => \$o{proud},
    'zoom=f'      => \$o{zoom},
    'fill-step=f' => \$o{fill_step},
    'source-power=s' => \$o{source_power},
    'cmap=s'         => \$o{cmap},
    'power-clip=f'   => \$o{power_clip},
    'power-gamma=f'  => \$o{power_gamma},
    'render=s'       => \$o{render},
    'wire'        => \$o{wire},
    'overlay!'    => \$o{overlay},       # --overlay / --no-overlay(灰皮質+閾値オーバレイ)
    'threshold=f' => \$o{threshold},
    'base-grey=f' => \$o{base_grey},
    'colorbar!'   => \$o{colorbar},      # --colorbar / --no-colorbar(画面右のカラーバー HUD)
    'width=i'     => \$o{width},
    'height=i'    => \$o{height},
) or die "bad args\n";
-f $o{mat} or die "not found: $o{mat}\n  (--mat で場所を指定)\n";

# --ho-labels 未指定なら既定を探す: 環境変数 NYHEAD_HO_LABELS → .mat と同じ場所。
# 正式な配布元は PDL-EEG/share/nyhead/HO_labels.txt(そこを symlink するか env で指す)。
unless (defined $o{ho_labels}) {
    for my $cand (grep { defined } $ENV{NYHEAD_HO_LABELS}, dirname($o{mat}).'/HO_labels.txt') {
        if (-f $cand) { $o{ho_labels} = $cand; last; }
    }
}

# ============================================================================
# ↓↓↓ ローダ流用: PDL-EEG examples/overlay_scalp_obj.pl より(HDF5 軸転置・
#     1/0-based 自動判定)。@V=[[x,y,z],..](mm)、@F=[[i,j,k],..](1-based に正規化)。
# ============================================================================
sub _as_Nx3 {
    my ( $p, $name ) = @_;
    my @d = $p->dims;
    die "$name: expected 2-D, got ${\ scalar @d}-D (@d)\n" unless @d == 2;
    return $p if $d[1] == 3;
    if ( $d[0] == 3 ) { warn "$name stored as (3,N); transposing\n"; return $p->transpose->copy; }
    die "$name: no axis of length 3 in (@d)\n";
}
sub _face_base {
    my ( $tri, $nv ) = @_;
    my ( $min, $max ) = ( $tri->min, $tri->max );
    if ( $min < 0.5 ) {
        die sprintf "tri max %d out of range for %d verts (0-based)\n", $max, $nv
            if $max > $nv - 1 + 0.5;
        return 0;
    }
    die sprintf "tri max %d out of range for %d verts (1-based)\n", $max, $nv
        if $max > $nv + 0.5;
    return 1;
}
sub load_surface {
    my ( $file, $path ) = @_;
    $path =~ s{/$}{};
    require PDL::IO::HDF5; PDL::IO::HDF5->import;
    my $h = PDL::IO::HDF5->new($file);
    my ( $vc, $tri );
    eval {
        $vc  = _as_Nx3( $h->dataset("$path/vc")->get,  "$path/vc"  );
        $tri = _as_Nx3( $h->dataset("$path/tri")->get, "$path/tri" );
        1;
    } or die
        "could not read $path/vc + $path/tri ($@)"
      . "  -> is '$path' a surface (has vc/tri)?\n"
      . "     list candidates with:  h5ls -r $file | grep -iE 'vc|tri'\n";
    my $nv = $vc->dim(0);
    my $nf = $tri->dim(0);
    printf STDERR "surface %s: %d vertices, %d faces\n", $path, $nv, $nf;
    my @x = $vc->slice(':,(0)')->list;
    my @y = $vc->slice(':,(1)')->list;
    my @z = $vc->slice(':,(2)')->list;
    my @V = map { [ $x[$_], $y[$_], $z[$_] ] } 0 .. $#x;
    my $add = _face_base( $tri, $nv ) ? 0 : 1;
    my @a = $tri->slice(':,(0)')->list;
    my @b = $tri->slice(':,(1)')->list;
    my @c = $tri->slice(':,(2)')->list;
    my @F = map { [ int($a[$_]+0.5)+$add, int($b[$_]+0.5)+$add, int($c[$_]+0.5)+$add ] } 0 .. $#a;
    return ( \@V, \@F );
}
# ↑↑↑ ここまで流用 ============================================================

# ---- 低解像 cortex ローダ(cortex1K/2K/5K/10K)----
# これらは vc を持たず tri のみ。頂点は 75K の部分集合を in_from_cortex75K で間接参照する
# (標準 NY Head sa 構造)。h5ls 実測: 例) cortex2K = tri{3,4000}(=4000面, 2K ローカル 1-based)
# + in_from_cortex75K{1,2004}(=2004頂点の 75K インデックス)+ vc は 75K 側。
#   verts2K = vc75K[ in_from_cortex75K ]      # 頂点を 75K から引く
#   faces   = cortex2K.tri                     # ローカル 1..2004(1-based)
# --max-faces と違い「連続した本物の低解像メッシュ」なので砂嵐にならず滑らかな脳形になる。
our @LOCAL_TO_75K;   # cortex 低解像: ローカル頂点 index → 75K 頂点 index(0-based)。pick→leadfield 用

sub load_cortex_lowres {
    my ( $file, $path ) = @_;
    $path =~ s{/$}{};
    require PDL::IO::HDF5; PDL::IO::HDF5->import;
    my $h = PDL::IO::HDF5->new($file);

    # 75K 頂点実体
    my $vc75 = _as_Nx3( $h->dataset('/sa/cortex75K/vc')->get, '/sa/cortex75K/vc' );  # [74382,3]
    my @x75 = $vc75->slice(':,(0)')->list;
    my @y75 = $vc75->slice(':,(1)')->list;
    my @z75 = $vc75->slice(':,(2)')->list;
    my $nv75 = scalar @x75;

    # in_from_cortex75K: 各ローカル頂点 → 75K インデックス(1-based=MATLAB 由来)
    my $inf = $h->dataset("$path/in_from_cortex75K")->get->flat;   # 形状(2004,1)/(1,2004)どちらでも
    my @IF  = $inf->list;
    my $ibase = ( $inf->min >= 0.5 ) ? 1 : 0;                      # 1-based 前提だが防御
    @LOCAL_TO_75K = ();
    my @V = map {
        my $j = int($_ + 0.5) - $ibase;
        die sprintf("in_from index %d out of range for 75K (%d verts)\n", $j, $nv75)
            if $j < 0 || $j >= $nv75;
        push @LOCAL_TO_75K, $j;                                    # pick→75K→leadfield 用に保持
        [ $x75[$j], $y75[$j], $z75[$j] ]
    } @IF;
    my $nv = scalar @V;

    # tri: ローカル番号(1..nv)。base 自動判定(75K を直接指していれば nv 超で die → 想定違いを検知)
    my $tri = _as_Nx3( $h->dataset("$path/tri")->get, "$path/tri" );  # [Nf,3]
    my $add = _face_base( $tri, $nv ) ? 0 : 1;
    my @a = $tri->slice(':,(0)')->list;
    my @b = $tri->slice(':,(1)')->list;
    my @c = $tri->slice(':,(2)')->list;
    my @F = map { [ int($a[$_]+0.5)+$add, int($b[$_]+0.5)+$add, int($c[$_]+0.5)+$add ] } 0 .. $#a;

    printf STDERR "cortex %s: %d verts (via in_from_cortex75K), %d faces\n", $path, $nv, scalar(@F);
    return ( \@V, \@F );
}

my ($V, $F);
if ($o{surf} =~ m{cortex(?:1|2|5|10)K/?$}) {
    ($V, $F) = load_cortex_lowres($o{mat}, $o{surf});   # vc 無し・in_from で 75K から頂点解決
} else {
    ($V, $F) = load_surface($o{mat}, $o{surf});         # /sa/head, /sa/cortex75K は vc+tri 直読み
}
my $is_cortex = $o{surf} =~ /cortex/;

# --max-faces N: 面を等間隔に間引いて負荷を段階的に測る(cortex がどこで重くなるか確認用)。
# メッシュに穴が空くので品質評価には使えないが、「面数 vs fps/線分本数」の当たりが掴める。
if ($o{max_faces} > 0 && @$F > $o{max_faces}) {
    my $k = @$F / $o{max_faces};                 # 間引き係数
    my @keep; my $acc = 0;
    for my $i (0 .. $#$F) { if (int($i/$k) != int(($i-1)/$k)) { push @keep, $F->[$i]; } }
    printf STDERR "max-faces: %d -> %d faces (decimated for speed probe)\n", scalar(@$F), scalar(@keep);
    $F = \@keep;
}

# @V / @F(1-based)を GS3D の mesh 契約へ。verts [Nv,3] / faces [Nf,3]。
# 「成分ごとに N 個」で並べると pdl([...]) が (N,3) になる(demo_gs3d_mesh.pl と同規約)。
my $verts = pdl([
    [ map { $_->[0] } @$V ],
    [ map { $_->[1] } @$V ],
    [ map { $_->[2] } @$V ],
]);
my $faces = pdl([
    [ map { $_->[0] } @$F ],
    [ map { $_->[1] } @$F ],
    [ map { $_->[2] } @$F ],
])->long;    # 1-based。_mesh_lines の base 自動判定がそのまま処理する

my $scene = {
    mesh => {
        verts   => $verts,
        faces   => $faces,
        color   => $is_cortex ? [0.82, 0.78, 0.80] : [0.86, 0.78, 0.70],  # 皮質は淡灰桃 / 頭皮は暖色
        light   => [0.3, 0.45, 1.0],     # view 空間: 前上右から
        ambient => 0.28,
        winding => 'auto',               # NY Head の tri 向きに依存しない(重心外向き多数決)
        fill_step => $o{wire} ? 4 : $o{fill_step},
    },
};

# ---- 源パワー・オーバレイ(--source-power) ----------------------------------
# eLORETA/sLORETA の標準化源パワーで皮質頂点を着色する。nyhead_inverse.pl --out
# が書く「1 行 1 値(cortex75K 頂点順, 74382 行)」を読み、mesh->{vcolors} [Nv,3]
# を差し込むだけ。giza-server / Driver::GS3D は無改変(Gouraud が vcolors を
# albedo に使い、Lambert 陰影が別途乗るので立体感は保たれる)。
#   cortex75K : 頂点 index = 75K index(恒等)
#   cortexNK  : 頂点 → 75K は @LOCAL_TO_75K(ローダが @V と同順で構築)
#   /sa/head  : 源は皮質に乗るので無効(警告して無視)
sub _cmap_rgb {
    my ($t, $name) = @_;
    $t = 0 if $t < 0; $t = 1 if $t > 1;
    my %STOPS = (
        inferno => [[0.0,0.001,0.000,0.014],[0.25,0.258,0.039,0.406],
                    [0.5,0.578,0.148,0.404],[0.75,0.865,0.317,0.226],
                    [0.9,0.988,0.645,0.140],[1.0,0.988,0.998,0.645]],
        viridis => [[0.0,0.267,0.005,0.329],[0.25,0.229,0.322,0.545],
                    [0.5,0.128,0.567,0.551],[0.75,0.369,0.789,0.383],
                    [1.0,0.993,0.906,0.144]],
        hot     => [[0.0,0,0,0],[0.375,1,0,0],[0.75,1,1,0],[1.0,1,1,1]],
    );
    my $s = $STOPS{$name} || $STOPS{inferno};
    for my $i (0 .. $#$s-1) {
        my ($t0,@c0) = @{$s->[$i]}; my ($t1,@c1) = @{$s->[$i+1]};
        if ($t <= $t1 || $i == $#$s-1) {
            my $f = ($t1 > $t0) ? ($t-$t0)/($t1-$t0) : 0; $f=0 if $f<0; $f=1 if $f>1;
            return [ $c0[0]+($c1[0]-$c0[0])*$f, $c0[1]+($c1[1]-$c0[1])*$f, $c0[2]+($c1[2]-$c0[2])*$f ];
        }
    }
    return [1,1,1];
}

# 灰色解剖皮質ベース + 閾値カラーオーバレイ。$grey が undef(=--no-overlay)なら cmap 直塗り。
#   vcolor = grey*(1-a) + cmap(t)*a ,  a = smoothstep((t-thr)/(1-thr)) , t<=thr で a=0
# これで未活動皮質は解剖の灰色に沈み、閾値以上の源だけが色で浮く(inferno の黒つぶれ解消)。
sub _overlay_rgb {
    my ($t, $cmap, $grey, $thr) = @_;
    my $rgb = _cmap_rgb($t, $cmap);
    return $rgb unless defined $grey;                    # オーバレイOFF=従来どおり
    my $a = ($thr < 1) ? ($t - $thr) / (1 - $thr) : 0;
    $a = 0 if $a < 0; $a = 1 if $a > 1;
    $a = $a * $a * (3 - 2 * $a);                          # smoothstep(自然な立ち上がり)
    return [ map { $grey * (1 - $a) + $rgb->[$_] * $a } 0 .. 2 ];
}

# 源パワー配列(75K 順)+ 頂点→75K index → vcolors [Nv,3]。純関数(テスト可能)。
sub source_vcolors {
    my ($pw, $g_of_vertex, $cmap, $clip, $gamma, $grey, $thr) = @_;   # $pw=arrayref(75K順), $g_of_vertex=arrayref(頂点→75K)
    my @vals = map { ($_ >= 0 && $_ <= $#$pw) ? $pw->[$_] : 0 } @$g_of_vertex;
    my $hi;
    if ($clip < 100) {
        my @s = sort { $a <=> $b } @vals;
        my $k = int($#s * $clip/100 + 0.5); $k = $#s if $k > $#s; $k = 0 if $k < 0;
        $hi = $s[$k];
    } else { $hi = 0; for (@vals) { $hi = $_ if $_ > $hi } }
    $hi ||= 1;
    my (@R,@G,@B,@T);
    for my $v (@vals) {
        my $t = $v/$hi; $t = $t ** $gamma if $gamma != 1;
        $t = 0 if $t < 0; $t = 1 if $t > 1;
        push @T, $t;
        my $rgb = _overlay_rgb($t, $cmap, $grey, $thr);
        push @R,$rgb->[0]; push @G,$rgb->[1]; push @B,$rgb->[2];
    }
    return (pdl([ \@R, \@G, \@B ]), $hi, \@T);   # [Nv,3] albedo 0..1 + per-vertex t
}

$o{render} //= (defined $o{source_power} ? q{zbuffer} : q{line});  # 源パワー時は Gouraud 既定
if (defined $o{source_power}) {
    -f $o{source_power} or die "not found: $o{source_power}\n";
    if (!$is_cortex) {
        warn "source-power: skipped (surface '$o{surf}' is not cortex)\n";
    } else {
        open my $sph, '<', $o{source_power} or die "open $o{source_power}: $!\n";
        my @pw; while (<$sph>) { next if /^\s*(#|$)/; my ($v) = split; push @pw, $v + 0; }
        close $sph;
        my $nv = scalar @$V;
        if (scalar(@$F) > 60000) {
            warn sprintf("source-power: '%s' has %d faces — exceeds the u16 (65535) tri/line ".
                "limit of the GS3D frame protocol, so the mesh will be truncated and flicker. ".
                "Use a lower-res cortex, e.g. --surf /sa/cortex10K (20000 faces) or /sa/cortex5K.\n",
                $o{surf}, scalar(@$F));
        }
        my $lowres = $o{surf} =~ m{cortex(?:1|2|5|10)K/?$};
        my @g = $lowres ? @LOCAL_TO_75K : (0 .. $nv - 1);
        @g == $nv or die sprintf("source-power: vertex/index mismatch (%d verts, %d idx)\n", $nv, scalar @g);
        my $grey = $o{overlay} ? $o{base_grey} : undef;       # 灰オーバレイ用ベース(OFF なら undef)
        my $thr  = $o{threshold};
        my ($vcol, $hi, $tv) = source_vcolors(\@pw, \@g, $o{cmap}, $o{power_clip}, $o{power_gamma}, $grey, $thr);
        $scene->{mesh}{vcolors} = $vcol;                      # zbuffer(Gouraud)経路が読む頂点色
        # line(スキャンライン)経路は面色 [Nf,3] のみ読むので、面の 3 頂点 t の平均で塗る。
        # これで --render line/zbuffer どちらでも源パワーが見える(server 無改変)。
        my (@FR,@FG,@FB);
        for my $f (@$F) {
            my ($a,$b,$c) = ($f->[0]-1, $f->[1]-1, $f->[2]-1);   # faces は 1-based
            my $tf = ($tv->[$a] + $tv->[$b] + $tv->[$c]) / 3;
            my $rgb = _overlay_rgb($tf, $o{cmap}, $grey, $thr);
            push @FR,$rgb->[0]; push @FG,$rgb->[1]; push @FB,$rgb->[2];
        }
        $scene->{mesh}{colors} = pdl([ \@FR, \@FG, \@FB ]);   # [Nf,3] 面ごと albedo
        printf STDERR "source-power: %d verts + %d faces coloured (%s), max=%.3g, clip=%g%%, render=%s\n",
            $nv, scalar(@$F), $o{cmap}, $hi, $o{power_clip}, $o{render};
        printf STDERR "  overlay: %s%s | scale: normalized source power, peak=1 (dimensionless; sLORETA/eLORETA statistic)\n",
            ($o{overlay} ? "on" : "off"),
            ($o{overlay} ? sprintf(" (threshold=%.2f, base-grey=%.2f)", $o{threshold}, $o{base_grey}) : "");

        # カラーバー(画面右 HUD): バーの色列を cmap+オーバレイと同じ _overlay_rgb で作り、
        # ドライバ(GS3D)へ渡す。ドライバは固定座標の水平線+ラベルで描く(giza-server 無改変)。
        if ($o{colorbar}) {
            my $N = 128;
            my @cols = map {
                my $rgb = _overlay_rgb($_/($N-1), $o{cmap}, $grey, $thr);
                [ map { int($_*255+0.5) } @$rgb ];
            } 0 .. $N-1;
            my @ticks = ([0,'0'], [0.5,'0.5'], [1,'1']);
            push @ticks, [$thr, sprintf('%.2f',$thr)] if defined $grey;   # 閾値線(オーバレイ時)
            $scene->{colorbar} = { colors=>\@cols, ticks=>\@ticks, title=>'power (norm.)' };
        }
    }
}

# ---- forward projection 用ローダ(P:EEG18) ----
# sa の 231ch モデル電極位置(V_fem_normal と index 1:1)と、pick 源のリードフィールド行。
our $VFN;                 # V_fem_normal を遅延ロードしてキャッシュ(74382×231 float ≈ 68MB)
our $VFN_SRC_DIM;         # source 軸(=74382 の次元)

# /sa/locs_3D_orig {3,231} → 電極位置 [231,3](mm)。V_fem_normal の 231ch と同順。
sub load_sa_electrodes {
    my ($file) = @_;
    require PDL::IO::HDF5; PDL::IO::HDF5->import;
    my $h = PDL::IO::HDF5->new($file);
    my $loc = _as_Nx3( $h->dataset('/sa/locs_3D_orig')->get, '/sa/locs_3D_orig' );  # [231,3]
    return $loc;
}

# 源(75K index g)の頭皮トポ = V_fem_normal の該当行/列 → 231 値。初回に全体をロード。
sub forward_topo {
    my ($file, $g) = @_;
    unless (defined $VFN) {
        warn "forward: loading leadfield V_fem_normal (~68MB, once)...\n";
        require PDL::IO::HDF5; PDL::IO::HDF5->import;
        my $h = PDL::IO::HDF5->new($file);
        $VFN = $h->dataset('/sa/cortex75K/V_fem_normal')->get;   # PDL、次元は {74382,231}↔軸反転
        # source 軸(74382)がどちらかを判定(チャンネル 231 と区別)
        my @d = $VFN->dims;
        $VFN_SRC_DIM = ($d[0] == 74382) ? 0 : 1;
        warn sprintf("forward: leadfield dims (%s), source axis = %d\n", join('x',@d), $VFN_SRC_DIM);
    }
    my $row = ($VFN_SRC_DIM == 0) ? $VFN->slice("($g),") : $VFN->slice(",($g)");
    return [ $row->list ];   # 231 値
}

# 231 値 → 発散カラーマップ [231,3](青=負, 白=0, 赤=正)。max|v| で正規化。
sub topo_colors {
    my ($vals) = @_;
    my $m = 0; for (@$vals) { my $a = abs $_; $m = $a if $a > $m; }
    $m ||= 1;
    my (@R,@G,@B);
    for my $v (@$vals) {
        my $t = $v / $m;                       # [-1,1]
        if ($t >= 0) { push @R,1;        push @G,1-$t;     push @B,1-$t; }   # 白→赤
        else         { my $s=-$t; push @R,1-$s; push @G,1-$s; push @B,1; }   # 白→青
    }
    return pdl([ \@R, \@G, \@B ]);             # [231,3]
}


# 既定: 内蔵 19 電極(理想 10-20, RAS mm)。P:EEG16 で NY Head と standard_1020 は
# 同一 MNI 枠=アライン不要が確定しているので、生座標のまま重畳する(残差 mean ~5mm)。
# --elc <file> があれば実モンタージュで上書き。--no-electrodes で無効。
# 点は面より後に描かれる(別配列)ので、頭皮に埋もれず常に手前に出る=モンタージュ確認向き。
if ($o{electrodes} || defined $o{elc}) {
    my (@ex, @ey, @ez, @lab);
    if (defined $o{elc}) {
        -f $o{elc} or die "not found: $o{elc}\n";
        require PDL::EEG::IO::ASA; PDL::EEG::IO::ASA->import('read_elc');
        my $elc = read_elc($o{elc});
        # read_elc は hash を返す: coords => PDL [3,N] (raw MNI mm)、labels => arrayref。
        # (overlay_scalp_obj.pl と同一の消費。{pos} はラベル→座標の hash なので使わない)
        my $coords = $elc->{coords};
        my $labels = $elc->{labels};
        my @d = $coords->dims;
        $coords = $coords->transpose->copy if @d == 2 && $d[0] != 3 && $d[1] == 3;  # [3,N] 前提
        @ex  = $coords->slice('(0),')->list;
        @ey  = $coords->slice('(1),')->list;
        @ez  = $coords->slice('(2),')->list;
        @lab = (ref $labels eq 'ARRAY') ? @$labels : map { "E$_" } 1 .. scalar(@ex);
    } else {
        # 内蔵フォールバック: 理想 10-20(球面近似, RAS mm)。実 NY Head 頭皮は非球面なので
        # 特に後頭部(P/T5/T6/O)が前寄り+内側にズレる。正確な配置は --elc で実 .elc を使うこと
        # (P:EEG16: 実 standard_1020.elc と NY Head は同一 MNI 枠、残差 mean ~5mm)。
        warn "electrodes: using APPROXIMATE built-in spherical 10-20 ".
             "(posterior sites will look forward/inside on the real head). ".
             "Pass --elc <standard_1020.elc> for accurate placement.\n";
        my @E = (
            [Fp1=>-27,83,-3],[Fp2=>27,83,-3],[F7=>-71,51,-3],[F3=>-48,59,44],
            [Fz=>0,63,61],[F4=>48,59,44],[F8=>71,51,-3],[T3=>-85,-1,-4],
            [C3=>-63,-3,61],[Cz=>0,0,95],[C4=>63,-3,61],[T4=>85,-1,-4],
            [T5=>-72,-47,-4],[P3=>-49,-63,45],[Pz=>0,-70,62],[P4=>49,-63,45],
            [T6=>72,-47,-4],[O1=>-27,-84,-3],[O2=>27,-84,-3],
        );
        for my $e (@E) { push @lab,$e->[0]; push @ex,$e->[1]; push @ey,$e->[2]; push @ez,$e->[3]; }
    }
    my $n = scalar @ex;

    # --snap: 各電極を最近傍の頭皮頂点へ寄せ、重心→頂点の外向きに proud mm 持ち上げる。
    # これは座標アライン(P:EEG16 で不要と確定)ではなく純粋な表示用スナップ。埋もれ/内側
    # 見えを解消し、電極を面の手前に確実に出す。生座標を見たいときは --no-snap(既定)。
    if ($o{snap}) {
        my ($cx,$cy,$cz) = (0,0,0);
        $cx += $_->[0] for @$V; $cy += $_->[1] for @$V; $cz += $_->[2] for @$V;
        my $nv = scalar @$V; $cx/=$nv; $cy/=$nv; $cz/=$nv;
        for my $i (0 .. $n-1) {
            my ($bx,$by,$bz,$bd) = (0,0,0,1e30);
            for my $v (@$V) {                              # 最近傍頂点(19×1082、総当たりで十分)
                my $d = ($v->[0]-$ex[$i])**2 + ($v->[1]-$ey[$i])**2 + ($v->[2]-$ez[$i])**2;
                ($bx,$by,$bz,$bd) = (@$v,$d) if $d < $bd;
            }
            my ($rx,$ry,$rz) = ($bx-$cx, $by-$cy, $bz-$cz);   # 外向き(重心→頂点)
            my $rl = sqrt($rx*$rx+$ry*$ry+$rz*$rz) || 1;
            $ex[$i] = $bx + $o{proud}*$rx/$rl;
            $ey[$i] = $by + $o{proud}*$ry/$rl;
            $ez[$i] = $bz + $o{proud}*$rz/$rl;
        }
        printf STDERR "electrodes: snapped to nearest scalp vertex + %.1fmm proud\n", $o{proud};
    }

    $scene->{points} = pdl([ \@ex, \@ey, \@ez ]);                        # [N,3]
    $scene->{colors} = pdl([ [(1.0)x$n], [(0.35)x$n], [(0.2)x$n] ]);     # 赤橙の点
    $scene->{labels} = \@lab;
    printf STDERR "electrodes: %d (%s)\n", $n, defined $o{elc} ? $o{elc} : 'built-in 10-20 approx';
}

our @IN_HO;        # 75K 頂点 → Harvard-Oxford atlas index(遅延ロード)
our @HO_NAMES;     # printed-index(0始まり)→ area 名。--ho-labels で供給
our $HO_BASE = 1;  # in_HO の基数(1-based MATLAB 想定、ロード時に実データで自動判定)

# --ho-labels <file>: H5Dump.pm 由来の "IDX : NAME" 形式(ヘッダ行あり)をそのまま食える。
# 素の "1行1名" 形式にも対応。sa の /sa/HO_labels は MATLAB cell {1,97} で PDL からは
# 読めないため、H5Dump.pm(h5dump 経由で #refs# を辿る)で txt 化して渡す。
if ($o{ho_labels}) {
    -f $o{ho_labels} or die "not found: $o{ho_labels}\n";
    open my $fh, '<', $o{ho_labels} or die "open $o{ho_labels}: $!\n";
    my @raw = <$fh>; close $fh;
    my $indexed = 0;
    for (@raw) {
        if (/^\s*(\d+)\s*:\s*(.+?)\s*$/) { $HO_NAMES[$1] = $2; $indexed = 1; }
    }
    unless ($indexed) {                       # 素の 1行1名(ヘッダ/空行は除外)
        @HO_NAMES = ();
        for (@raw) { chomp; push @HO_NAMES, $_ if /\S/ && !/Number of labels/i; }
    }
    printf STDERR "HO labels: %d area names loaded (%s)\n",
        scalar(grep { defined } @HO_NAMES), $indexed ? 'IDX:NAME' : 'plain';
}

# in_HO を遅延ロード(/sa/cortex75K/in_HO {1,74382})。同時に基数(0/1)を実データで判定。
sub in_HO_index {
    my ($file, $g) = @_;
    unless (@IN_HO) {
        require PDL::IO::HDF5; PDL::IO::HDF5->import;
        my $h = PDL::IO::HDF5->new($file);
        @IN_HO = $h->dataset('/sa/cortex75K/in_HO')->get->flat->list;
        my ($mn,$mx) = ($IN_HO[0],$IN_HO[0]);
        for (@IN_HO) { $mn=$_ if $_<$mn; $mx=$_ if $_>$mx; }
        $HO_BASE = ($mn >= 1) ? 1 : 0;        # 1-based なら 0 を含まない
        printf STDERR "in_HO: %d indices, range %d..%d -> base=%d\n",
            scalar @IN_HO, $mn, $mx, $HO_BASE;
    }
    return $IN_HO[$g];
}

# 75K 頂点 g → (HO index, area 名)。printed-index = in_HO値 - 基数。
sub ho_area {
    my ($g) = @_;
    my $hoi = int(in_HO_index($o{mat}, $g) + 0.5);
    my $ni  = $hoi - $HO_BASE;                # @HO_NAMES への 0始まり index
    my $name = ($ni >= 0 && $ni <= $#HO_NAMES && defined $HO_NAMES[$ni] && length $HO_NAMES[$ni])
               ? $HO_NAMES[$ni] : "HO#$hoi";
    return ($hoi, $name);
}

my $on_pick = sub {
    my ($idx, $x, $y, $z, $seedno) = @_;   # idx=ローカル頂点, (x,y,z)=MNI mm, seedno=0-based
    if ($is_cortex && $o{surf} =~ m{cortex(?:1|2|5|10)K/?$} && @LOCAL_TO_75K) {
        my $g = $LOCAL_TO_75K[$idx];                  # 75K 頂点 index(0-based)
        my ($hoi, $name) = ho_area($g);
        printf STDERR "  -> cortex75K v%d, HO atlas %d = %s  (leadfield V_fem_normal[%d,:])\n",
            $g, $hoi, $name, $g;
        return "$name ($hoi)";                        # ← シード表示ラベル(末尾に HO 番号)
    }
    return undef;
};

# hover: カーソル下の頂点の area 名を返す(右上の x,y,z の後ろに表示される)。
my $on_hover = sub {
    my ($idx, $x, $y, $z) = @_;
    if ($is_cortex && $o{surf} =~ m{cortex(?:1|2|5|10)K/?$} && @LOCAL_TO_75K) {
        my ($hoi, $name) = ho_area($LOCAL_TO_75K[$idx]);
        return "$name ($hoi)";
    }
    return undef;
};

my $drv = PDL::Graphics::Cairo::Driver::GS3D->new(
    render   => $o{render},
    scene    => $scene,
    width    => $o{width},
    height   => $o{height},
    zoom     => $o{zoom},
    on_pick  => $on_pick,
    on_hover => $on_hover,
);
$drv->run;
