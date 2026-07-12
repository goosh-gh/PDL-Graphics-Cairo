#!/usr/bin/env perl
# verify_gs3d_projection.pl — GS3D の _project / _apply_drag_rotation を
# headless で検証する(giza-server 接続なし・描画なし・目視なし)。
#
#   * new() は呼ばない。bare hash を bless して純関数だけ叩く。
#   * standard_1020.elc の実電極座標を使う(--elc)。無ければ内蔵の
#     理想 10-20 座標へ自動フォールバック(RAS: +X=右, +Y=前, +Z=上)。
#
# 検証内容:
#   [1] seed(0,0,0,1) で canonical topomap:
#       T3 画面左 / T4 画面右 / Fp 画面上 / Cz 中央かつ手前 / chirality 非鏡映
#   [2] 縦ドラッグ sweep(2π): Cz が真上を越えて「回り続ける」
#       - 画面座標が連続(極なし・ジンバルロックで止まらない)
#       - Cz depth が両符号 = 頂点を越えて裏側まで到達
#       - T3/T4 は world-X 軸上なので全域で不動(左右が壊れない)
#       - 2π 後に seed ビューへ復帰(ドリフトなし)
#   [3] 横ドラッグ sweep(2π): yaw で左右がちょうど 2 回、0 近傍を連続通過
#
# 使い方:
#   perl tools/verify_gs3d_projection.pl                       # リポジトリルートで
#   perl tools/verify_gs3d_projection.pl --elc /path/standard_1020.elc
#   perl tools/verify_gs3d_projection.pl --map                 # ASCII 散布図つき
use strict;
use warnings;
use Test::More;

my ($ELC, $SHOW_MAP, $LIB) = (undef, 0, 'lib');
for (my $i = 0; $i < @ARGV; $i++) {
    $ELC      = $ARGV[$i+1] if $ARGV[$i] eq '--elc';
    $LIB      = $ARGV[$i+1] if $ARGV[$i] eq '--lib';
    $SHOW_MAP = 1           if $ARGV[$i] eq '--map';
}

eval { require PDL; 1 }
    or plan skip_all => 'PDL 不在(Mac で実行してください)';
unshift @INC, $LIB;
eval { require PDL::Graphics::Cairo::Driver::GS3D; 1 }
    or plan skip_all => "GS3D load 失敗(--lib で lib ルートを指定): $@";
my $PKG = 'PDL::Graphics::Cairo::Driver::GS3D';

# ---- 電極座標 -------------------------------------------------------------
my %POS = (                       # 内蔵フォールバック(RAS, mm 相当)
    Cz  => [   0,    0,  95 ],
    Fpz => [   0,   88,  -1 ],
    Oz  => [   0,  -98,  -1 ],
    T3  => [ -85,   -1,  -4 ],    # = T7 (左耳)
    T4  => [  85,   -1,  -4 ],    # = T8 (右耳)
);
my $src_label = 'built-in ideal 10-20 (RAS)';

if (defined $ELC && -f $ELC) {
    my (%raw, @labels, @xyz, $in_pos, $in_lab);
    open my $fh, '<', $ELC or die "elc open: $!";
    while (my $l = <$fh>) {
        $l =~ s/\s+$//;
        if    ($l =~ /^\s*Positions/i)     { $in_pos = 1; $in_lab = 0; next }
        elsif ($l =~ /^\s*Labels/i)        { $in_lab = 1; $in_pos = 0; next }
        elsif ($l =~ /^\s*[A-Za-z]+\s*=/)  { next }          # NumberPositions= 等
        if ($l =~ /^\s*([A-Za-z0-9_']+)\s*:\s*(-?[\d.eE+-]+)\s+(-?[\d.eE+-]+)\s+(-?[\d.eE+-]+)/) {
            $raw{$1} = [ $2+0, $3+0, $4+0 ];                 # "Fp1: x y z" 形式
        }
        elsif ($in_pos && $l =~ /^\s*(-?[\d.eE+-]+)\s+(-?[\d.eE+-]+)\s+(-?[\d.eE+-]+)\s*$/) {
            push @xyz, [ $1+0, $2+0, $3+0 ];                 # 座標のみの行
        }
        elsif ($in_lab && $l =~ /\S/) {
            (my $t = $l) =~ s/^\s+//;
            push @labels, split /\s+/, $t;                   # ラベル行
        }
    }
    close $fh;
    if (!%raw && @labels && @labels == @xyz) {               # Positions/Labels 別ブロック
        $raw{ $labels[$_] } = $xyz[$_] for 0 .. $#labels;
    }
    my %alias = (Cz => ['Cz'], Fpz => ['Fpz','Fp1'], Oz => ['Oz','O1'],
                 T3 => ['T3','T7'], T4 => ['T4','T8']);      # T3/T7・T4/T8 別名吸収
    my %got;
    for my $k (keys %alias) {
        for my $c (@{ $alias{$k} }) { $got{$k} = $raw{$c}, last if exists $raw{$c} }
    }
    if (5 == grep { $got{$_} } qw(Cz Fpz Oz T3 T4)) { %POS = %got; $src_label = "$ELC (実電極)" }
    else { diag('elc から 5 電極を取得できず → 内蔵座標へフォールバック') }
}
diag("electrodes: $src_label");

my @N   = qw(Cz Fpz Oz T3 T4);
my $pts = PDL->pdl([ [ map { $POS{$_}[0] } @N ],   # X (dim0=N)
                     [ map { $POS{$_}[1] } @N ],   # Y
                     [ map { $POS{$_}[2] } @N ] ]);  # [N,3]

# ---- new() を回避して bare object を組む(giza-server 接続なし)------------
my ($W, $H) = (600, 600);
sub bare_self {
    my ($q) = @_;
    no strict 'refs';
    return bless { width => $W, height => $H, zoom => 1, perspective => 1,
                   qrot => [@$q], rot => &{"${PKG}::_q_to_rot"}(@$q) }, $PKG;
}
sub project_all {
    my ($self) = @_;
    my ($sx, $sy, $z) = $self->_project($self->_rotate_points($self->{rot}, $pts));
    return map { $N[$_] => [ $sx->at($_), $sy->at($_), $z->at($_) ] } 0 .. $#N;
}
# 画面 sy は下向き正 → 数学的上向きへ直して符号付き面積(chirality)
sub chirality {
    my %s = @_;
    my @F = ($s{Fpz}[0], -$s{Fpz}[1]);
    my @L = ($s{T3}[0],  -$s{T3}[1]);
    my @R = ($s{T4}[0],  -$s{T4}[1]);
    return ($L[0]-$F[0]) * ($R[1]-$F[1]) - ($L[1]-$F[1]) * ($R[0]-$F[0]);
}
# 参照符号は「理想トポマップ(Fp上/T3左/T4右)」から同式で算出(自作定義を排除)
my $CHI_REF = (-1-0)*(0-1) - (0-1)*(1-0);

# ============================================================
# [1] seed = canonical topomap
# ============================================================
my %s = project_all(bare_self([0,0,0,1]));
note(sprintf('%-4s %8s %8s %8s', qw(name sx sy depth)));
note(sprintf('%-4s %8.1f %8.1f %8.1f', $_, @{ $s{$_} })) for @N;

cmp_ok($s{T3}[0],  '<', $s{T4}[0], 'T3 が画面左 / T4 が画面右 (sx: T3 < T4)');
cmp_ok($s{Fpz}[1], '<', $s{Oz}[1], 'Fp が画面上 / O が画面下 (sy 下向き正)');

# Cz の中央性は「原点にある」ではなく「頭部スケールに対して中央寄り」で判定する。
# 実 standard_1020.elc は原点が耳介間 midpoint 基準のため Cz は解剖学的に
# やや後方(数 mm)にあり、画面上でも中心から僅かにずれるのが正しい。
# 内蔵理想座標(Cz=(0,0,95))前提の「±1px」判定は実データで偽陽性になる。
my $R_head = ($s{T4}[0] - $s{T3}[0]) / 2;                       # 画面上の頭半径 [px]
my $cz_off = sqrt(($s{Cz}[0] - $W/2)**2 + ($s{Cz}[1] - $H/2)**2);
note(sprintf('Cz の中心からのずれ: %.1f px = 頭半径の %.1f%% (実頭部では Cz は僅かに後方)',
             $cz_off, 100 * $cz_off / $R_head));
cmp_ok($cz_off / $R_head, '<', 0.25, 'Cz は画面中央付近(ずれ < 頭半径の 25%)');

my ($nearest) = sort { $a->[1] <=> $b->[1] }
                map { [ $_, sqrt(($s{$_}[0]-$W/2)**2 + ($s{$_}[1]-$H/2)**2) ] } @N;
is($nearest->[0], 'Cz', '5 電極中 Cz が画面中心に最も近い');

my ($deepest) = sort { $s{$b}[2] <=> $s{$a}[2] } @N;
is($deepest, 'Cz', 'Cz が最も手前 = 上に凸(頭頂が視点側)');
cmp_ok($s{Cz}[2], '>', 0,     'Cz は手前 = 上に凸 (depth > 0)');
ok(chirality(%s) * $CHI_REF > 0,
   sprintf('chirality が理想トポマップと同符号 = 非鏡映 [%.4g]', chirality(%s)));

# ---- 共通: sweep ドライバ -------------------------------------------------
my $SENS  = do { no strict 'refs'; eval { &{"${PKG}::DRAG_SENSITIVITY"}() } // 0.01 };
my $STEPS = int(2 * 4 * atan2(1,1) / $SENS);     # 1px × N step = ちょうど 2π
sub sweep {
    my ($dx, $dy) = @_;
    my $d = bare_self([0,0,0,1]);
    my %p = project_all($d);
    my %r = (max_jump => 0, flips => 0, flip_near_zero => 1,
             lr_always_ok => 1, cz_pos => 0, cz_neg => 0);
    my $prev_lr = $p{T4}[0] - $p{T3}[0];
    for my $i (1 .. $STEPS) {
        $d->_apply_drag_rotation($dx, $dy);
        my %c = project_all($d);
        for my $n (@N) {                                   # (a) 連続性 = 極なし
            my $j = sqrt(($c{$n}[0]-$p{$n}[0])**2 + ($c{$n}[1]-$p{$n}[1])**2);
            $r{max_jump} = $j if $j > $r{max_jump};
        }
        my $lr = $c{T4}[0] - $c{T3}[0];                    # (b) 左右
        $r{lr_always_ok} = 0 if $lr <= 0;
        if (($lr > 0) != ($prev_lr > 0)) {                 # (c) 入替は 0 近傍のみ
            $r{flips}++;
            $r{flip_near_zero} = 0 unless abs($prev_lr) < 40 && abs($lr) < 40;
        }
        $c{Cz}[2] > 0 ? $r{cz_pos}++ : $r{cz_neg}++;       # (d) 頂点越え
        $prev_lr = $lr; %p = %c;
    }
    $r{ret} = 0;                                           # (e) 2π 後の復帰誤差
    my %e = project_all($d);
    for my $n (@N) {
        my $m = (abs($e{$n}[0]-$s{$n}[0]) > abs($e{$n}[1]-$s{$n}[1]))
              ?  abs($e{$n}[0]-$s{$n}[0]) : abs($e{$n}[1]-$s{$n}[1]);
        $r{ret} = $m if $m > $r{ret};
    }
    return %r;
}

# ============================================================
# [2] 縦ドラッグ 2π: 頂点を越えて回り続ける(world-X 軸回転)
# ============================================================
note(sprintf('vertical sweep: dy=1px × %d step (=2π, DRAG_SENSITIVITY=%g)', $STEPS, $SENS));
my %v = sweep(0, 1);
cmp_ok($v{max_jump}, '<', 5,
       sprintf('縦 sweep 全域で画面座標が連続 = 極なし (max %.2f px/step)', $v{max_jump}));
ok($v{cz_pos} > 0 && $v{cz_neg} > 0,
   "Cz depth が両符号 = 頂点を越えて裏まで回り続けた (手前 $v{cz_pos} / 奥 $v{cz_neg} step)");
ok($v{lr_always_ok},
   'T3/T4 は world-X 軸上 → 縦 sweep 全域で左右不動(鏡映が壊れない)');
cmp_ok($v{ret}, '<', 2,
       sprintf('2π 後に seed ビューへ復帰 = ドリフトなし (誤差 %.3f px)', $v{ret}));

# ============================================================
# [3] 横ドラッグ 2π: yaw で左右がちょうど 2 回、連続に入れ替わる
# ============================================================
note(sprintf('horizontal sweep: dx=1px × %d step (=2π)', $STEPS));
my %h = sweep(1, 0);
cmp_ok($h{max_jump}, '<', 5,
       sprintf('横 sweep 全域で画面座標が連続 (max %.2f px/step)', $h{max_jump}));
is($h{flips}, 2, 'yaw 一周で左右の入替はちょうど 2 回(突発反転なし)');
ok($h{flip_near_zero}, '左右の入替は 0 近傍を連続通過(瞬間反転でない)');
cmp_ok($h{ret}, '<', 2,
       sprintf('2π 後に seed ビューへ復帰 (誤差 %.3f px)', $h{ret}));

# ---- 任意: ASCII 散布図 ---------------------------------------------------
if ($SHOW_MAP) {
    my @g = map { [ (' ') x 41 ] } 0 .. 20;
    for my $n (@N) {
        my $c = int($s{$n}[0] / $W * 40);
        my $r = int($s{$n}[1] / $H * 20);
        $g[$r][$c] = substr($n, 0, 1) if $c >= 0 && $c <= 40 && $r >= 0 && $r <= 20;
    }
    note('--- seed view (画面座標: 上が画面上, 左が画面左) ---');
    note(join '', @{ $g[$_] }) for 0 .. 20;
    note('--- C=Cz F=Fpz O=Oz T=T3/T4 ---');
}
done_testing;
