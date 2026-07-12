#!/usr/bin/env perl
# verify_gs3d.pl — GS3D.pm 0.2 クリーンアップ後の動作確認(2段)
#
# Tier 1 (どこでも / PDL不要): ソース静的検査 + POD検査 +
#         クォータニオン不変量を plain-Perl 参照実装で検算。
# Tier 2 (Mac / 要 PDL+Driver::GS): 実モジュールを load して
#         $VERSION・撤去済みメソッド・実 _q_to_rot(seed)・剛体性を検査。
#         ※ new() は呼ばない(giza-server 接続を起こさないため)。
#
#   perl verify_gs3d.pl [--src path/to/GS3D.pm]
#   （既定: lib/PDL/Graphics/Cairo/Driver/GS3D.pm）
use strict; use warnings;
use Test::More;

my $src = 'lib/PDL/Graphics/Cairo/Driver/GS3D.pm';
for (my $i=0; $i<@ARGV; $i++) { $src = $ARGV[$i+1] if $ARGV[$i] eq '--src'; }
-f $src or plan skip_all => "source not found: $src";
my $text = do { open my $fh,'<:encoding(UTF-8)',$src or die $!; local $/; <$fh> };

# ---- Tier 1a: 静的検査 ----------------------------------------------------
like($text, qr/^package\s+PDL::Graphics::Cairo::Driver::GS3D\s*;/m,
     'package = PDL::Graphics::Cairo::Driver::GS3D');
like($text, qr/^our\s+\$VERSION\s*=/m,          'our $VERSION 宣言あり');
like($text, qr/^=encoding\s+utf-?8/mi,          '=encoding utf-8 あり');
unlike($text, qr/sub\s+_compute_lookat_rotation/, '_compute_lookat_rotation 撤去済み');
is(scalar(() = $text =~ /\{cam_azimuth\}/g),   0, 'コード上の {cam_azimuth} なし');
is(scalar(() = $text =~ /\{cam_elevation\}/g), 0, 'コード上の {cam_elevation} なし');
like($text, qr/\{cam_distance\}/,                '{cam_distance} は残置(zoom/pan用)');
for my $sub (qw(new _rotation _q_identity _q_axis_angle _q_mul _q_norm
                _q_to_rot _apply_drag_rotation _project _rotate_points
                _send_3d_frame run)) {
    like($text, qr/sub\s+\Q$sub\E\b/, "live sub: $sub");
}
cmp_ok(scalar(() = $text =~ /\{qrot\}\s*=\s*\[\s*0\s*,\s*0\s*,\s*0\s*,\s*1\s*\]/g),
       '>=', 2, 'qrot seed=(0,0,0,1) が new と reset に存在');
like($text, qr/sub\s+_q_identity\s*\{\s*return\s*\(\s*1\s*,\s*0\s*,\s*0\s*,\s*0\s*\)/,
     '_q_identity=(1,0,0,0)=恒等(wxと同値・GS3D seedとは別物)');

# ---- Tier 1b: POD 検査 ----------------------------------------------------
SKIP: {
    eval { require Pod::Checker; 1 } or skip 'Pod::Checker 不在', 1;
    my $out=''; open my $ph,'>',\$out;
    my $errs = Pod::Checker::podchecker($src, $ph); close $ph;
    is($errs, 0, 'POD 構文エラー 0 (podchecker)') or diag($out);
}

# ---- Tier 1c: クォータニオン不変量(plain-Perl 参照実装)-------------------
sub qR { my($w,$x,$y,$z)=@_; [
  [1-2*($y*$y+$z*$z), 2*($x*$y-$w*$z),   2*($x*$z+$w*$y)  ],
  [2*($x*$y+$w*$z),   1-2*($x*$x+$z*$z), 2*($y*$z-$w*$x)  ],
  [2*($x*$z-$w*$y),   2*($y*$z+$w*$x),   1-2*($x*$x+$y*$y)] ]; }
sub qmul { my($a,$b)=@_; my($aw,$ax,$ay,$az)=@$a; my($bw,$bx,$by,$bz)=@$b;
  [ $aw*$bw-$ax*$bx-$ay*$by-$az*$bz, $aw*$bx+$ax*$bw+$ay*$bz-$az*$by,
    $aw*$by-$ax*$bz+$ay*$bw+$az*$bx, $aw*$bz+$ax*$by-$ay*$bx+$az*$bw ]; }
sub qnorm { my $q=shift; my $n=sqrt($q->[0]**2+$q->[1]**2+$q->[2]**2+$q->[3]**2)||1; [map{$_/$n}@$q]; }
sub qaa { my($x,$y,$z,$t)=@_; my $s=sin($t/2); [cos($t/2),$x*$s,$y*$s,$z*$s]; }
sub det3 { my $m=shift;
  $m->[0][0]*($m->[1][1]*$m->[2][2]-$m->[1][2]*$m->[2][1])
 -$m->[0][1]*($m->[1][0]*$m->[2][2]-$m->[1][2]*$m->[2][0])
 +$m->[0][2]*($m->[1][0]*$m->[2][1]-$m->[1][1]*$m->[2][0]); }
sub near { my($a,$b,$e)=@_; $e//=1e-9; abs($a-$b)<=$e; }
sub Rdiag { my($m,$a,$b,$c,$e)=@_; $e//=1e-9;
  return 0 unless near($m->[0][0],$a,$e)&&near($m->[1][1],$b,$e)&&near($m->[2][2],$c,$e);
  for my $i (0..2){for my $j (0..2){ next if $i==$j; return 0 unless near($m->[$i][$j],0,$e);}} 1; }
sub orthoerr { my $R=shift; my $mx=0;
  for my $i (0..2){for my $j (0..2){ my $s=0; $s+=$R->[$_][$i]*$R->[$_][$j] for 0..2;
    my $e=abs($s-($i==$j?1:0)); $mx=$e if $e>$mx; }} $mx; }

my $Rs = qR(0,0,0,1);
ok(Rdiag($Rs,-1,-1,1), 'seed(0,0,0,1) → R=diag(-1,-1,1)');
ok(near(det3($Rs),1),  'seed det=+1 (proper rotation)');
my $Ri = qR(1,0,0,0);
ok(Rdiag($Ri,1,1,1),   'identity(1,0,0,0) → R=I');
ok(!near($Rs->[0][0],$Ri->[0][0]), 'seed と identity は別物(§5: 流用不可)');

srand(42); my $q=[1,0,0,0];
for (1..2000){ my @a=(rand()*2-1,rand()*2-1,rand()*2-1);
  my $n=sqrt($a[0]**2+$a[1]**2+$a[2]**2)||1; @a=map{$_/$n}@a;
  $q=qnorm(qmul(qaa(@a,(rand()-0.5)*0.2),$q)); }   # world軸 左合成 + 正規化
my $R=qR(@$q); my $oe=orthoerr($R);
cmp_ok($oe,'<',1e-10, sprintf('2000step 後も直交性維持 (max|R^T R - I|=%.2e)',$oe));
ok(near(det3($R),1,1e-9), '累積後も det=+1');

# ---- Tier 2: 実モジュール load(Mac / 要 PDL)------------------------------
SKIP: {
    my $lib = $src;
    my $ok  = ($lib =~ s{/PDL/Graphics/Cairo/Driver/GS3D\.pm$}{});
    eval { require PDL; 1 }        or skip 'PDL 不在(Mac で実行)', 4;
    $ok                           or skip 'lib ルート推定不可', 4;
    unshift @INC, ($lib eq '' ? '.' : $lib);
    eval { require PDL::Graphics::Cairo::Driver::GS3D; 1 }
                                  or skip "モジュール load 失敗: $@", 4;
    my $pkg='PDL::Graphics::Cairo::Driver::GS3D';
    no strict 'refs';
    ok(defined ${"${pkg}::VERSION"}, '実 $VERSION = '.(${"${pkg}::VERSION"}//'undef'));
    ok(!$pkg->can('_compute_lookat_rotation'), '実モジュールにも look-at 撤去反映');
    ok($pkg->can('_q_to_rot'), '_q_to_rot 生存');
    my $Rp = &{"${pkg}::_q_to_rot"}(0,0,0,1);
    my @f  = $Rp->list; my $M=[[@f[0..2]],[@f[3..5]],[@f[6..8]]];
    ok(Rdiag($M,-1,-1,1,1e-9), '実 _q_to_rot(seed)=diag(-1,-1,1)');
}
done_testing;
