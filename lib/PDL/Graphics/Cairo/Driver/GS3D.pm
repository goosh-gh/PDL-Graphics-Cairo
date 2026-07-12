package PDL::Graphics::Cairo::Driver::GS3D;
# Driver::GS3D  --  giza-server 経由の3D描画ドライバ (Phase 2)
#
# Driver::GS を継承し、3Dシーンの投影・送信・マウス入力受信を追加。
#
# REVIEW NOTE (2026-06-20):
#   - メッセージ番号を 0x20-0x23 から 0x24-0x27 に変更（既存の
#     GSP_MSG_CLOSE=0x20 / GSP_MSG_ACK=0x21 との衝突を回避。
#     gsp_3d.h 参照）。
#   - _recv_ack_sys はスタブだったため、Driver::GS::_recv_ack_sys の
#     実装パターン（ACKまでループし、割り込みメッセージを吸収する形）
#     に合わせて完全に書き直した。2D専用の SLIDER/RESIZE/SAVEREQ 分岐
#     は持たず、3D_INPUT のみを扱う独立ループとした（3DビューアにSLIDER
#     等は来ない前提）。SUPER::_recv_ack_sys には委譲していない。理由：
#     親の実装は「ACKが来るまで内部ループする」設計のため、外側からの
#     委譲だけでは3D_INPUTを割り込みとして吸収できない。
#   - _open_window という存在しないメソッドへの依存を解消し、
#     Driver::GS の NEWWIN 送信パターン（_send_msg + _recv_ack_sys）を
#     直接呼ぶ形に変更。NEWWIN ペイロードに3Dモードフラグ(flags=0x01)を
#     立てて送る案を追加（クライアント側のNEWWIN処理で2D/3D描画モードを
#     切り替える必要があるため。Cocoa/Xlib側の対応実装はTODO）。
#
# 使い方:
#   use PDL::Graphics::Cairo::Driver::GS3D;
#
#   my $scene = {
#       type   => 'scatter',
#       points => $xyz,      # PDL [N, 3]
#       colors => $rgb,      # PDL [N, 3] 0-1
#   };
#   my $drv = PDL::Graphics::Cairo::Driver::GS3D->new(
#       scene  => $scene,
#       width  => 600,
#       height => 600,
#   );
#   $drv->run;   # インタラクティブループ

use strict;
use warnings;
use parent 'PDL::Graphics::Cairo::Driver::GS';

our $VERSION = '0.2';   # <- Cairo.pm 本体の版表記に合わせて調整

use PDL;
use PDL::Basic qw(sequence);
use Time::HiRes qw(time sleep);   # 組み込みtime()をミリ秒精度版で上書き。
                                   # PDL/PDL::Basicにtime/sleep同名関数は
                                   # 無いので衝突なし。sleepも小数秒対応版に
                                   # なる(組み込みsleepは整数秒のみ)。

# GSPメッセージ番号（gsp_3d.h と一致。0x24からの新番号帯）
use constant {
    GSP_MSG_3D_FRAME => 0x24,
    GSP_MSG_3D_INPUT => 0x25,
    # GSP_MSG_3D_LABEL (0x26) は2026-06-21に廃止。ラベルはFRAMEペイロード
    # 末尾に統合した(ちらつき修正、_send_3d_frame参照)。欠番として
    # コメントだけ残し、0x26は再利用しない。
    GSP_MSG_3D_CLEAR => 0x27,

    NEWWIN_FLAG_3D   => 0x01,   # NEWWINペイロードに乗せる3Dモードフラグ（TODO: クライアント側対応）

    AXIS_LEN         => 100,
    DEFAULT_ZOOM     => 1.0,
    FOV              => 600,

    # REVIEW NOTE (2026-06-21, トラックボール回転): ドラッグ1pxあたりの
    # 回転角(radian)。0.01相当(旧theta/phiの感度と揃えた値)。大きいほど
    # 同じドラッグ量でより大きく回転する。
    DRAG_SENSITIVITY => 0.01,

    # REVIEW NOTE (2026-06-23, クォータニオン回転): 縦ドラッグをworld-X軸
    # 回転に変換するときの符号。giza本体(giza-3d-engine.c)は画面y下向きの
    # ドラッグデルタ前提で呼び出し側が -dy と反転していたが、Cocoaビューは
    # isFlipped=NO(yが既に上向き)なので、その -dy を無批判に写すと二重反転
    # になる。実機で縦ドラッグが逆向きに感じたら +1 を -1 に変える。
    DRAG_DY_SIGN     => +1,

    # REVIEW NOTE (2026-06-23, キラリティ修正): _projectでscreen-xを反転
    # (cx - x)した結果、横ドラッグの見た目の回転方向が反転する場合がある。
    # その時のための符号ノブ。まず+1(回転計算は現状のまま)で確認し、横
    # ドラッグが逆に感じたら-1にする。screen-x反転とは独立した調整。
#    DRAG_DX_SIGN     => +1,
    DRAG_DX_SIGN     => -1,

    # REVIEW NOTE (2026-06-20 実機計測): run()のwhile(1)ループは
    # フレーム送信→ACK受信を可能な限り高速に繰り返す設計だったため、
    # 実機計測で毎秒8800フレーム相当の送信頻度が確認され、Cocoa側の
    # drawRect:がディスプレイのリフレッシュレートを大幅に超える頻度で
    # 呼ばれ続け、静止時でも常時ちらつく原因になっていた
    # (test_gs3d_electrode.plでの実機報告: マウス操作の有無に関係なく
    # 常時チラつく)。MIN_FRAME_INTERVALで明示的に頭打ちする
    # (60fps相当 = 1/60秒間隔)。
    MIN_FRAME_INTERVAL => 1.0 / 60,
};

# ============================================================
# コンストラクタ
# ============================================================
sub new {
    my ($class, %args) = @_;
    my $self = $class->SUPER::new(%args);   # Driver::GS の new (Moo経由) を流用
    $self->{scene}       = $args{scene} or die "scene required";

    # 設計変遷(2026-06): theta/phi(オイラー2軸) -> 累積回転行列(トラックボール、
    # 経路依存で T3/T4 反転) -> look-at(gluLookAt風、極でジンバルロック) を経て、
    # 現在はクォータニオン方式に確定(下記 2026-06-24 の直接種づけ)。旧 look-at の
    # cam_azimuth/cam_elevation 状態と _compute_lookat_rotation は 0.2 で撤去。
    $self->{cam_distance}  = $args{cam_distance}  // 300;   # 注視点(原点)からのカメラ距離(現状はzoomと別概念)

    # REVIEW NOTE (2026-06-24, 既定姿勢の直接種づけ):
    # 既定姿勢を、標準EEGトポマップ(頭頂を上から見下ろす: 鼻=Fp画面上、
    # 左耳=T3画面左、右耳=T4画面右、Cz中央・手前=上に凸)に直接種づけする。
    # qrot=(0,0,0,1) は Z軸180°回転 = R=diag(-1,-1,1)(proper, det=+1)。
    # _projectのscreen-x反転を込みで較正した実機マッピング上、これが
    # 上記トポマップを与えることを検算済み。look-atの「up基準=前(Fp)」
    # という規約を経由しないので、向きの混乱(カメラ角度と画面の180°ずれ、
    # 真後ろビューでの左右の見え方)を根本から断つ。以降は純クォータニオン
    # 回転で、この正しい左右(剛体回転で不変)が保たれる。
    # NOTE(seed規約): qrot は (w,x,y,z) 表記。(0,0,0,1)=w0/z1=Z軸180°=diag(-1,-1,1)
    # であり「恒等ではない」。wx viewer(tools/pdl_3d_wx.pl)は seed=(1,0,0,0)恒等+
    # _project で sy=-Y と Y反転を投影側に置く。畳み込む軸が逆(GS3D=screen-X反転)
    # なので GS3D の (0,0,0,1) を wx へ流用しないこと(二重反転で mirror になる)。
    $self->{qrot} = [ 0, 0, 0, 1 ];
    $self->{rot}  = _q_to_rot(@{$self->{qrot}});

    $self->{zoom}        = $args{zoom}   // DEFAULT_ZOOM;
    $self->{perspective} = $args{perspective} // 1;

    # XYZ軸定義: PDL規則(2)により [4,3] 形 (dim0=4点/N点、dim1=XYZ) で統一する。
    #
    # REVIEW NOTE (2026-06-20): Phase1 (pdl_3d_wx.pl) の axes_xyz と書き方を
    # 統一した。Phase1は「軸(行)ごとに4点分の値を並べる」形で書いており、
    # これは pdl([[行],...]) の規則(内側リスト長=dim0,外側リスト数=dim1)に
    # 素直に当てはまり、3行4列のリテラルがそのまま [4,3] になる。
    # (このファイルの旧版は「点ごとの行」で書いて->transposeしていたが、
    # Phase1と書き方を揃えるため不要なtransposeを廃した。動作は等価。)
    my $al = AXIS_LEN;
    $self->{axes} = PDL->pdl([
        [0, $al, 0,   0  ],  # X成分: 原点,X先端,Y先端,Z先端
        [0, 0,   $al, 0  ],  # Y成分
        [0, 0,   0,   $al],  # Z成分
    ]);   # [4,3] (dim0=4点, dim1=XYZ) -- Phase1と同じ書き方
    return $self;
}

# ============================================================
# 回転行列 [3, 3] を返す。
#
# REVIEW NOTE (2026-06-21): 旧実装はtheta/phiから毎フレーム$ry x $rzを
# 計算していたが、トラックボール回転方式への変更により、回転行列
# そのもの($self->{rot})を状態として直接保持するようになった。
# このメソッドは単にその状態を返すだけになる。
# ============================================================
sub _rotation {
    my ($self) = @_;
    return $self->{rot};
}

# ============================================================
# クォータニオン・ヘルパ群 (2026-06-23、giza-3d-quat.c の忠実な移植。
# Shugo Suwazono, LGPL v2.1)。メソッドではなく純関数。
#
# クォータニオンは4要素リスト (w, x, y, z) で表す。回転は $self->{qrot}
# に累積し、そこから導いた3x3行列 $self->{rot} が描画側(_rotate_points/
# _project)の唯一の契約として使われる(契約は不変、作り方だけが変わった)。
#
# 回転モデルはgiza_3d_view_rotate()と同じ: world軸まわりの小回転を左から
# 合成(rot = rx * ry * rot)し、毎フレーム正規化する。サンドボックスで
# 2000ステップ累積後も直交性 max err 4.4e-16(機械イプシロン級)を確認済み。
# ============================================================
sub _q_identity { return (1, 0, 0, 0); }

sub _q_axis_angle {            # axis は単位ベクトルであること
    my ($ax, $ay, $az, $ang) = @_;
    my $s = sin($ang * 0.5);
    return (cos($ang * 0.5), $ax*$s, $ay*$s, $az*$s);
}

sub _q_mul {                   # Hamilton積 a*b (bを先に、次にaを適用)
    my ($aw,$ax,$ay,$az, $bw,$bx,$by,$bz) = @_;
    return (
        $aw*$bw - $ax*$bx - $ay*$by - $az*$bz,
        $aw*$bx + $ax*$bw + $ay*$bz - $az*$by,
        $aw*$by - $ax*$bz + $ay*$bw + $az*$bx,
        $aw*$bz + $ax*$by - $ay*$bx + $az*$bw,
    );
}

sub _q_norm {
    my ($w,$x,$y,$z) = @_;
    my $len = sqrt($w*$w + $x*$x + $y*$y + $z*$z);
    return _q_identity() if $len < 1e-12;
    return ($w/$len, $x/$len, $y/$len, $z/$len);
}

# クォータニオン -> 3x3回転行列。pdl([[行],...]) の行優先で書き下すので、
# $R x $pts_n3 が転置なしで [N,3] 点群を out = R . v に回転する。これは
# 旧 look-at の $self->{rot} と完全に同じ契約(_rotate_points がそのまま使える)。
sub _q_to_rot {
    my ($w,$x,$y,$z) = @_;
    my ($x2,$y2,$z2) = ($x*$x,$y*$y,$z*$z);
    my ($xy,$xz,$yz) = ($x*$y,$x*$z,$y*$z);
    my ($wx,$wy,$wz) = ($w*$x,$w*$y,$w*$z);
    return PDL->pdl([
        [1-2*($y2+$z2),   2*($xy-$wz),     2*($xz+$wy)   ],
        [2*($xy+$wz),     1-2*($x2+$z2),   2*($yz-$wx)   ],
        [2*($xz-$wy),     2*($yz+$wx),     1-2*($x2+$y2) ],
    ]);
}

# 3x3回転行列 -> クォータニオン (w,x,y,z)。行列は row-major(pdl([[行],...])で
# 構成)なので R[i][j] = $m->at(j,i) として読む。初期化/リセット時に look-at
# 既定姿勢からqrotを種づけするためだけに使う(Shepperd分岐法。サンドボックス
# で5000回往復 max err 1.1e-15、180度の3分岐も厳密一致を確認済み)。
sub _mat_to_quat {
    my ($m) = @_;
    my $r00 = $m->at(0,0); my $r01 = $m->at(1,0); my $r02 = $m->at(2,0);
    my $r10 = $m->at(0,1); my $r11 = $m->at(1,1); my $r12 = $m->at(2,1);
    my $r20 = $m->at(0,2); my $r21 = $m->at(1,2); my $r22 = $m->at(2,2);
    my $tr = $r00 + $r11 + $r22;
    my ($w,$x,$y,$z);
    if ($tr > 0) {
        my $s = 0.5/sqrt($tr+1.0);
        $w=0.25/$s; $x=($r21-$r12)*$s; $y=($r02-$r20)*$s; $z=($r10-$r01)*$s;
    } elsif ($r00>$r11 && $r00>$r22) {
        my $s = 2.0*sqrt(1.0+$r00-$r11-$r22);
        $w=($r21-$r12)/$s; $x=0.25*$s; $y=($r01+$r10)/$s; $z=($r02+$r20)/$s;
    } elsif ($r11>$r22) {
        my $s = 2.0*sqrt(1.0+$r11-$r00-$r22);
        $w=($r02-$r20)/$s; $x=($r01+$r10)/$s; $y=0.25*$s; $z=($r12+$r21)/$s;
    } else {
        my $s = 2.0*sqrt(1.0+$r22-$r00-$r11);
        $w=($r10-$r01)/$s; $x=($r02+$r20)/$s; $y=($r12+$r21)/$s; $z=0.25*$s;
    }
    return _q_norm($w,$x,$y,$z);
}

# ============================================================
# クォータニオン方式でのドラッグ操作(2026-06-23、look-at方式を置き換え)。
#
# 画面上のドラッグ差分(dx, dy)から、world軸まわりの小さな回転クォータニオン
# を作り、現在の姿勢に左から合成して正規化する。giza_3d_view_rotate()の
# 忠実な移植: rot = rx * ry * rot; normalise。
#
#   横ドラッグ(dx) -> world-Y軸まわりの回転
#   縦ドラッグ(dy)  -> world-X軸まわりの回転(符号は DRAG_DY_SIGN で調整)
#
# elevationクランプは無い。クォータニオンには極が無いため、look-at方式で
# 残っていた極(elevation=0/pi)付近の不連続(ドラッグ中に視点が飛ぶ)が
# 原理的に起きない。また毎フレームの正規化で基底が厳密に直交を保つため、
# 旧トラックボール方式の経路依存な左右反転(基底が累積誤差で鏡映に近づく)
# も起きない。
# ============================================================
sub _apply_drag_rotation {
    my ($self, $dx, $dy) = @_;
    my $q  = $self->{qrot};
    my @ry = _q_axis_angle(0, 1, 0, DRAG_DX_SIGN * $dx * DRAG_SENSITIVITY);  # 横 -> world Y
    my @rx = _q_axis_angle(1, 0, 0, DRAG_DY_SIGN * $dy * DRAG_SENSITIVITY);  # 縦 -> world X
    my @r  = _q_mul(@rx, _q_mul(@ry, @$q));
    $self->{qrot} = [ _q_norm(@r) ];
    $self->{rot}  = _q_to_rot(@{$self->{qrot}});
}

# ============================================================
# 3D→スクリーン投影
#   入力: $pts3d は [N, 3] (PDL規則2に統一)
#   出力: (sx[N], sy[N], depth[N])
#
# REVIEW NOTE: 旧実装は $rot3d->slice('(2),') 等、dim0固定のslice
# （[3,N]前提）を使っていた。Phase2規則(2)(3)により [N,3] (dim1=XYZ)
# に統一したので、抜き出しは slice(',(0)') / slice(',(1)') / slice(',(2)')
# （dim1固定）に直す必要がある。回転適用側 ($rot x $pts->transpose 等)
# も合わせて [N,3]統一に揃えた（_send_3d_frame 側で対応）。
# ============================================================
sub _project {
    my ($self, $pts3d) = @_;
    my $cx   = $self->width / 2;
    my $cy   = $self->height / 2;
    my $zoom = $self->{zoom};

    my $x = $pts3d->slice(',(0)');
    my $y = $pts3d->slice(',(1)');
    my $z = $pts3d->slice(',(2)');

    # REVIEW NOTE (2026-06-23, キラリティ修正): screen-xを反転(cx - x*…)する。
    # 既定ビュー az=0.6/el=1.17 の数学予測では T4(+X)→screenX正(右)になるはず
    # だが、実機ではT4が左・T3が右に見える(回転は剛体なので既定ビュー時点で
    # 既に反転している = 固定的な左右鏡映)。原因がデータの手系(+X=左)であれ
    # Cocoa側のx反転であれ、screen-xが生まれる唯一の場所であるここで1回反転
    # すれば、両ケースとも rendered ∝ +math に揃い、確定的に直る。上下(screenY)
    # と奥行き(z)は触らないので、Cz浮き沈み・Fp上下の対応は不変。
    if ($self->{perspective}) {
        my $fov = FOV * $zoom;
        my $w   = $fov / ($fov - $z + 200);
        my $sx  = $cx - $x * $w * $zoom;
        my $sy  = $y * $w * $zoom + $cy;
        return ($sx, $sy, $z);
    } else {
        my $sx = $cx - $x * $zoom;
        my $sy = $y * $zoom + $cy;
        return ($sx, $sy, $z);
    }
}

# ============================================================
# [N,3]データを回転行列で回転する共通ヘルパー。
#
# REVIEW NOTE (2026-06-20 実機検証済み): 当初案は $pts_n3->transpose
# してから $rot x ... し、また transpose で戻す「往復」だったが、これは
# 誤りでエラーになることが実機で確認された（check_rot_x_n3.pl）。
#
# PDLの x (matmult) 演算子の実際の規則: $left x $right が成立する条件は
# 「$left->dim(0) == $right->dim(1)」。$rot は [3,3] (dim0=dim1=3)、
# $pts_n3 は [N,3] (dim0=N, dim1=3) なので、$rot->dim(0)=3 と
# $pts_n3->dim(1)=3 が常に一致する。つまり transpose は一切不要で、
# $rot x $pts_n3 をそのまま呼ぶだけで [N,3] の結果が返る。
# 実機での検算（90度Z回転で (1,0,0)->(0,1,0), (0,1,0)->(-1,0,0)）でも
# 数学的に正しい結果と一致することを確認済み。
# ============================================================
sub _rotate_points {
    my ($self, $rot, $pts_n3) = @_;       # $pts_n3: [N,3]
    return $rot x $pts_n3;                 # [N,3] そのまま、転置不要
}

# ============================================================
# フレームをGSPで送信
# ============================================================
sub _send_3d_frame {
    my ($self) = @_;
    my $rot   = $self->_rotation();
    my $scene = $self->{scene};

    my @lines_data;
    my @points_data;
    my @label_recs;   # 2026-06-21: 軸ラベル(XYZ)も使うため宣言を関数冒頭に移動

    # ---- XYZ軸（線分として送信）----
    my $rot_ax = $self->_rotate_points($rot, $self->{axes});   # [4,3]
    my ($ax, $ay, $az) = $self->_project($rot_ax);
    my @ax_colors = ([255,80,80,255], [80,255,80,255], [80,160,255,255]);
    for my $i (0..2) {
        push @lines_data, {
            x0 => $ax->at(0), y0 => $ay->at(0),
            x1 => $ax->at($i+1), y1 => $ay->at($i+1),
            depth => ($az->at(0) + $az->at($i+1)) / 2,
            rgba  => $ax_colors[$i],
        };
    }

    # ---- 軸の矢じり (2026-06-21追加) ----
    # REVIEW NOTE: goosh氏からの実機フィードバックで「Czが画面上方にある
    # 視点で、本来左側にあるはずの電極(Fp1,F3,T5等)が右側に見える」という
    # 報告があった。これが「実は下から見上げている視点なのに上から見て
    # いると誤解している」という単純な視覚的混乱なのか、実際の座標計算
    # バグなのかを切り分けるため、各軸の先端に矢じりを追加し、軸の
    # 「先端方向」を視覚的に明確にする(矢じりが無いと、対称的な直線は
    # 画面に投影された時点でどちらが手前/奥か、上下が判別しにくい)。
    #
    # 計算方法: スクリーン投影後の2D空間で、軸線分(原点->先端)の方向
    # ベクトルに対して垂直な向きに、先端から少し戻った位置に矢じりの
    # 両翼を配置する。3D空間で計算せず2D(投影後)で計算するのは、矢じり
    # 自体が「画面上で見やすい一定の大きさ」であるべきで、3D空間での
    # 矢じりサイズだと遠近感で極端に小さく/大きく見えてしまうため。
    my @ax_labels = ('X', 'Y', 'Z');
    for my $i (0..2) {
        my $x0 = $ax->at(0);    my $y0 = $ay->at(0);     # 原点(投影後)
        my $x1 = $ax->at($i+1); my $y1 = $ay->at($i+1);  # 軸先端(投影後)
        my $dx = $x1 - $x0; my $dy = $y1 - $y0;
        my $len = sqrt($dx*$dx + $dy*$dy) || 1;          # ゼロ除算回避
        my $ux  = $dx / $len; my $uy = $dy / $len;       # 軸方向の単位ベクトル
        my $px  = -$uy;       my $py = $ux;              # 垂直方向の単位ベクトル

        my $head_len = 12;   # 矢じりの長さ(px、画面上で一定)
        my $head_wid = 5;    # 矢じりの開き幅(px)

        # 矢じりの根本(先端から軸方向にhead_len戻った位置)
        my $bx = $x1 - $ux * $head_len;
        my $by = $y1 - $uy * $head_len;
        # そこから垂直方向にhead_widだけ開いた2点
        my $lx = $bx + $px * $head_wid; my $ly = $by + $py * $head_wid;
        my $rx = $bx - $px * $head_wid; my $ry = $by - $py * $head_wid;

        my $tip_depth = $az->at($i+1);   # 矢じり自体の深度は先端のdepthを流用
        for my $wing ([$lx,$ly], [$rx,$ry]) {
            push @lines_data, {
                x0 => $x1, y0 => $y1,
                x1 => $wing->[0], y1 => $wing->[1],
                depth => $tip_depth,
                rgba  => $ax_colors[$i],
            };
        }

        # 軸ラベル(X/Y/Z文字)を先端の少し外側に追加。矢じりと合わせて
        # 「どちらが上/手前か」をさらに明確にする(goosh氏フィードバック対応)。
        #
        # BUG FIX (2026-06-21): $ax_colors[$i] は [R,G,B,A] の4要素
        # (線分・矢じり用、gsp_3d_line_tはRGBA4バイト)だが、ラベル
        # レコード(gsp_3d_label_t)の色フィールドはRGB3バイトのみで
        # アルファを持たない。4要素のまま渡すと、_send_3d_frame末尾の
        # pack('... CCCC ...', @{$lb->{rgb}}, $len, ...) で
        # CCCC(4スロット)にR,G,B,A(4要素)が入ってしまい、本来そこに
        # 入るべき$len(テキスト長)が1つ後ろにずれて`a*`の文字列側に
        # 混入する。これによりCocoa側で読み取るlenの値が破壊され
        # (実機でlen=255という異常値として観測された)、テキストが
        # 全く描画されなくなっていた。電極ラベル(379行目付近)は元々
        # 3要素のRGBを渡していたため問題なかった。
        # 修正: スライスで先頭3要素(RGB)だけを渡す。
        push @label_recs, {
            x    => $x1 + $ux * 10,
            y    => $y1 + $uy * 10,
            rgb  => [@{$ax_colors[$i]}[0,1,2]],   # RGBAの先頭3要素(RGB)のみ
            text => $ax_labels[$i],
        };
    }

    # ---- ワイヤーフレーム線 ----
    # $scene->{lines} は [M, 9]: dim1 = (x0,y0,z0, x1,y1,z1, r,g,b)
    if (exists $scene->{lines}) {
        my $lines = $scene->{lines};
        my $p0    = $lines->slice(':,0:2');    # [M,3]
        my $p1    = $lines->slice(':,3:5');    # [M,3]
        my $r0    = $self->_rotate_points($rot, $p0);
        my $r1    = $self->_rotate_points($rot, $p1);
        my ($sx0, $sy0, $d0) = $self->_project($r0);
        my ($sx1, $sy1, $d1) = $self->_project($r1);
        my $rgb   = $lines->slice(':,6:8');
        for my $i (0 .. $lines->dim(0) - 1) {
            push @lines_data, {
                x0 => $sx0->at($i), y0 => $sy0->at($i),
                x1 => $sx1->at($i), y1 => $sy1->at($i),
                depth => ($d0->at($i) + $d1->at($i)) / 2,
                rgba  => [
                    int($rgb->at($i,0)*255),
                    int($rgb->at($i,1)*255),
                    int($rgb->at($i,2)*255),
                    200
                ],
            };
        }
    }

    # ---- 点群 ----
    if (exists $scene->{points}) {
        my $pts    = $scene->{points};    # [N, 3]
        my $colors = $scene->{colors};    # [N, 3]
        my $rp     = $self->_rotate_points($rot, $pts);   # [N,3]
        my ($sx, $sy, $depth) = $self->_project($rp);
        my $order = $depth->qsorti;             # 奥から手前
        for my $idx ($order->list) {
            push @points_data, {
                x     => $sx->at($idx),
                y     => $sy->at($idx),
                depth => $depth->at($idx),
                size  => $self->{zoom} * 4,
                rgba  => [
                    int($colors->at($idx,0)*255),
                    int($colors->at($idx,1)*255),
                    int($colors->at($idx,2)*255),
                    255,
                ],
            };
        }
        # ラベル
        if (exists $scene->{labels}) {
            for my $i (0 .. $#{$scene->{labels}}) {
                push @label_recs, {
                    x    => $sx->at($i) + 6,
                    y    => $sy->at($i) - 6,
                    rgb  => [255, 255, 200],
                    text => $scene->{labels}[$i],
                };
            }
        }
    }

    # ---- ペイロードのパック ----
    # gsp_3d_frame_hdr_t: n_lines(u16) n_points(u16) flags(u8) cx(f32) cy(f32) = 13 bytes
    my $nl  = scalar @lines_data;
    my $np  = scalar @points_data;
    my $cx  = $self->width / 2;
    my $cy  = $self->height / 2;
    my $payload = pack('S S C f< f<', $nl, $np, 0x03, $cx, $cy);

    # 線分レコード: x0 y0 x1 y1 depth r g b a (f32×5 + u8×4 = 24 bytes)
    for my $ln (@lines_data) {
        $payload .= pack('f<f<f<f<f<CCCC',
            $ln->{x0}, $ln->{y0}, $ln->{x1}, $ln->{y1},
            $ln->{depth}, @{$ln->{rgba}});
    }

    # 点レコード: x y depth size r g b a (f32×4 + u8×4 = 20 bytes)
    for my $pt (@points_data) {
        $payload .= pack('f<f<f<f<CCCC',
            $pt->{x}, $pt->{y}, $pt->{depth}, $pt->{size},
            @{$pt->{rgba}});
    }

    # ---- ラベルセクション (2026-06-21追加) ----
    # REVIEW NOTE (ちらつき修正): 旧実装はFRAME送信後、ラベルを
    # GSP_MSG_3D_LABEL として1個ずつ別メッセージで送っていた。Cocoa側で
    # 「clear→add×N」がdrawRect:の再描画と競合し、ラベル個数が
    # 0,1,2,...,Nと不規則に見えてしまう(実機で確認済み)バグの原因だった。
    # FRAMEペイロード自体にラベルを連結することで、点・線と同じく
    # 1回のNSData置き換えでアトミックに反映されるようにする。
    # 構造: n_labels(u16) + 各ラベル(point_idx(u16) x(f32) y(f32)
    #       r,g,b(u8) len(u8) text[len])
    my $n_labels = scalar @label_recs;
    $payload .= pack('S', $n_labels);
    for my $lb (@label_recs) {
        my $text = $lb->{text};
        my $len  = length($text);
        # 防御的チェック (2026-06-21追加): rgbが3要素(RGB)でなければ
        # pack('CCCC...')のスロット数とズレ、$len以降が破壊される
        # (実機で実際に踏んだバグ。die せず警告+先頭3要素に丸めて
        # 描画自体は継続させる - 1ラベルの色が想定と違うだけなら実害は
        # 小さいが、これを無視してpackすると全ラベルのテキストが
        # 消えるという重大な実害になるため)。
        my @rgb = @{$lb->{rgb}};
        if (@rgb != 3) {
            warn "Driver::GS3D: label rgb has " . scalar(@rgb)
               . " elements (expected 3, RGB only - no alpha). "
               . "Truncating/padding to avoid corrupting the label payload.\n";
            @rgb = (@rgb[0,1,2], (0,0,0))[0,1,2];   # 3要素に切り詰め/0埋め
        }
        $payload .= pack('S f< f< CCCCa*',
            0xFFFF,                      # point_idx=0xFFFF → 絶対座標センチネル
            $lb->{x}, $lb->{y},
            @rgb,
            $len, $text);
    }

    PDL::Graphics::Cairo::Driver::GS::_send_msg(
        $self->{_ix3d}{sock}, GSP_MSG_3D_FRAME, $payload, $self->{_ix3d}{seq}++);
}

# ============================================================
# インタラクティブループ
# ============================================================
sub run {
    my ($self) = @_;

    $self->_ensure_server;     # Driver::GS のサーバ確保ロジックを継承

    my $sock = IO::Socket::UNIX->new(
        Type => IO::Socket::UNIX::SOCK_STREAM(),
        Peer => PDL::Graphics::Cairo::Driver::GS::_sock_path())
        or die "Driver::GS3D: connect " . PDL::Graphics::Cairo::Driver::GS::_sock_path() . ": $!\n";
    $sock->autoflush(1);
    binmode($sock);

    my $seq = 0;
    # NEWWINペイロードに3Dモードフラグをのせる案。
    # TODO: Cocoa/Xlib側のNEWWINハンドラがこのフラグを見て描画モードを
    # 切り替える実装がまだない。現状はクライアントが2Dモード前提のまま
    # 0x24(3D_FRAME)を受け取ることになるので、クライアント側対応が
    # 統合の前提条件。フラグの場所は要相談（NEWWINペイロード末尾に
    # 1バイト追加 or 別途 GSP_MSG_3D_CLEAR を「3Dセッション開始」通知に
    # 流用する、等の選択肢がある）。
    PDL::Graphics::Cairo::Driver::GS::_send_msg(
        $sock, PDL::Graphics::Cairo::Driver::GS::GSP_MSG_NEWWIN,
        pack('L L', $self->width, $self->height), $seq++);
    $self->_recv_ack_3d($sock);

    $self->{_ix3d} = { sock => $sock, seq => $seq };

    # REVIEW NOTE: $last_frame_time はループの直前で初期化し、各イテレー
    # ション末尾で更新する。フレーム送信そのものより前に経過時間を測る
    # ことで、_send_3d_frame自体の処理時間も含めた実際のフレーム間隔を
    # 制御できる(ACK待ち時間だけを見ると、ローカルソケットなので待ち時間
    # がほぼ0になり、結局無制限速度に戻ってしまうため)。
    my $last_frame_time = time();

    while (1) {
        $self->_send_3d_frame();
        my $input = $self->_recv_ack_3d($sock);

        last unless defined $input;          # 接続切断

        if ($input->{input_3d}) {
            my $inp = $input->{input_3d};
            # REVIEW NOTE (2026-06-21, トラックボール回転): dtheta/dphiの
            # 単純加算(オイラー角)ではなく、_apply_drag_rotationで現在の
            # $self->{rot}に小さな回転を合成する。これにより、視点が
            # どの向きにあっても、ドラッグした方向にそのまま回転して
            # 見えるようになり、Cz等のZ軸上の点も画面の任意の位置
            # (真上含む)に到達できるようになる(旧実装の2自由度制約を解消)。
            $self->_apply_drag_rotation($inp->{dx}, $inp->{dy});
            $self->{zoom}  *= (1 + $inp->{dzoom} * 0.1)
                if abs($inp->{dzoom}) > 0.01;

            # REVIEW NOTE (2026-06-23, クォータニオン方式): 姿勢は
            # $self->{qrot}に累積され、$self->{rot}はそこから導出される
            # (_apply_drag_rotation参照)。極が無いため極付近の不連続は
            # 起きず、毎フレーム正規化で経路依存の左右反転も起きない。

            if ($inp->{type} == 2) {
                if ($inp->{key} == ord('p') || $inp->{key} == ord('P')) {
                    $self->{perspective} = !$self->{perspective};
                } elsif ($inp->{key} == ord('r') || $inp->{key} == ord('R')) {
                    # リセット: 標準EEGトポマップ(上から見下ろし)に戻す。
                    $self->{qrot} = [ 0, 0, 0, 1 ];
                    $self->{rot}  = _q_to_rot(@{$self->{qrot}});
                    $self->{zoom} = DEFAULT_ZOOM;
                }
            }
        }

        # --- フレームレート制限 (2026-06-20追加、実機計測で8800fps相当
        # が確認されたことへの対処) ---
        # 経過時間がMIN_FRAME_INTERVALに満たなければ差分だけ待つ。
        # マウス入力(GSP_MSG_3D_INPUT)はACK受信前に_recv_ack_3dが吸収
        #済みなので、ここでsleepしても入力の取りこぼしにはならない
        # (次のループ先頭で最新のtheta/phiの状態から_send_3d_frameする)。
        my $now = time();
        my $elapsed = $now - $last_frame_time;
        if ($elapsed < MIN_FRAME_INTERVAL) {
            sleep(MIN_FRAME_INTERVAL - $elapsed);
        }
        $last_frame_time = time();
    }
    delete $self->{_ix3d};
    $sock->close;
}

# ============================================================
# 3D版 _recv_ack_sys。
#
# REVIEW NOTE: 親(Driver::GS)の_recv_ack_sysをそのまま使わず独立実装
# にした理由は上部コメント参照。ループ構造とsysread/EOF処理パターンは
# 親の_sysread_exactをそのまま再利用し、分岐だけ3D用に絞った。
#
# 戻り値:
#   - 通常のACK受信のみ → { } (空hashref。input_3dキーなし)
#   - 3D_INPUT を1つ以上吸収した → { input_3d => {...} } (最後の1つを採用。
#     coalescing: ドラッグ中に複数届いた場合、最新の差分だけ残りは握り潰す。
#     ただしdtheta/dphiは「差分」なので本来は積算すべきという指摘がある。
#     TODO: 複数INPUTが溜まった場合にdtheta/dphiを単純上書きでなく
#     加算すべきかどうか、実機でドラッグ操作の追従性を見て判断する。)
#   - 接続切断 → undef
# ============================================================
sub _recv_ack_3d {
    my ($self, $sock) = @_;
    my $result = {};

    while (1) {
        my $hdr = $self->_sysread_exact($sock, 16);
        return undef unless defined $hdr;        # EOF/エラー = 接続切断

        my ($magic, $ver, $type, $flags, $len) = unpack('L C C S L', $hdr);
        die "Driver::GS3D: bad magic\n"
            unless $magic == PDL::Graphics::Cairo::Driver::GS::GSP_MAGIC();

        my $payload = $len ? $self->_sysread_exact($sock, $len) : '';
        return undef if $len && !defined $payload;

        if ($type == PDL::Graphics::Cairo::Driver::GS::GSP_MSG_ACK()) {
            return $result;                       # 本命のACK。今までに吸収した分を返す
        }
        elsif ($type == GSP_MSG_3D_INPUT) {
            # gsp_3d_input_t: dx(f32) dy(f32) dzoom(f32) type(u8) key(u8) = 14 bytes
            # (2026-06-21: dtheta/dphiからdx/dyに改名。バイトレイアウトは
            #  不変、意味が「角度差分」から「ドラッグの生ピクセル差分」
            #  に変わった。トラックボール回転方式、_apply_drag_rotation参照)
            my ($dx, $dy, $dzoom, $itype, $key)
                = unpack('f< f< f< C C', $payload);
            # Driver::GS継承のverbose(PDLCAIRO_DEBUG=1で有効)でのみ出力。
            # マウス/キー入力がCocoa側からPerl側へ到達しているかの確認用。
            if ($self->verbose) {
                printf STDERR "[GS3D] 3D_INPUT received: dx=%.3f dy=%.3f dzoom=%.3f type=%d key=%d(%s)\n",
                    $dx, $dy, $dzoom, $itype, $key,
                    ($key ? chr($key) : '');
            }

            # REVIEW NOTE (2026-06-21): dx/dy/dzoomは「差分」なので、ACK
            # 待ち中に複数のINPUTが溜まった場合は積算する(取りこぼし防止)。
            # type/keyは離散的なイベント(キー押下)なので積算の意味がなく、
            # 最後に届いたものをそのまま使う。
            if ($result->{input_3d}) {
                $result->{input_3d}{dx}    += $dx;
                $result->{input_3d}{dy}    += $dy;
                $result->{input_3d}{dzoom} += $dzoom;
                $result->{input_3d}{type}   = $itype;
                $result->{input_3d}{key}    = $key;
            } else {
                $result->{input_3d} = {
                    dx => $dx, dy => $dy, dzoom => $dzoom,
                    type   => $itype,  key  => $key,
                };
            }
            # ACKではないのでループを継続し、本命のACKを待つ
        }
        elsif ($type == PDL::Graphics::Cairo::Driver::GS::GSP_MSG_ERR()) {
            warn "Driver::GS3D: server error: $payload\n";
            return $result;
        }
        # 想定外の型は読み捨ててループ継続（ACKを待ち続ける）
    }
}

1;
__END__

=encoding utf-8

=head1 NAME

PDL::Graphics::Cairo::Driver::GS3D - giza-server経由の3Dビューア (Phase 2)

=head1 SYNOPSIS

  use PDL::Graphics::Cairo::Driver::GS3D;

  my $scene = {
      type   => 'electrode',
      points => $xyz_pdl,     # [N, 3]
      colors => $rgb_pdl,     # [N, 3]  0-1
      labels => \@labels,     # ['Fp1', 'Fp2', ...]
  };

  my $drv = PDL::Graphics::Cairo::Driver::GS3D->new(
      scene  => $scene,
      width  => 600,
      height => 600,
  );
  $drv->run;

=head1 DESCRIPTION

Driver::GS を継承し、GSPプロトコルに 3D描画メッセージ (0x24〜0x27) を追加。
PDL側でCPU行列演算により投影を行い、スクリーン座標の線分・点リストを
Cocoa/Xlibクライアントに送信する。OpenGL不要。

=head1 STATUS (2026-06-23 更新 — クォータニオン方式への移行)

解決済み:

=over 4

=item * NEWWIN時の3Dモード通知は、GSP_MSG_3D_FRAME初回受信時にCocoa側で
is_3dフラグをラッチする方式で解決済み（NEWWINペイロード自体は無変更）。

=item * _rotation/_project の単体テストは実機検証済み（PDL軸規則・
matmult規則の確認含む）。

=item * ラベルのちらつきは、GSP_MSG_3D_LABEL(個別送信)を廃止し、
FRAMEペイロードに統合することで解決済み（線・点と同じアトミック更新に統一）。

=item * Cz(頭頂、Z軸上の点)を画面の任意位置に持ってこられない問題は、
theta/phiのオイラー角2軸合成(2自由度)からトラックボール方式の任意軸
回転に変更して一旦解決したが、トラックボール方式には別の問題があった
（次項）。

=item * トラックボール方式(累積回転行列)では、ドラッグの経路によって
T3/T4の左右(Neurosurgeon's view相当の配置とRadiologist's view相当の
配置)が入れ替わってしまう経路依存のバグがあった(2026-06-22実機検証で
発覚、rot行列の1行目=画面right方向の基底が、ドラッグの累積で元のX軸
からほぼ反転するまでズレていた)。これをlook-at方式(OpenGLのgluLookAt
と同じ考え方。cam_azimuth/cam_elevationという球面座標を状態として持ち、
毎フレームview/up/right=up×viewを再構成してrotを作る)に変更して解決
した。

goosh氏の確定要件(同日、2回の訂正を経て確定): 「Czが上に凸(浮く、頭を
上から見下ろすNeurosurgeon's view)ならT3が画面左・T4が画面右、Czが
下に凸(沈む、足元から見上げるRadiologist's view)ならT3が画面右・T4が
画面左」という対応が常に一貫していることが要件であり、どちらの視点も
正しい(片方が常に正解ということではない)。right=up×viewという外積の
順序が、check_float_lr_consistency.plでの全elevation角度の検証により
この対応をほぼ全件再現することを確認済み(elevation≈90度の境界付近の
わずかな不一致を除く)。

=back

未解決のTODO:

=over 4

=item * ドラッグ感度(DRAG_SENSITIVITY)は仮の値。実機でドラッグの
追従感を見て調整が必要かもしれない。

=item * zoom/panは現状cam_distance(未使用、_projectのzoom属性とは別物)
として状態だけ用意したが、実際の操作への結線(ホイール操作でcam_distance
を変える、pan操作で画面オフセットを加える等)はまだ未実装。

=item * Xlibクライアント側（giza-server-xlib-3d.c等）は未対応。
今回のラベル統合・look-at方式の変更はCocoa側のみ反映済み。

=item * look-at方式で残っていた極(elevation=0/pi)付近のジンバルロック的な
不連続(ドラッグ中に視点が飛ぶ。2026-06-22実機報告)は、2026-06-23に
クォータニオン方式(giza本体 giza-3d-quat.c/giza-3d-engine.c で実証済みの
world軸増分回転を左合成+毎フレーム正規化)へ移行して解決。状態は
$self->{qrot}に累積し、$self->{rot}はそこから導出。左右対応は既定姿勢を qrot=(0,0,0,1)
(=diag(-1,-1,1))へ直接種づけして確定(_projectのscreen-X反転込みで較正済み。
0.2 で look-at 種づけ経路と _compute_lookat_rotation は撤去)。極が無く、
毎フレーム正規化で基底が厳密直交を保つため、極の不連続もトラックボール方式の
経路依存反転も原理的に起きない。一時診断ログ([GS3D-DIAG]ブロック)は移行と
同時に削除済み。

=back

=cut
