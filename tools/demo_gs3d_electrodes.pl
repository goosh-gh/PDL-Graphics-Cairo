#!/usr/bin/env perl
# demo_gs3d_electrodes.pl — GS3D を実際に窓に出して目視確認する。
#
#   perl tools/demo_gs3d_electrodes.pl
#   perl tools/demo_gs3d_electrodes.pl --elc ~/src/giza-server/tools/standard_1020.elc
#
# headless 検証(verify_gs3d_projection.pl)は _project の「数式」を保証する。
# こちらは Cocoa/Xlib クライアントが「その計算どおり描いているか」を見る。
# 過去の drawRect y-flip 系のバグはここでしか出ない。
#
# 左右は非対称に色付けする(対称な図では鏡映バグが原理的に見えないため):
#     左半球 = オレンジ / 右半球 = シアン / 正中 = 白
#     T3(左耳)と T4(右耳)は特に明るく、大きめのラベルで表示。
# 軸はモジュール側が描く: X=赤 Y=緑 Z=青(矢じり+ラベルつき)。
use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo::Driver::GS3D;

my $ELC = "$ENV{HOME}/src/giza-server/tools/standard_1020.elc";
for (my $i = 0; $i < @ARGV; $i++) { $ELC = $ARGV[$i+1] if $ARGV[$i] eq '--elc' }

# ---- 内蔵フォールバック: 標準 19ch 10-20 (RAS mm, +X=右 +Y=前 +Z=上) ------
my @STD19 = (
    [Fp1 => -27,  83,  -3], [Fp2 =>  27,  83,  -3],
    [F7  => -71,  51,  -3], [F3  => -48,  59,  44], [Fz => 0,  63, 61],
    [F4  =>  48,  59,  44], [F8  =>  71,  51,  -3],
    [T3  => -85,  -1,  -4], [C3  => -63,  -3,  61], [Cz => 0,   0, 95],
    [C4  =>  63,  -3,  61], [T4  =>  85,  -1,  -4],
    [T5  => -72, -47,  -4], [P3  => -49, -63,  45], [Pz => 0, -70, 62],
    [P4  =>  49, -63,  45], [T6  =>  72, -47,  -4],
    [O1  => -27, -84,  -3], [O2  =>  27, -84,  -3],
);

my (@name, @xyz);
if (-f $ELC) {
    my (%raw, @labels, @pos, $in_pos, $in_lab);
    open my $fh, '<', $ELC or die "elc: $!";
    while (my $l = <$fh>) {
        $l =~ s/\s+$//;
        if    ($l =~ /^\s*Positions/i)    { $in_pos = 1; $in_lab = 0; next }
        elsif ($l =~ /^\s*Labels/i)       { $in_lab = 1; $in_pos = 0; next }
        elsif ($l =~ /^\s*[A-Za-z]+\s*=/) { next }
        if ($l =~ /^\s*([A-Za-z0-9_']+)\s*:\s*(-?[\d.eE+-]+)\s+(-?[\d.eE+-]+)\s+(-?[\d.eE+-]+)/) {
            $raw{$1} = [ $2+0, $3+0, $4+0 ];
        } elsif ($in_pos && $l =~ /^\s*(-?[\d.eE+-]+)\s+(-?[\d.eE+-]+)\s+(-?[\d.eE+-]+)\s*$/) {
            push @pos, [ $1+0, $2+0, $3+0 ];
        } elsif ($in_lab && $l =~ /\S/) {
            (my $t = $l) =~ s/^\s+//; push @labels, split /\s+/, $t;
        }
    }
    close $fh;
    if (!%raw && @labels && @labels == @pos) { $raw{$labels[$_]} = $pos[$_] for 0..$#labels }
    # 10-20 の主要電極だけ拾う(全 300ch 出すと画面が潰れるため)
    my @want = qw(Fp1 Fp2 F7 F3 Fz F4 F8 T3 T7 C3 Cz C4 T4 T8
                  T5 P7 P3 Pz P4 T6 P8 O1 Oz O2);
    my %seen;
    for my $w (@want) {
        next unless $raw{$w};
        my $canon = { T7 => 'T3', T8 => 'T4', P7 => 'T5', P8 => 'T6' }->{$w} // $w;
        next if $seen{$canon}++;
        push @name, $canon; push @xyz, $raw{$w};
    }
    printf "electrodes: %s (%d ch)\n", $ELC, scalar @name;
}
if (!@name) {
    @name = map { $_->[0] } @STD19;
    @xyz  = map { [ @{$_}[1..3] ] } @STD19;
    print "electrodes: built-in standard 19ch (elc なし → フォールバック)\n";
}

# ---- 色: 左=オレンジ / 右=シアン / 正中=白、T3/T4 は最大輝度 --------------
my @rgb;
for my $i (0 .. $#name) {
    my $x = $xyz[$i][0];
    my $n = $name[$i];
    if    ($n eq 'T3')     { push @rgb, [1.0, 0.45, 0.0 ] }   # 左耳: 明オレンジ
    elsif ($n eq 'T4')     { push @rgb, [0.0, 0.85, 1.0 ] }   # 右耳: 明シアン
    elsif (abs($x) < 5)    { push @rgb, [1.0, 1.0,  1.0 ] }   # 正中: 白
    elsif ($x < 0)         { push @rgb, [0.9, 0.55, 0.25] }   # 左半球
    else                   { push @rgb, [0.3, 0.7,  0.85] }   # 右半球
}

my $points = pdl([ [ map { $_->[0] } @xyz ],     # X (dim0=N)
                   [ map { $_->[1] } @xyz ],     # Y
                   [ map { $_->[2] } @xyz ] ]);  # [N,3]
my $colors = pdl([ [ map { $_->[0] } @rgb ],
                   [ map { $_->[1] } @rgb ],
                   [ map { $_->[2] } @rgb ] ]);  # [N,3]

print <<"HELP";

--- GS3D 目視確認 ---
色:  T3(左耳)=明オレンジ / T4(右耳)=明シアン / 左半球=オレンジ系
     右半球=シアン系 / 正中(Fz,Cz,Pz,Oz)=白
軸:  X=赤  Y=緑(鼻方向)  Z=青(頭頂方向)   ※矢じり付き

チェック項目:
 1. 起動直後 = canonical か
      Fp が画面上 / T3(オレンジ)が画面左 / T4(シアン)が画面右
      Cz が中央・最も手前(大きく見える) / 緑の Y 軸矢印が画面上向き
      → これが崩れていればクライアント側の描画(y-flip 等)を疑う
 2. 縦ドラッグ: 頂点を越えても止まらず回り続ける(極なし)
      耳(オレンジ/シアン)は画面左右に留まったままピッチする
 3. 横ドラッグ: 一周でオレンジとシアンがちょうど 2 回入れ替わる(yaw)
 4. r キー: canonical に一発で戻る
 5. p キー: 透視 / 正射 切替(奥行きの遠近感が消える)
 6. スクショを撮り、verify_gs3d_projection.pl --map の ASCII 配置と照合

閉じる: 窓を閉じる / Ctrl-C
---------------------

HELP

my $drv = PDL::Graphics::Cairo::Driver::GS3D->new(
    scene  => { points => $points, colors => $colors, labels => \@name },
    width  => 700,
    height => 700,
);
$drv->run;
