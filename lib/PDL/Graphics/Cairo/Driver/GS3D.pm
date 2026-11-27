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
#       # --- 面(P:EEG18で追加。省略可。points/lines/labels と併用可)---
#       mesh   => {
#           verts   => $vc,        # PDL [Nv,3]  頂点(mm)
#           faces   => $tri,       # PDL [Nf,3]  三角面 index(0/1-based 自動)
#           color   => [0.85,0.78,0.70],  # 基本色 0-1(省略時は暖色グレー)
#         # colors  => $fc,        # PDL [Nf,3]  面ごとの基本色(color より優先)
#           light   => [0.3,0.4,1.0],     # view 空間の光方向(既定 前上右)
#           ambient => 0.25,
#           winding => 'auto',     # 'auto'|'ccw'|'cw'  外向き法線の決め方
#           alpha   => 255,
#           fill_step => 1,        # 走査間隔(px)。継ぎ目が出たら 0.5 に
#       },
#   };
#
#   面は z バッファ無し環境向けのソフトウェアパイプライン(投影→バックフェース
#   カリング→面デプスソート=画家のアルゴリズム→flat Lambert→スキャンライン塗り)
#   で描く。塗りは既存の「線分プリミティブ」に落とすので giza-server 側は無改変。
#   凸メッシュ(頭皮 ≈1082頂点)は綺麗。凹メッシュ(皮質・脳溝で自己遮蔽)は
#   面ソートだとアーティファクトが出る(正確な遮蔽は .obj→Blender を使う)。
#   幾何スカラー部は PDL::Graphics::Cairo::Mesh3D に分離(headless 検証可)。
#   my $drv = PDL::Graphics::Cairo::Driver::GS3D->new(
#       scene  => $scene,
#       width  => 600,
#       height => 600,
#   );
#   $drv->run;   # インタラクティブループ

use strict;
use warnings;
use parent 'PDL::Graphics::Cairo::Driver::GS';
use Encode ();                    # label text -> UTF-8 bytes (_send_3d_frame)


use PDL;
use PDL::Basic qw(sequence);
use PDL::Primitive;               # indadd (vertex-normal accumulation for Gouraud)
use PDL::Graphics::Cairo::Mesh3D qw(
    detect_face_base face_normal lambert shade_color scanline_spans
    bbox_offscreen nearest_index_2d
);   # 面描画の幾何コア(PDL 非依存・headless 検証済み)
use PDL::Graphics::Cairo::SceneExport ();   # 表示中シーンの .obj/.usda 書き出し(独立・PDL 非依存の書式コア)
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
    # 逆チャネル(サーバ→クライアント)。3D 窓の menu「Export OBJ/USDA」で
    # 送られる。ペイロードは format 1 バイト(0=obj, 1=usda)。gsp_3d.h と一致。
    GSP_MSG_3D_EXPORT => 0x28,

    # 親 Driver::GS と同値の逆チャネル通知(サーバ→クライアント)。3D 窓でも
    # サーバはこれらを送っているが従来 _recv_ack_3d が読み捨てていた。無改変で活用:
    GSP_MSG_RESIZE   => 0x16,   # 窓リサイズ (w,h uint32) → width/height 更新で再センタリング
    GSP_MSG_PICK     => 0x19,   # クリック (fx,fy 画像比率, btn) → 頂点 pick に使う
    GSP_MSG_CURSOR   => 0x18,   # カーソル移動(未使用、将来のホバー表示用)

    # 段階 B(giza-server viewer/gsp_3d.h が正本): メッシュを 1 回送り、以後は視点・色・
    # 重ねものだけ。サーバが回し、描き、クリックとカーソルの下の頂点の番号を返す。
    GSP_MSG_3D_MESH    => 0x29,   # → サーバ、ACK
    GSP_MSG_3D_COLORS  => 0x2A,   # → サーバ、ACK
    GSP_MSG_3D_VIEW    => 0x2B,   # → サーバ、ACK なし(33 バイト)
    GSP_MSG_3D_OVERLAY => 0x2C,   # → サーバ、ACK
    GSP_MSG_3D_POSE    => 0x2D,   # サーバ →(VIEW と同じ 33 バイト)
    GSP_MSG_3D_PICKV   => 0x2E,   # サーバ →(14 バイト)
    GSP_MSG_3D_HOVERV  => 0x2F,   # サーバ →(13 バイト)
    GSP_CAP_3D_SCENE   => 0x01,   # 中身 u32 = 1 の PING への PONG の機能のビット
    GSP_MESH_NORMALS   => 0x01,
    GSP_MESH_WINDING_CW => 0x04,
    GSP_NO_VERTEX      => 0xFFFFFFFF,
    GSP_OVL_SCREEN     => 0x01,   # 3D_OVERLAY の flags: 画面の画素(投影しない)
    GSP_OVL_ON_TOP     => 0x02,   #   メッシュに隠されない
    GSP_OVL_ARROW      => 0x04,   #   線: p1 に矢じり
    GSP_OVL_BAND       => 0x08,   #   線: 高さ width の帯(カラーバーの行)

    NEWWIN_FLAG_3D   => 0x01,   # NEWWINペイロードに乗せる3Dモードフラグ（TODO: クライアント側対応）

    AXIS_LEN         => 100,
    DEFAULT_ZOOM     => 1.0,
    FOV              => 600,

    # REVIEW NOTE (2026-06-21, トラックボール回転): ドラッグ1pxあたりの
    # 回転角(radian)。0.01相当(旧theta/phiの感度と揃えた値)。大きいほど
    # 同じドラッグ量でより大きく回転する。
    DRAG_SENSITIVITY => 0.01,

    # REVIEW NOTE (2026-06-23 / 2026-07-12 実機確定):
    # 縦ドラッグを world-X 軸回転に変換するときの符号。+1 で両OS確定。
    # 注意: ワイヤ上の dy は「上が正」を正とする(Cocoa の isFlipped=NO 由来)。
    # X11 の画面 y は下が正なので、Xlib ビューア側(giza-server-xlib.c の
    # MotionNotify)で反転して規約を揃えてある。縦ドラッグが片方の OS だけ
    # 逆になった場合、この定数ではなくクライアント側の符号規約を疑うこと
    # (ここを触ると片方を直した瞬間に他方が壊れる)。
    DRAG_DY_SIGN     => +1,

    # REVIEW NOTE (2026-06-23 キラリティ修正 / 2026-07-12 実機確定):
    # _project で screen-x を反転(cx - x)しているため、world-Y 軸まわりの
    # 回転が画面上では逆向きに見える。Mac(Cocoa)・Ubuntu(Xlib)の両方で
    # 横ドラッグが直感と逆であることを確認し、-1 に確定。回転計算自体は
    # 正しく、投影の X 反転と符号を合わせるためのノブ。
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

    # REVIEW NOTE (2026-07-23, adaptive LOD): ドラッグ(回転/ズーム)中は
    # 粗メッシュ(coarse LOD)で軽く回し、操作が IDLE_SEC 秒止まったら
    # 高精細メッシュ(fine LOD)に一度だけ差し替える(progressive refinement)。
    # run() は元々 60fps で常時再描画するので、_send_3d_frame の前に
    # scene->{mesh} を差し替えるだけで成立する(select タイムアウト不要)。
    # 回転の体感速度は coarse で、静止画の精細さは fine で決まる=グルグルの
    # 速度を落とさずに止めた瞬間だけ精緻化される。lod は new(lod=>{...}) で有効化。
    IDLE_SEC => 0.15,

    # 段階 B の再生(play)でコマを進める間隔の上限(秒)。サーバの画面更新 120 Hz に合わせる。
    PLAY_INTERVAL => 1.0 / 120,
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
    $self->{on_pick}     = $args{on_pick};   # クリック pick 時: ($vertex_index,$x,$y,$z) を受ける
    $self->{on_hover}    = $args{on_hover};   # カーソル移動時: ($vertex_index,$x,$y,$z)→表示文字列を返す
    $self->{seeds}       = [];               # multi-seed: pick した頂点のリスト(EMSE 的なシード群)
    $self->{readout}     = undef;            # カーソル下の x,y,z + area 名(右上表示)
    $self->{_cursor}     = undef;            # 直近カーソル(fx,fy)

    # fill span を「高さ=step の帯(filled bar)」で描くと、拡大時の横縞
    # (step>1 の行間隙間)が消える。既定 on。giza-server が frame flag 0x04 を
    # 解さない旧版なら 1px stroke に落ちるだけ(前方・後方互換)。thick_fill=>0 で無効。
    $self->{thick_fill} = defined $args{thick_fill} ? $args{thick_fill} : 1;

    # 描画モード: 'line'(既定=スキャンライン線塗り, fail-safe) | 'zbuffer'(三角
    # ラスタライザ + Gouraud + z バッファ = 脳溝の遮蔽が正確・襞が滑らか)。
    # 実行時に切替可能。zbuffer は giza-server が三角セクション(flags 0x08)を
    # 解する新版のときだけ面が出る。旧版なら面は出ないが破綻しない(後方互換)。
    $self->{render} = $args{render} // 'line';

    # 段階: 'auto'(既定。サーバが段階 B に対応し、scene に mesh があれば B)| 'A' | 'B'。
    # 環境変数 GS3D_STAGE=A は何を渡しても段階 A に固定する(比べるとき・切り分け用)。
    # B を指定してもサーバが対応していなければ、警告して A で動く。
    $self->{stage} = uc($args{stage} // 'auto');
    die "Driver::GS3D: stage must be 'auto', 'A' or 'B'\n"
        unless $self->{stage} =~ /\A(?:AUTO|A|B)\z/;

    # シーン中心(pivot): 位置回転時にここを原点へ移す=脳を画面中心に置き、回転軸も
    # 脳の中心にする。demo が mesh 重心を渡す。既定 undef=原点(従来動作)。[N,3] に
    # ブロードキャストするため [1,3] で保持。
    $self->{_pivot} = (defined $args{pivot} && ref $args{pivot})
        ? pdl($args{pivot})->dummy(0)     # [3] -> [1,3]
        : undef;

    # 段階 B の重ねもの: 電極の点・ラベル、scene の lines、シードを、メッシュの裏に回ったら
    # 隠す(overlay_depth => 0 で段階 A と同じく常に手前)。overlay_eps(mm)は、メッシュの
    # 面からこの距離までの手前・奥を隠さない幅(頭皮にスナップした電極、頂点上のシード)。
    $self->{overlay_depth} = $args{overlay_depth} // 1;
    $self->{overlay_eps}   = $args{overlay_eps}   // 2.0;

    # --- adaptive LOD (progressive refinement) ---------------------------
    # lod => { coarse => \%mesh, fine => \%mesh } を渡すと、run() が
    # ドラッグ中は coarse、操作が IDLE_SEC 止まったら fine に差し替える。
    # 既定表示(idle)は fine。pick/hover は常に fine に対して解決する
    # (run/_pick_at_screen 参照)ので、pick の頂点 index は fine メッシュ
    # 基準で一意になり、呼び出し側の in_from(ローカル→75K 対応)と噛み合う。
    if ($args{lod}) {
        $self->{_lod}         = $args{lod};
        $self->{_lod_state}   = 'fine';
        $self->{_last_motion} = 0;
        $self->{scene}{mesh}  = $args{lod}{fine};   # idle の見た目を既定に
    }

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
    my ($self, $rot, $pts_n3) = @_;       # $pts_n3: [N,3] 位置
    # pivot(シーン重心)を原点へ移してから回転する。これで脳の中心を軸に回り、
    # 投影も脳を画面中心に置く(電極は co-registered なので一緒に動き頭皮に載る)。
    # 真の MNI 座標は _hover/_pick が生 verts を直読するので不変。方向ベクトル
    # (法線)は平行移動できないので _rotate_dirs を使うこと。
    my $pv = $self->{_pivot};
    $pts_n3 = $pts_n3 - $pv if defined $pv;
    return $rot x $pts_n3;                 # [N,3] そのまま、転置不要
}

# 方向ベクトル(法線等)の回転。pivot は引かない(平行移動しない)。
sub _rotate_dirs {
    my ($self, $rot, $vecs_n3) = @_;
    return $rot x $vecs_n3;
}

# ============================================================
# 面(三角メッシュ)→ 線分レコード列(P:EEG18)
#
# z バッファの無い giza-server で面を出すためのソフトウェアパイプライン。
# 面を「水平スキャンラインの束(=線分プリミティブ)」に落とすことで、
# ワイヤプロトコル(GSP_MSG_3D_FRAME の線分レコード)も giza-server 側の
# ラスタライザも一切触らずに solid + flat-Lambert 陰影を実現する。
#
# 手順: 頂点回転(PDL)→ 投影(_project)→ 面ごとに
#        バックフェースカリング(回転後法線の z 符号)
#        → 面デプス(回転後 z 平均)で画家ソート(奥→手前)
#        → view 空間光で flat Lambert → スキャンライン塗り。
#
# 返り値: @lines_data 互換の hashref 列(x0,y0,x1,y1,depth,rgba)。
#         呼び出し側(_send_3d_frame)がこれを軸より前(=奥)に unshift する。
#
# 罠(申し送りより): 凸(頭皮)は綺麗、凹(皮質)は面ソートで自己遮蔽が壊れる。
#                    大規模メッシュ(75K)は u16 線分上限のため fill_step で間引く
#                    (間引くと横縞が出る=向き確認用途向け。厳密遮蔽は Blender)。
# ============================================================
use constant _MESH_FILL_BUDGET => 60000;   # u16(65535)から軸/枠の余白を引いた塗り線分の上限

sub _mesh_lines {
    my ($self, $rot) = @_;
    my $m = $self->{scene}{mesh} or return [];
    my $verts = $m->{verts} // die "scene.mesh.verts required\n";
    my $faces = $m->{faces} // die "scene.mesh.faces required\n";

    my $base_rgb = $m->{color}   // [0.85, 0.78, 0.70];   # 暖色グレー(頭皮っぽく)
    my $light    = $m->{light}   // [0.3, 0.4, 1.0];      # view 空間: 前上右から
    my $ambient  = defined $m->{ambient} ? $m->{ambient} : 0.25;
    my $alpha    = defined $m->{alpha}   ? $m->{alpha}   : 255;
    my $step     = $m->{fill_step} && $m->{fill_step} > 0 ? $m->{fill_step} : 1;
    my $per_face = $m->{colors};                          # PDL [Nf,3] または undef

    # ---- 回転 + 投影(バッチは PDL、以降はスカラーで回す)----
    my $rv = $self->_rotate_points($rot, $verts);         # [Nv,3] 回転後 3D
    my ($sxp, $syp, $dzp) = $self->_project($rv);         # 投影後スクリーン + depth(=回転後 z)
    my @SX = $sxp->list; my @SY = $syp->list;
    my @RX = $rv->slice(',(0)')->list;
    my @RY = $rv->slice(',(1)')->list;
    my @RZ = $rv->slice(',(2)')->list;                    # 法線 z・面デプス用

    # ---- 面 index を Perl 配列へ。0/1-based 自動判定 ----
    my @I0 = $faces->slice(',(0)')->list;
    my @I1 = $faces->slice(',(1)')->list;
    my @I2 = $faces->slice(',(2)')->list;
    my $nf = scalar @I0;
    my $fmin = $faces->min;
    my $fbase = detect_face_base($fmin);
    if ($fbase) { $_-- for (@I0, @I1, @I2); }             # 1-based → 0-based

    # ---- 外向きワインディング符号(回転不変なので原座標で 1 回だけ決めてキャッシュ)----
    my $wind = $m->{winding} // 'auto';
    my $wsign;
    if    ($wind eq 'ccw') { $wsign = +1; }
    elsif ($wind eq 'cw')  { $wsign = -1; }
    else {                                                # auto: 法線が重心から外向きか多数決
        $wsign = $self->{_mesh_wsign};
        unless (defined $wsign) {
            my @VX = $verts->slice(',(0)')->list;
            my @VY = $verts->slice(',(1)')->list;
            my @VZ = $verts->slice(',(2)')->list;
            my $nv = scalar @VX;
            my ($cx,$cy,$cz) = (0,0,0);
            $cx += $_ for @VX; $cy += $_ for @VY; $cz += $_ for @VZ;
            $cx/=$nv; $cy/=$nv; $cz/=$nv;
            my $acc = 0;
            for my $f (0 .. $nf-1) {
                my ($a,$b,$c) = ($I0[$f],$I1[$f],$I2[$f]);
                my ($nx,$ny,$nz) = face_normal(
                    [$VX[$a],$VY[$a],$VZ[$a]],
                    [$VX[$b],$VY[$b],$VZ[$b]],
                    [$VX[$c],$VY[$c],$VZ[$c]]);
                my ($fx,$fy,$fz) = (($VX[$a]+$VX[$b]+$VX[$c])/3 - $cx,
                                    ($VY[$a]+$VY[$b]+$VY[$c])/3 - $cy,
                                    ($VZ[$a]+$VZ[$b]+$VZ[$c])/3 - $cz);
                my $dot = $nx*$fx + $ny*$fy + $nz*$fz;     # >0 なら法線が外向き
                $acc += ($dot >= 0 ? 1 : -1);
            }
            $wsign = ($acc >= 0) ? +1 : -1;               # 多数が外向きなら +1、逆なら反転
            $self->{_mesh_wsign} = $wsign;
        }
    }

    # ---- 面ごと: カリング → デプス → 陰影。front かつ画面内だけ集める ----
    my $W = $self->width;
    my $H = $self->height;
    my @vis = (0) x scalar(@SX);     # pick 用: front 面に属する頂点を可視とマーク
    my @front;   # [depth, [SXa,SXb,SXc],[SYa,SYb,SYc], rgba]
    for my $f (0 .. $nf-1) {
        my ($a,$b,$c) = ($I0[$f],$I1[$f],$I2[$f]);
        # バックフェースカリング: 回転後法線 z(× winding 符号)がカメラ(+Z)向きか
        my ($nx,$ny,$nz) = face_normal(
            [$RX[$a],$RY[$a],$RZ[$a]],
            [$RX[$b],$RY[$b],$RZ[$b]],
            [$RX[$c],$RY[$c],$RZ[$c]]);
        next unless $nz * $wsign > 0;                     # 裏面は捨てる

        my $fsx = [$SX[$a],$SX[$b],$SX[$c]];
        my $fsy = [$SY[$a],$SY[$b],$SY[$c]];
        # ビューポートカリング: 画面外の面はスキャンライン化しない(強拡大で本数が
        # 爆発して縞になるのを防ぐ。可視ピクセルだけ塗れば予算に収まり step=1 を保てる)
        next if bbox_offscreen($fsx, $fsy, $W, $H);
        $vis[$a] = $vis[$b] = $vis[$c] = 1;               # 可視頂点(pick 候補)

        my $depth = ($RZ[$a] + $RZ[$b] + $RZ[$c]) / 3;    # 画家ソート用(回転後 z)

        # flat Lambert(法線は front 向きに揃えてから)
        my $I = lambert($nx*$wsign, $ny*$wsign, $nz*$wsign,
                        $light->[0], $light->[1], $light->[2], $ambient);
        my $rgb = $base_rgb;
        if (defined $per_face) {
            $rgb = [ $per_face->at($f,0), $per_face->at($f,1), $per_face->at($f,2) ];
        }
        my $rgba = shade_color($rgb, $I, $alpha);

        push @front, [ $depth, $fsx, $fsy, $rgba ];
    }
    # pick(クリック)用に投影と可視マスクを保存(piddle。_nearest_visible が読む)。次フレームまで有効。
    $self->{_mesh_proj} = { sx => $sxp, sy => $syp, vis => pdl(byte, \@vis) };
    return [] unless @front;

    # 画家ソート: depth 昇順(奥→手前)
    @front = sort { $a->[0] <=> $b->[0] } @front;

    # ---- スキャンライン塗り。総本数が u16 予算超なら step を自動で上げる ----
    # 概算は各 front 面の投影高さ合計だが、ビューポートに収まる分だけ数える
    # (画面外の巨大面を数えて過剰間引きするのを防ぐ)。
    my $est = 0;
    for my $t (@front) {
        my $sy = $t->[2];
        my ($lo,$hi) = ($sy->[0],$sy->[0]);
        for my $i (1,2) { $lo=$sy->[$i] if $sy->[$i]<$lo; $hi=$sy->[$i] if $sy->[$i]>$hi; }
        $lo = 0    if $lo < 0;                            # 縦クリップして概算
        $hi = $H   if $hi > $H;
        $est += int(($hi-$lo)/$step) + 1 if $hi > $lo;
    }
    if ($est > _MESH_FILL_BUDGET) {
        my $scale = $est / _MESH_FILL_BUDGET;
        $step *= $scale;                                  # 間引き(横縞が出るが上限は守る)
        unless ($self->{_budget_warned}) {                # スパム防止: 初回のみ告知
            warn sprintf("Driver::GS3D: on-screen mesh fill can exceed budget %d at high zoom ".
                         "(e.g. ~%d lines, step=%.2f). Minor striping; fundamental to painter's ".
                         "fill without a z-buffer. (Further occurrences suppressed.)\n",
                         _MESH_FILL_BUDGET, $est, $step);
            $self->{_budget_warned} = 1;
        }
    }

    # 初回のみ、面塗りの負荷を報告(PDLCAIRO_DEBUG=1)。
    if ($self->verbose && !$self->{_mesh_diag_done}) {
        printf STDERR "[GS3D mesh] front=%d/%d faces on-screen, ~%d fill-lines/frame, step=%.2f, view=%dx%d\n",
            scalar(@front), $nf, $est, $step, $W, $H;
        $self->{_mesh_diag_done} = 1;
    }

    # fill 帯の高さ = ceil(step)。step>1 でも行間に隙間を残さない(拡大時の横縞対策)。
    # _send_3d_frame が thick_fill 時にこの w をワイヤの depth スロットへ載せ、
    # giza-server が frame flag 0x04 で「高さ w の filled bar」として塗る。
    my $fillw = ($step <= 1) ? 1 : int($step + 0.9999);

    my @out;
    for my $t (@front) {
        my ($depth, $sx, $sy, $rgba) = @$t;
        for my $span (scanline_spans($sx, $sy, $step, $W, $H)) {   # ビューポートにクリップ
            my ($y, $xL, $xR) = @$span;
            push @out, {
                x0 => $xL, y0 => $y,
                x1 => $xR, y1 => $y,
                depth => $depth,
                w     => $fillw,
                rgba  => $rgba,
            };
        }
    }
    return \@out;
}

# カーソル下の可視頂点の x,y,z(+ on_hover が返す area 名)を右上表示用にまとめる。
sub _hover_readout {
    my ($self, $px, $py) = @_;
    my $proj = $self->{_mesh_proj} or return;
    my ($idx, $dist) = _nearest_visible($proj, $px, $py);
    $self->_readout_vertex($idx);
}

# readout の文字列を頂点の番号から作る(段階 A は最近傍の可視頂点、段階 B は 3D_HOVERV の番号)。
# $idx < 0 なら readout を消す。
sub _readout_vertex {
    my ($self, $idx) = @_;
    if ($idx < 0) { $self->{readout} = undef; return; }
    my $verts = $self->{scene}{mesh}{verts};
    my ($x, $y, $z) = ($verts->at($idx,0), $verts->at($idx,1), $verts->at($idx,2));
    my $area = $self->{on_hover} ? $self->{on_hover}->($idx, $x, $y, $z) : undef;
    $self->{readout} = sprintf('x=%.1f y=%.1f z=%.1f%s',
        $x, $y, $z, (defined $area && length $area) ? "  $area" : '');
}

# ============================================================
# 頂点 pick: スクリーン座標 (px,py) に最も近い可視メッシュ頂点を選ぶ。
#
# giza-server の 3D 窓がクリック(移動<3px)を GSP_MSG_PICK(fx,fy 画像比率)で
# 送ってくる。run() が fx*width, fy*height に変換して本メソッドを呼ぶ。直近フレーム
# の投影 _mesh_proj(可視頂点マスク付き)に対し最近傍を取り、front-facing のみを候補
# にするので裏側の頂点は選ばれない。選択頂点は緑ハイライト+on_pick コールバック。
# ============================================================
sub _pick_at_screen {
    my ($self, $px, $py) = @_;
    my $proj = $self->{_mesh_proj} or return;      # まだ 1 フレームも描いてない
    my ($idx, $dist) = _nearest_visible($proj, $px, $py);
    return if $idx < 0;                            # 可視頂点が無い
    $self->_add_seed($idx, $dist);
}

# シードを 1 つ足す(on_pick を呼び、ラベルを決める)。段階 A は _pick_at_screen から、
# 段階 B は 3D_PICKV の頂点の番号で呼ぶ。$dist は表示用(段階 B は undef)。
sub _add_seed {
    my ($self, $idx, $dist) = @_;
    my $verts = $self->{scene}{mesh}{verts};
    my ($x, $y, $z) = ($verts->at($idx,0), $verts->at($idx,1), $verts->at($idx,2));

    # on_pick は解剖ラベル等の文字列を返せる(返り値をシード表示ラベルに使う)。
    # 第5引数 = これで何個目のシードになるか(0-based)。
    my $n = scalar @{ $self->{seeds} };
    my $ret = $self->{on_pick} ? $self->{on_pick}->($idx, $x, $y, $z, $n) : undef;
    my $label = (defined $ret && !ref $ret) ? $ret : sprintf('v%d', $idx);

    push @{ $self->{seeds} }, { index => $idx, x => $x, y => $y, z => $z, label => $label };

    printf STDERR "[GS3D pick] seed %d: vertex %d @ (%.1f, %.1f, %.1f) mm  [%s]%s\n",
        $n + 1, $idx, $x, $y, $z, $label, defined $dist ? sprintf('  (%.1f px)', $dist) : '';
}

# ============================================================
# 右クリック解除: スクリーン座標 (px,py) に最も近い seed マークを1つ削除。
# 既存 seed の (x,y,z) を現在の回転で投影して最近傍を選ぶ(_pick_at_screen の
# ように mesh 投影 _mesh_proj は使わない=LOD 非依存)。許容半径内に seed が
# 無ければ何もしない(誤って遠い seed を消さない)。マーカ表示サイズが zoom*7
# なので許容半径は zoom*12。削除時は on_seed_removed コールバックを呼ぶ(任意)。
# ============================================================
sub _unpick_at_screen {
    my ($self, $px, $py) = @_;
    my $seeds = $self->{seeds};
    return unless $seeds && @$seeds;

    my $rot = $self->_rotation();
    my ($best, $bestd2) = (-1, 1e18);
    for my $i (0 .. $#$seeds) {
        my $sd = $seeds->[$i];
        my $rp = $self->_rotate_points($rot, pdl([[$sd->{x}], [$sd->{y}], [$sd->{z}]]));
        my ($sx, $sy) = $self->_project($rp);
        my $dx = $sx->at(0) - $px;
        my $dy = $sy->at(0) - $py;
        my $d2 = $dx*$dx + $dy*$dy;
        ($best, $bestd2) = ($i, $d2) if $d2 < $bestd2;
    }

    my $tol = ($self->{zoom} // 1) * 12;           # クリック許容半径(px)
    if ($best >= 0 && $bestd2 <= $tol*$tol) {
        my $rm = splice(@$seeds, $best, 1);
        printf STDERR "[GS3D pick] remove seed (was vertex %d @ %.1f,%.1f,%.1f) — %d left\n",
            $rm->{index}, $rm->{x}, $rm->{y}, $rm->{z}, scalar @$seeds;
        $self->{on_seed_removed}->($rm) if $self->{on_seed_removed};
    } else {
        printf STDERR "[GS3D pick] right-click: no seed within %.0f px (nearest %.0f px)\n",
            $tol, sqrt($bestd2);
    }
}

# ============================================================
# フレームをGSPで送信
# ============================================================
# ============================================================
# 頂点法線(Gouraud 用)。面法線を各頂点へ indadd で集約し正規化、重心外向きに
# 全体符号を合わせる(winding 非依存で表が明・裏が暗)。原座標で1回だけ計算し
# メッシュ hashref にキャッシュ($m->{_vnorm})。LOD で別メッシュに切り替わっても
# 各メッシュが自分の法線を持つので取り違えない。
# ============================================================
sub _compute_vnormals {
    my ($verts, $faces) = @_;                 # [Nv,3], [Nf,3]
    my $Nv = $verts->dim(0);
    my $fb = detect_face_base($faces->min);
    my $F  = $fb ? ($faces - $fb) : $faces;   # 0-based
    my $a  = $F->slice(',(0)')->flat->long;
    my $b  = $F->slice(',(1)')->flat->long;
    my $c  = $F->slice(',(2)')->flat->long;
    my $Va = $verts->dice_axis(0,$a);
    my $e1 = $verts->dice_axis(0,$b) - $Va;
    my $e2 = $verts->dice_axis(0,$c) - $Va;
    my ($e1x,$e1y,$e1z) = ($e1->slice(',(0)'),$e1->slice(',(1)'),$e1->slice(',(2)'));
    my ($e2x,$e2y,$e2z) = ($e2->slice(',(0)'),$e2->slice(',(1)'),$e2->slice(',(2)'));
    my $fn = cat($e1y*$e2z-$e1z*$e2y, $e1z*$e2x-$e1x*$e2z, $e1x*$e2y-$e1y*$e2x);   # [Nf,3]
    my @vn;
    for my $k (0..2) {
        my $acc = zeroes($Nv); my $fk = $fn->slice(",($k)")->sever;
        indadd($fk,$a,$acc); indadd($fk,$b,$acc); indadd($fk,$c,$acc);
        push @vn, $acc;
    }
    my $vn  = cat(@vn);                         # [Nv,3]
    my $len = sqrt(($vn*$vn)->slice(',(0)')+($vn*$vn)->slice(',(1)')+($vn*$vn)->slice(',(2)'));
    $vn = $vn / ($len->dummy(1) + 1e-12);
    my $rad = $verts - $verts->average->dummy(0);
    my $al  = $vn->slice(',(0)')*$rad->slice(',(0)')
            + $vn->slice(',(1)')*$rad->slice(',(1)')
            + $vn->slice(',(2)')*$rad->slice(',(2)');
    return $vn * (($al->avg < 0) ? -1 : 1);     # 外向きに揃える
}

# ============================================================
# 面(三角メッシュ)→ 三角レコード列(z-buffer 描画, P:EEG18 案③)。
#
# _mesh_lines のスキャンライン化の代わりに面を投影三角形として送り、giza-server
# 側の z バッファ・ラスタライザが Gouraud 補間で塗る。これで (1)脳溝の遮蔽が
# z バッファで正確、(2)頂点法線 Gouraud で襞が滑らか、(3)線分でないので横縞が
# 原理的に出ない。頂点色 = 頂点法線を view 空間へ回転 → Lambert(I=ambient+
# (1-ambient)*max(0,N.L)) → albedo(mesh->{vcolors} があれば頂点ごと, 無ければ
# base 単色) × I。返り値 = { n => 三角形の数, xyz => (3 [x,y,z], 3 頂点, n) double,
# rgb => (3 [r,g,b], 3 頂点, n) byte }(z 大きいほど手前。n が 0 なら xyz・rgb は無い)。
# _pack_tris_pdl がこれを詰める。すべて PDL の演算で、面ごとの Perl のループは無い。
# backface/viewport カリングは _mesh_lines と同じ(閉曲面なので安全, z バッファが
# 残りの重なりを正しく解決)。pick 用に _mesh_proj(sx・sy・vis の piddle)も保存。
# ============================================================
sub _mesh_tris {
    my ($self, $rot) = @_;
    my $m = $self->{scene}{mesh} or return { n => 0 };
    my $verts = $m->{verts} // die "scene.mesh.verts required\n";
    my $faces = $m->{faces} // die "scene.mesh.faces required\n";

    my $base_rgb = $m->{color}   // [0.85, 0.78, 0.70];
    my $light    = $m->{light}   // [0.3, 0.4, 1.0];
    my $ambient  = defined $m->{ambient} ? $m->{ambient} : 0.25;
    my $vcolors  = $m->{vcolors};                        # 頂点ごと albedo [Nv,3] or undef

    my $rv = $self->_rotate_points($rot, $verts);
    my ($sx, $sy, $dz) = $self->_project($rv);

    my ($fi, $wsign) = _mesh_faces_wsign($m);

    # 頂点法線(キャッシュ)→ view 空間 → Gouraud Lambert → 頂点色 u8
    my $vn  = $m->{_vnorm} //= _compute_vnormals($verts, $faces);   # [Nv,3] 外向き unit
    my $vnr = $self->_rotate_dirs($rot, $vn);                      # [Nv,3] view 空間(方向=pivot 引かない)
    my $L   = pdl($light); $L = $L / (sqrt(($L*$L)->sum) + 1e-12);
    my $nl  = $vnr->slice(',(0)')*$L->at(0) + $vnr->slice(',(1)')*$L->at(1) + $vnr->slice(',(2)')*$L->at(2);
    my $I   = $ambient + (1-$ambient) * $nl->clip(0,1);             # [Nv]
    my $alb = defined $vcolors ? $vcolors : pdl($base_rgb)->dummy(0);
    my $col = (($I->dummy(1) * $alb)->clip(0,1) * 255)->byte;       # [Nv,3]

    # 面ごと: backface/viewport カリング。面法線は回転後の z 成分だけ要る
    # (Mesh3D::face_normal の z と同じ式)。画面外は 3 頂点の外接矩形で判定
    # (Mesh3D::bbox_offscreen と同じ)。
    my ($rx, $ry) = ($rv->slice(',(0)'), $rv->slice(',(1)'));
    my @fx = map { $rx->index($_) } @$fi;
    my @fy = map { $ry->index($_) } @$fi;
    my $nz = ($fx[1] - $fx[0]) * ($fy[2] - $fy[0]) - ($fy[1] - $fy[0]) * ($fx[2] - $fx[0]);
    my $fsx = cat(map { $sx->index($_) } @$fi)->mv(1, 0);          # (3,Nf)
    my $fsy = cat(map { $sy->index($_) } @$fi)->mv(1, 0);
    my ($W, $H) = ($self->width, $self->height);
    my $off = ($fsx->maximum < 0) | ($fsx->minimum > $W) | ($fsy->maximum < 0) | ($fsy->minimum > $H);
    my $sel = which(($nz * $wsign > 0) & !$off);                   # 残る面の番号(昇順)
    my @vi  = map { $_->index($sel) } @$fi;                        # 残る面の頂点 (n) ×3

    # pick / hover 用: 投影と可視頂点の印(残った面の頂点)。次フレームまで有効
    my $vis = zeroes(byte, $sx->nelem);
    $vis->index($_) .= 1 for @vi;
    $self->{_mesh_proj} = { sx => $sx, sy => $sy, vis => $vis };

    my $n = $sel->nelem;
    return { n => 0 } unless $n;
    # 三角形の頂点: 座標 (3 [x,y,z], 3 頂点, n) と色 (3 [r,g,b], 3 頂点, n)。
    # 頂点ごとに 1 枚ずつ代入する(内側の次元を mv で並べ替えるより速い。pdl-perl.md)
    my $xyz = zeroes(double, 3, 3, $n);
    my $rgb = zeroes(byte, 3, 3, $n);
    my $ct  = $col->transpose;                                     # (3,Nv)
    for my $k (0 .. 2) {                                           # 三角形の 3 頂点(外側のループ)
        my $v = $vi[$k];
        $xyz->slice(":,($k),:") .= cat($sx->index($v), $sy->index($v), $dz->index($v))->transpose;
        $rgb->slice(":,($k),:") .= $ct->dice_axis(1, $v);
    }
    return { n => $n, xyz => $xyz, rgb => $rgb };
}

# 面の頂点番号(0 始まり、(Nf) を 3 本)と外向きの winding 符号(+1 / −1)。メッシュごとに
# キャッシュする($m->{_face_idx}・$m->{_wsign})。_mesh_tris と段階 B の 3D_MESH が使う。
sub _mesh_faces_wsign {
    my ($m) = @_;
    my $faces = $m->{faces} // die "scene.mesh.faces required\n";
    my $fi = $m->{_face_idx} //= do {
        my $F = $faces->long;
        $F = $F - 1 if detect_face_base($faces->min);
        [ map { $F->slice(",($_)")->copy } 0 .. 2 ];
    };
    my $wsign = $m->{_wsign} //= do {
        my $wind = $m->{winding} // 'auto';
        $wind eq 'ccw' ? +1 : $wind eq 'cw' ? -1 : _winding_sign($m->{verts}, $fi);
    };
    return ($fi, $wsign);
}

# 外向きの winding 符号: 面法線と(面の重心 − 全頂点の重心)の内積の符号の多数決。
# $fi は面の頂点番号(0 始まり)の (Nf) ×3。
sub _winding_sign {
    my ($verts, $fi) = @_;
    my @p  = map { $verts->dice_axis(0, $_) } @$fi;                # (Nf,3) ×3
    my ($u, $w) = ($p[1] - $p[0], $p[2] - $p[0]);
    my @n = map {
        my ($i, $j) = (($_ + 1) % 3, ($_ + 2) % 3);
        $u->slice(",($i)") * $w->slice(",($j)") - $u->slice(",($j)") * $w->slice(",($i)")
    } 0 .. 2;
    my $cg  = $verts->average;                                     # (3) 全頂点の重心
    my $fc  = ($p[0] + $p[1] + $p[2]) / 3 - $cg->dummy(0);         # (Nf,3)
    my $dot = $n[0] * $fc->slice(',(0)') + $n[1] * $fc->slice(',(1)') + $n[2] * $fc->slice(',(2)');
    my $acc = (($dot >= 0) * 2 - 1)->sum;
    return $acc >= 0 ? +1 : -1;
}

# 直近フレームの投影 _mesh_proj に対し、(px,py) に最も近い可視頂点を返す: ($index, $dist)。
# 可視頂点が無ければ (-1, undef)。距離が同じなら番号の小さい方(Mesh3D::nearest_index_2d と同じ)。
sub _nearest_visible {
    my ($proj, $px, $py) = @_;
    my $cand = which($proj->{vis});
    return (-1, undef) unless $cand->nelem;
    my $d2 = ($proj->{sx}->index($cand) - $px)**2 + ($proj->{sy}->index($cand) - $py)**2;
    my $k  = $d2->minimum_ind->sclr;
    return ($cand->at($k), sqrt($d2->at($k)));
}

# 三角セクションのバイト列: n_tris(u16) と三角形(頂点 x,y,z(f32) r,g,b(u8) × 3)。
# n_tris は u16 なので、65535 を超えたら奥の三角形から捨てて 65535 にする(1 回警告)。
# 深度は大きいほど手前。捨てるのは 3 頂点の深度の和が小さいもの(手前の面に隠れて
# いることが多い)。超えたまま送ると数が折り返し、サーバが三角形を読み違える。
# _pack_tris は三角形の配列([ [x,y,z,r,g,b]×3 ], ...)を受け、_pack_tris_pdl に渡す。
my $_warned_tris;
sub _pack_tris {
    my ($tris) = @_;
    return pack('S', 0) unless @$tris;
    my $p = pdl(double, $tris);                                    # (6, 3, n)
    return _pack_tris_pdl($p->slice('0:2'), $p->slice('3:5')->byte);
}

# $xyz: (3 [x,y,z], 3 頂点, n)、$rgb: (3 [r,g,b], 3 頂点, n) byte。
# 1 頂点 15 バイト(f32 ×3 + u8 ×3)の (15, 3, n) の byte の piddle に詰めて、一度に取り出す。
sub _pack_tris_pdl {
    my ($xyz, $rgb) = @_;
    my $n = $xyz->dim(2);
    if ($n > 65535) {
        warn sprintf("Driver::GS3D: %d triangles exceed the u16 count; drawing the 65535 nearest.\n",
                     $n) unless $_warned_tris++;
        # 深度の和の大きい順、同じなら番号の小さい順で 65535 個を選び、元の順に戻す
        my $depth = $xyz->slice('(2),:,:')->double->sumover;       # (n)
        my $ord   = qsortveci(cat(-$depth, sequence(double, $n))->transpose);
        my $keep  = $ord->slice('0:65534')->qsort;
        ($xyz, $rgb, $n) = ($xyz->dice_axis(2, $keep), $rgb->dice_axis(2, $keep), 65535);
    }
    return pack('S', 0) unless $n;
    my $xf = $xyz->float->copy;                                    # (3,3,n) f32、実体
    $xf->bswap4 if pack('L', 1) ne pack('V', 1);                   # ワイヤはリトルエンディアン
    my $fb = zeroes(byte, 12, 3, $n);                              # f32 の中身をそのままバイトに
    ${ $fb->get_dataref } = ${ $xf->get_dataref };
    $fb->upd_data;
    my $rec = zeroes(byte, 15, 3, $n);
    $rec->slice('0:11')  .= $fb;
    $rec->slice('12:14') .= $rgb;
    return pack('S', $n) . ${ $rec->get_dataref };
}

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

    # ---- 再生中の潜時(左下)----
    if (defined(my $pl = $self->_play_label)) {
        push @label_recs, { x => 12, y => $self->height - 14, rgb => [235, 235, 245], text => $pl };
    }

    # ---- hover readout: カーソル下の x,y,z + area 名を隅に表示 ----
    if (defined $self->{readout}) {
        push @label_recs, {
            x => 12, y => 20,                 # 左上(長い文字列でも切れにくい)
            rgb => [235, 235, 245],
            text => $self->{readout},
        };
    }

    # ---- multi-seed ハイライト: pick した各頂点を色分けで表示(最前面)----
    if (@{ $self->{seeds} }) {
        # シードを見分けやすい配色(緑・橙・シアン・マゼンタ・黄…を循環)
        my @pal = ([80,255,120],[255,170,40],[80,220,255],[255,90,220],[240,240,80],[160,120,255]);
        my $si = 0;
        for my $sd (@{ $self->{seeds} }) {
            my $rp = $self->_rotate_points($rot, pdl([[$sd->{x}],[$sd->{y}],[$sd->{z}]]));
            my ($sx, $sy, $depth) = $self->_project($rp);
            my $col = $pal[$si % @pal];
            push @points_data, {
                x => $sx->at(0), y => $sy->at(0),
                depth => 1e9,                          # 常に最前面
                size  => $self->{zoom} * 7,
                rgba  => [ @$col, 255 ],
            };
            push @label_recs, {
                x => $sx->at(0) + 8, y => $sy->at(0) + 8,
                rgb => [ map { int(($_+255)/2) } @$col ],   # 明るめのラベル色
                text => sprintf('%d:%s', $si + 1, $sd->{label}),
            };
            $si++;
        }
    }

    # ---- 面(メッシュ)を差し込む (P:EEG18) ----
    # line モード: 面塗り線分を @lines_data 先頭へ unshift(軸・点より奥に描画)。
    # zbuffer モード: 面は三角セクションで送る(ラベルの後に付与)。どちらの経路も
    # _mesh_lines/_mesh_tris が pick 用の _mesh_proj を設定する。
    my $tris = { n => 0 };
    if (exists $scene->{mesh}) {
        if (($self->{render} // 'line') eq 'zbuffer') {
            $tris = $self->_mesh_tris($rot);
        } else {
            unshift @lines_data, @{ $self->_mesh_lines($rot) };
        }
    }

    # ---- カラーバー(画面固定 HUD) ----------------------------------------
    # $scene->{colorbar} = { colors=>[[r,g,b]... 0..255, t=0→1 順], ticks=>[[frac,'txt']...],
    #                        title=>'...' }。座標は _project を通さない固定値なので回転しない。
    # 水平線を 1px 間隔で積んで勾配帯にする(thick_fill 有無に依らず連続)。ラベルは
    # point_idx=0xFFFF の絶対座標センチネルでそのまま画面座標に出る。giza-server 無改変。
    if ($scene->{colorbar}) {
        my ($cl, $cbl) = $self->_colorbar_items;
        push @lines_data, @$cl;
        push @label_recs, @$cbl;
    }

    # ---- ペイロードのパック ----
    # gsp_3d_frame_hdr_t: n_lines(u16) n_points(u16) flags(u8) cx(f32) cy(f32) = 13 bytes
    # n_lines は u16。超えると pack('S') が折り返しサーバが誤カウント→破損するので、
    # ここで防御的に切り詰める(_mesh_lines の予算 60000 は通常これに掛からない)。
    if (@lines_data > 65535) {
        warn sprintf("Driver::GS3D: %d line records exceed u16 max; truncating to 65535.\n",
                     scalar @lines_data);
        # 先頭(=奥の面塗り)を優先的に残し、末尾を捨てる。軸・点は別枠なので消えない。
        splice(@lines_data, 65535);
    }
    my $nl  = scalar @lines_data;
    my $np  = scalar @points_data;
    my $cx  = $self->width / 2;
    my $cy  = $self->height / 2;
    my $flags = 0x03 | ($self->{thick_fill} ? 0x04 : 0) | ($tris->{n} ? 0x08 : 0);   # 0x04:fill帯 0x08:三角
    my $payload = pack('S S C f< f<', $nl, $np, $flags, $cx, $cy);

    # 線分レコード: x0 y0 x1 y1 depth r g b a (f32×5 + u8×4 = 24 bytes)
    for my $ln (@lines_data) {
        # thick_fill 時は depth スロットに fill 帯高さ w(既定1)を載せる。giza-server は
        # 水平線(y0==y1)を「高さ w の filled bar」で塗る(flag 0x04)。depth はサーバの
        # 描画では未使用(レコードは既に depth ソート済みで届く)なので上書きして問題ない。
        my $slot5 = $self->{thick_fill} ? ($ln->{w} // 1) : $ln->{depth};
        $payload .= pack('f<f<f<f<f<CCCC',
            $ln->{x0}, $ln->{y0}, $ln->{x1}, $ln->{y1},
            $slot5, @{$ln->{rgba}});
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
        # len is a byte count (u8). A character string (a label from `use utf8`
        # source, e.g. Japanese) must go as its UTF-8 bytes: length() would
        # count characters, and pack-ing it in would upgrade the whole payload,
        # which _send_msg then encodes as UTF-8 - every byte >= 0x80 of the
        # floats doubles and the frame is garbage. Cut at 255 bytes on a
        # character boundary, as titles are (GS::_clip_utf8).
        my $text = $lb->{text} // '';
        $text = Encode::encode('UTF-8', $text) if utf8::is_utf8($text);
        $text = PDL::Graphics::Cairo::Driver::GS::_clip_utf8($text, 255);
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

    # ---- 三角セクション (z-buffer 描画, flags bit3=0x08) ----
    # ラベルの直後に付与。旧 giza-server は flags 0x08 を見ずここを読まないので
    # 面は描かれないが破綻しない(後方互換)。頂点レコード(15 bytes):
    #   x,y(f32 スクリーン座標) z(f32 深度, 大きいほど手前) r,g,b(u8 Gouraud色)
    # 三角 = 頂点×3 = 45 bytes。n_tris(u16) が先頭。
    $payload .= _pack_tris_pdl($tris->{xyz}, $tris->{rgb}) if $tris->{n};

    PDL::Graphics::Cairo::Driver::GS::_send_msg(
        $self->{_ix3d}{sock}, GSP_MSG_3D_FRAME, $payload, $self->{_ix3d}{seq}++);
}

# カラーバーの線とラベル(画面座標)。段階 A は 3D_FRAME の線・ラベルに、段階 B は
# 3D_OVERLAY の帯・線・ラベルにする。返り値: (\@lines, \@labels)。線は
# { x0,y0,x1,y1, depth, w, rgba, band }(band = 勾配の 1 行)、ラベルは { x, y, rgb, text }。
sub _colorbar_items {
    my ($self) = @_;
    my $cb = $self->{scene}{colorbar} or return ([], []);
    my (@lines, @labels);
    my $W  = $self->width;  my $H = $self->height;
    my $bw = 18;                                   # バー幅 px
    my $bh = int($H * 0.42);  $bh = 220 if $bh > 220;  $bh = 80 if $bh < 80;
    my $xl = $W - 96;  my $xr = $xl + $bw;         # 画面右(タイトル/数値が切れない余白を確保)
    my $yt = int(($H - $bh) / 2);                  # 画面上原点(小y=上): t=1 が上端
    my $yb = $yt + $bh;
    my $cols = $cb->{colors} || [];
    my $nc   = scalar(@$cols) || 1;
    for my $py (0 .. $bh) {                        # 勾配(上端 t=1 → 下端 t=0)
        my $t  = 1 - $py / ($bh || 1);
        my $ci = int($t * ($nc - 1) + 0.5);  $ci = 0 if $ci < 0;  $ci = $nc-1 if $ci > $nc-1;
        my $rgb = $cols->[$ci] || [200,200,200];
        push @lines, { x0=>$xl, y0=>$yt+$py, x1=>$xr, y1=>$yt+$py,
                       depth=>-1e9, w=>1, rgba=>[ @{$rgb}[0,1,2], 255 ], band=>1 };
    }
    my $bd = [230,230,240,255];                    # 枠
    for my $s ([$xl,$yt,$xr,$yt],[$xl,$yb,$xr,$yb],[$xl,$yt,$xl,$yb],[$xr,$yt,$xr,$yb]) {
        push @lines, { x0=>$s->[0], y0=>$s->[1], x1=>$s->[2], y1=>$s->[3],
                       depth=>-1e9, w=>1, rgba=>$bd };
    }
    for my $tk (@{ $cb->{ticks} || [] }) {         # 目盛り(frac 0=下,1=上)+数値
        my ($frac,$txt) = @$tk;
        my $y = int($yb - $frac * $bh);
        push @lines, { x0=>$xr, y0=>$y, x1=>$xr+5, y1=>$y, depth=>-1e9, w=>1, rgba=>$bd };
        push @labels, { x=>$xr+9, y=>$y+5, rgb=>[235,235,245], text=>$txt };  # +5=半文字ぶん下げ目盛り線と中心合わせ(cocoa は下端アンカー11pt)
    }
    push @labels, { x=>$xl-6, y=>$yt-16, rgb=>[235,235,245],
                    text=>($cb->{title} // 'power (norm.)') };
    return (\@lines, \@labels);
}

# ============================================================
# LOD 差し替え(progressive refinement)。$which = 'coarse'|'fine'。
# scene->{mesh} を差し替えるだけ。次フレームの _send_3d_frame が新メッシュで
# 描く。winding 符号(_mesh_wsign)は両 LOD が同一 NY Head サーフェスの
# 別解像度で tri の向き規約が共通なので、キャッシュを流用してよい(clear しない
# =drag 解放ごとの重心外向き多数決の再計算を避ける)。もし将来 winding 規約の
# 異なるメッシュ対を渡すなら、ここで delete $self->{_mesh_wsign} すること。
# ============================================================
sub _lod_set {
    my ($self, $which) = @_;
    return unless $self->{_lod} && $self->{_lod_state} ne $which;
    $self->{scene}{mesh} = $self->{_lod}{$which};
    $self->{_lod_state}  = $which;
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
    # 段階 B に対応しているかを、窓を開く前に中身 u32 = 1 の PING で問う
    # (段階 B のサーバは中身 4 バイトの PONG、古いサーバは 0 バイトの PONG)。
    my $caps  = $self->_query_caps($sock, $seq++);
    my $stage = $self->_choose_stage($caps);
    $self->{_stage} = $stage;

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

    if ($stage eq 'B') {
        $self->_run_stage_b;
        delete $self->{_ix3d};
        $sock->close;
        return;
    }

    # REVIEW NOTE: $last_frame_time はループの直前で初期化し、各イテレー
    # ション末尾で更新する。フレーム送信そのものより前に経過時間を測る
    # ことで、_send_3d_frame自体の処理時間も含めた実際のフレーム間隔を
    # 制御できる(ACK待ち時間だけを見ると、ローカルソケットなので待ち時間
    # がほぼ0になり、結局無制限速度に戻ってしまうため)。
    my $last_frame_time = time();

    while (1) {
        $self->_play_tick if $self->_play_running;   # 再生中: 今のコマの頂点の色にする
        $self->_send_3d_frame();
        my $input = $self->_recv_ack_3d($sock);

        last unless defined $input;          # 接続切断

        # menu「Export OBJ/USDA」: 表示中シーンを .obj/.usda に書き出す。
        # 投影前の生ジオメトリ(MNI mm)を書くので、面デプス等の描画状態には依存しない。
        if ($input->{export}) {
            $self->_export_scene($input->{export}{fmt}, $input->{export}{path});
        }

        # LOD: 前フレームで coarse→fine に切り替えて持ち越した pick を、fine が
        # 描かれ _mesh_proj が更新された「この」フレームで解決する(下の pick 分岐参照)。
        if ($self->{_pick_pending}) {
            $self->_pick_at_screen(@{ delete $self->{_pick_pending} });
        }

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

            # LOD: 回転/ズームの「動き」があれば粗メッシュに落とす(スナップに回す)。
            # キー入力のみ(type==2, dx=dy=dzoom=0)では落とさない=リセット'r'等で
            # 精細表示を維持する。
            if ($self->{_lod}
                && ($inp->{dx} || $inp->{dy} || abs($inp->{dzoom}) > 0.01)) {
                $self->_lod_set('coarse');
                $self->{_last_motion} = time();
            }

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
                } else {
                    $self->_client_key($inp->{key});
                }
            }
        }

        # クリック pick: 3D 窓でクリック(移動<3px)すると giza-server が GSP_MSG_PICK
        # (fx,fy 画像比率)を送る。直近フレームの投影 _mesh_proj に対し最近傍可視頂点を選ぶ。
        if ($input->{pick} && $self->{scene}{mesh}) {
            my ($px, $py) = ($input->{pick}{fx} * $self->width,
                             $input->{pick}{fy} * $self->height);
            if ( (($input->{pick}{btn} // 1) == 2) ) {
                # 右クリック: 最も近い seed マークを削除(左クリック pick=追加 の対称)。
                # 既存 seed の x,y,z を現在の回転で投影して解決するので LOD は不要。
                $self->_unpick_at_screen($px, $py);
            }
            # pick(追加)は常に fine LOD に対して解決する(頂点 index を一意にするため=
            # 呼び出し側の in_from(fine のローカル→75K)と噛み合う)。ドラッグ直後で
            # まだ coarse なら fine に切り替え、pick は次フレーム(fine を描いて
            # _mesh_proj が更新された後)に持ち越す。既に fine ならその場で拾う。
            # 持ち越しは 1 フレーム(~16ms)で、pick 中は向きが動かないので座標は不変。
            elsif ($self->{_lod} && $self->{_lod_state} ne 'fine') {
                $self->_lod_set('fine');
                $self->{_pick_pending} = [ $px, $py ];
            } else {
                $self->_pick_at_screen($px, $py);
            }
        }

        # hover readout: カーソル下の頂点の x,y,z + area 名を右上に出す(クリック前の確認)。
        # LOD 使用時は fine が出ているときだけ readout する(coarse の頂点 index は
        # in_from と対応しないため。ドラッグ中は回転操作でありホバー確認はしない)。
        if ($input->{cursor} && $self->{scene}{mesh}
            && (!$self->{_lod} || $self->{_lod_state} eq 'fine')) {
            $self->{_cursor} = $input->{cursor};
            $self->_hover_readout($input->{cursor}{fx} * $self->width,
                                  $input->{cursor}{fy} * $self->height);
        }

        # LOD: 操作が IDLE_SEC 止まったら高精細メッシュに一度だけ差し替える。
        # 次フレームの _send_3d_frame が fine で描く(=手を止めた瞬間に精緻化)。
        # ループは常時 60fps で回るので、ここが実質のアイドルタイマになる。
        if ($self->{_lod} && $self->{_lod_state} eq 'coarse'
            && time() - $self->{_last_motion} >= IDLE_SEC) {
            $self->_lod_set('fine');
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

# 姿勢に関わらないキー(段階 A・B 共通。B ではサーバが 3D_INPUT で転送してくる)。
#   c: シードを全部消す   u: 最後のシードを取り消す
# 処理したら 1 を返す。
sub _client_key {
    my ($self, $key) = @_;
    if ($key == ord('c') || $key == ord('C')) {
        $self->{seeds} = [];
        print STDERR "[GS3D pick] seeds cleared\n";
        $self->{on_seeds_cleared}->() if $self->{on_seeds_cleared};
        return 1;
    }
    if ($key == ord(' ') && $self->{_play}) {
        $self->pause(!$self->{_play}{paused});
        return 1;
    }
    if ($key == ord('u') || $key == ord('U')) {
        if (@{ $self->{seeds} }) {
            my $s = pop @{ $self->{seeds} };
            printf STDERR "[GS3D pick] undo seed (was vertex %d)\n", $s->{index};
        }
        return 1;
    }
    return 0;
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
        elsif ($type == GSP_MSG_RESIZE) {
            # サーバ発の窓リサイズ通知 (w,h uint32)。width/height(親の rw 属性)を
            # 更新すれば、次フレームの _project と frame header の cx/cy が
            # 自動で新しい中心(w/2,h/2)になる=拡大しても中心が動かず左上が
            # 先に切れる問題が解消。giza-server 側は無改変。
            my ($w, $h) = unpack('L L', $payload);
            $self->width($w)  if $w;
            $self->height($h) if $h;
        }
        elsif ($type == GSP_MSG_PICK) {
            # サーバ発のクリック通知 (fx,fy 画像比率 [0,1], btn)。最新の 1 つを保持。
            my ($fx, $fy, $btn) = unpack('f< f< C', $payload);
            $result->{pick} = { fx => $fx, fy => $fy, btn => $btn };
        }
        elsif ($type == GSP_MSG_CURSOR) {
            # サーバ発のカーソル移動 (fx,fy 画像比率)。最新の 1 つだけ保持(hover readout 用)。
            my ($fx, $fy, $btn) = unpack('f< f< C', $payload);
            $result->{cursor} = { fx => $fx, fy => $fy };
        }
        elsif ($type == GSP_MSG_3D_EXPORT) {
            # menu 発の書き出し要求。format 1 バイト(0=obj, 1=usda) + 任意でパス
            # (NSSavePanel で選んだ保存先。空なら Perl 側が既定名を作る)。run() で処理。
            my $fmt  = unpack('C', substr($payload, 0, 1));
            my $path = length($payload) > 1 ? substr($payload, 1) : '';
            $result->{export} = { fmt => $fmt, path => $path };
        }
        # 想定外の型は読み捨ててループ継続（ACKを待ち続ける）
    }
}

# ============================================================
# 段階 B(メッシュを 1 回送り、以後は視点・色・重ねものだけ)
#
# サーバ(giza-server の viewer/gsp_scene3d.c)がメッシュを持ち、ドラッグ・ホイール・
# p・r で回して描き、姿勢を 3D_POSE で知らせる。Perl はその写しを $self->{qrot}・
# {rot}・{zoom}・{perspective} に持つ(右クリックで近いシードを消す・書き出しが使う)。
# クリックとカーソルの下の頂点の番号は 3D_PICKV・3D_HOVERV で届き、シード・on_pick・
# on_hover は段階 A と同じ関数(_add_seed・_unpick_at_screen・_readout_vertex)で扱う。
# c・u などのキーはサーバが 3D_INPUT で転送する。
# 段階 B では LOD を使わない(fine を送る)。光と ambient はサーバの既定(GS3D の既定と
# 同じ (0.3,0.4,1.0)・0.25)で、mesh の light・ambient は効かない。
# ============================================================

# 中身 u32 = 1 の PING を送り、PONG の機能のビットを返す(0 バイトの PONG なら 0)。
sub _query_caps {
    my ($self, $sock, $seq) = @_;
    PDL::Graphics::Cairo::Driver::GS::_send_msg(
        $sock, PDL::Graphics::Cairo::Driver::GS::GSP_MSG_PING, pack('V', 1), $seq);
    while (1) {
        my $hdr = $self->_sysread_exact($sock, 16)
            // die "Driver::GS3D: connection closed waiting for PONG\n";
        my ($magic, $ver, $type, $flags, $len) = unpack('L C C S L', $hdr);
        die "Driver::GS3D: bad magic\n"
            unless $magic == PDL::Graphics::Cairo::Driver::GS::GSP_MAGIC();
        my $payload = $len ? $self->_sysread_exact($sock, $len) : '';
        die "Driver::GS3D: connection closed waiting for PONG\n" unless defined $payload;
        next unless $type == PDL::Graphics::Cairo::Driver::GS::GSP_MSG_PONG();
        return length($payload) >= 4 ? unpack('V', $payload) : 0;
    }
}

# 段階 'A' か 'B' を決める。GS3D_STAGE(A|B)が stage より優先。
sub _choose_stage {
    my ($self, $caps) = @_;
    my $want = $self->{stage};
    my $env  = uc($ENV{GS3D_STAGE} // '');
    $want = $env if $env eq 'A' || $env eq 'B';
    return 'A' if $want eq 'A';
    my $can  = ($caps // 0) & GSP_CAP_3D_SCENE;
    my $mesh = $self->_fine_mesh;
    if ($want eq 'B') {
        warn "Driver::GS3D: the giza-server does not speak stage B; using stage A.\n" unless $can;
        warn "Driver::GS3D: stage B needs scene->{mesh}; using stage A.\n" if $can && !$mesh;
    }
    return ($can && $mesh) ? 'B' : 'A';
}

sub _fine_mesh {
    my ($self) = @_;
    return $self->{_lod} ? $self->{_lod}{fine} : $self->{scene}{mesh};
}

sub _stage_b_live {
    my ($self) = @_;
    return $self->{_ix3d} && ($self->{_stage} // '') eq 'B';
}

# PDL → リトルエンディアンのバイト列(f32・u32)。dim 0 が速く回る順。
sub _f32_bytes {
    my $c = $_[0]->float->copy;
    $c->bswap4 if pack('L', 1) ne pack('V', 1);
    return ${ $c->get_dataref };
}
sub _u32_bytes {
    my $c = $_[0]->ulong->copy;
    $c->bswap4 if pack('L', 1) ne pack('V', 1);
    return ${ $c->get_dataref };
}

# 陰影を掛けない頂点の色 (4 [r,g,b,a], Nv) byte。vcolors(Nv,3)、無ければ面の色 colors(Nf,3)を
# 頂点ごとに平均、どちらも無ければ color。アルファは mesh の alpha(既定 255)。
sub _mesh_rgba {
    my ($m) = @_;
    my $nv  = $m->{verts}->dim(0);
    my $rgb;
    if (defined $m->{vcolors}) {
        $rgb = $m->{vcolors};
    } elsif (ref $m->{colors} && $m->{colors}->isa('PDL')) {
        my ($fi) = _mesh_faces_wsign($m);
        my $fc  = $m->{colors};
        my $cnt = zeroes($nv);
        indadd(ones($fi->[0]->nelem), $_, $cnt) for @$fi;
        my @ch;
        for my $k (0 .. 2) {
            my ($acc, $fk) = (zeroes($nv), $fc->slice(",($k)")->sever);
            indadd($fk, $_, $acc) for @$fi;
            push @ch, $acc / ($cnt + ($cnt == 0));
        }
        $rgb = cat(@ch);                                           # (Nv,3)
    } else {
        $rgb = pdl($m->{color} // [0.85, 0.78, 0.70])->dummy(0, $nv);
    }
    my $out = zeroes(byte, 4, $nv);
    $out->slice('0:2') .= ($rgb->clip(0, 1) * 255 + 0.5)->byte->transpose;
    $out->slice('(3)') .= $m->{alpha} // 255;
    return $out;
}

# 3D_MESH の中身: mesh_id flags nv nf、頂点 f32×3×nv、法線 f32×3×nv、色 u8×4×nv、面 u32×3×nf。
sub _mesh_payload {
    my ($m, $id) = @_;
    my $verts = $m->{verts} // die "scene.mesh.verts required\n";
    my ($fi, $wsign) = _mesh_faces_wsign($m);
    my $vn    = $m->{_vnorm} //= _compute_vnormals($verts, $m->{faces});
    my $flags = GSP_MESH_NORMALS | ($wsign < 0 ? GSP_MESH_WINDING_CW : 0);
    return pack('C C V V', $id // 0, $flags, $verts->dim(0), $fi->[0]->nelem)
         . _f32_bytes($verts->transpose) . _f32_bytes($vn->transpose)
         . ${ _mesh_rgba($m)->get_dataref }
         . _u32_bytes(cat(@$fi)->transpose);
}

# 3D_VIEW(と 3D_POSE)の 33 バイト: q(w,x,y,z) zoom pivot(x,y,z) perspective。
sub _view_payload {
    my ($self) = @_;
    my @pv = defined $self->{_pivot} ? $self->{_pivot}->flat->list : (0, 0, 0);
    return pack('f<4 f< f<3 C', @{ $self->{qrot} }, $self->{zoom}, @pv,
                $self->{perspective} ? 1 : 0);
}

# 段階 B の送信。$ack なら ACK まで読み、途中に届いたメッセージは _b_queue に積む
# (run のループが順に処理する)。接続が切れていたら 0。
sub _send_b {
    my ($self, $type, $payload, $ack) = @_;
    my $ix = $self->{_ix3d} or return 0;
    return 0 if $self->{_b_eof};
    PDL::Graphics::Cairo::Driver::GS::_send_msg($ix->{sock}, $type, $payload, $ix->{seq}++);
    return 1 unless $ack;
    while (defined(my $msg = $self->_read_msg_b)) {
        return 1 if $msg->[0] == PDL::Graphics::Cairo::Driver::GS::GSP_MSG_ACK();
        if ($msg->[0] == PDL::Graphics::Cairo::Driver::GS::GSP_MSG_ERR()) {
            warn "Driver::GS3D: server error: $msg->[1]\n";
            return 1;
        }
        push @{ $self->{_b_queue} }, $msg;
    }
    return 0;
}

# 1 メッセージ [type, payload]。EOF なら undef(_b_eof を立てる)。
sub _read_msg_b {
    my ($self) = @_;
    return undef if $self->{_b_eof};
    my $sock = $self->{_ix3d}{sock};
    my $hdr  = $self->_sysread_exact($sock, 16);
    unless (defined $hdr) { $self->{_b_eof} = 1; return undef }
    my ($magic, $ver, $type, $flags, $len) = unpack('L C C S L', $hdr);
    die "Driver::GS3D: bad magic\n"
        unless $magic == PDL::Graphics::Cairo::Driver::GS::GSP_MAGIC();
    my $payload = $len ? $self->_sysread_exact($sock, $len) : '';
    unless (defined $payload) { $self->{_b_eof} = 1; return undef }
    return [ $type, $payload ];
}

# 積んであるもの、無ければ 1 つ届くまで待ち、そのあとすでに届いている分も取る。
sub _recv_batch_b {
    my ($self, $timeout) = @_;      # $timeout(秒): その間に何も届かなければ空で返す(再生中)
    my @out = splice @{ $self->{_b_queue} };
    my $sel = IO::Select->new($self->{_ix3d}{sock});
    unless (@out) {
        return if defined $timeout && !$sel->can_read($timeout);
        my $m = $self->_read_msg_b // return;
        push @out, $m;
    }
    while (!$self->{_b_eof} && $sel->can_read(0)) {
        my $m = $self->_read_msg_b // last;
        push @out, $m;
    }
    return @out;
}

sub _run_stage_b {
    my ($self) = @_;
    require IO::Select;
    $self->{_b_queue} = [];
    $self->{_b_eof}   = 0;
    $self->_lod_set('fine') if $self->{_lod};
    my $m = $self->_fine_mesh;
    printf STDERR "[GS3D] stage B: mesh %d vertices, %d faces\n",
        $m->{verts}->dim(0), $m->{faces}->dim(0) if $self->verbose;
    $self->_send_b(GSP_MSG_3D_MESH, _mesh_payload($m, 0), 1) or return;
    $self->_send_b(GSP_MSG_3D_VIEW, $self->_view_payload);
    delete $self->{_b_ovl_sent};
    $self->_send_overlay_b;
    while (1) {
        my @msgs;
        if ($self->_play_running) {
            $self->_play_tick;                 # コマが進んでいれば 3D_COLORS
            $self->_send_overlay_b;            # 潜時の文字
            @msgs = $self->_recv_batch_b(PLAY_INTERVAL);
        } else {
            @msgs = $self->_recv_batch_b or last;
        }
        $self->_handle_b_msgs(@msgs) if @msgs;
        $self->_send_overlay_b;           # シード・readout・窓の大きさが変わっていれば送り直す
        last if $self->{_b_eof} && !@{ $self->{_b_queue} };
    }
}

# 重ねものを作り、前に送ったものと違えば 3D_OVERLAY を送る(ACK を待つ)。
sub _send_overlay_b {
    my ($self) = @_;
    return unless $self->_stage_b_live;
    my $p = $self->_overlay_payload;
    return if defined $self->{_b_ovl_sent} && $self->{_b_ovl_sent} eq $p;
    $self->{_b_ovl_sent} = $p if $self->_send_b(GSP_MSG_3D_OVERLAY, $p, 1);
}

# float の (k, n) と byte の (m, n) を、1 件 4k + m バイトのレコード n 件のバイト列にする。
sub _pack_records {
    my ($f, $b) = @_;
    my $n = $f->dim(1);
    return '' unless $n;
    my ($k, $m) = ($f->dim(0), $b->dim(0));
    my $fb = zeroes(byte, 4 * $k, $n);
    ${ $fb->get_dataref } = _f32_bytes($f);
    $fb->upd_data;
    my $rec = zeroes(byte, 4 * $k + $m, $n);
    $rec->slice('0:' . (4 * $k - 1)) .= $fb;
    $rec->slice((4 * $k) . ':')      .= $b;
    return ${ $rec->get_dataref };
}

# 3D_OVERLAY の中身(giza-server viewer/gsp_3d.h)。段階 A の _send_3d_frame と同じものを、
# 画面座標ではなくモデル座標で送る(投影と深度での隠しはサーバ)。
#   軸: 原点から先端への線(矢じり)と X・Y・Z の文字。常に手前。
#   scene の lines、points とその labels、シード: 深度で隠す(overlay_depth => 0 なら常に手前)。
#   点の半径は zoom 1 の画素(サーバが zoom を掛ける): 電極 4、シード 7(段階 A と同じ)。
#   readout とカラーバー: 画面座標。
sub _overlay_payload {
    my ($self) = @_;
    my $scene = $self->{scene};
    my $df    = $self->{overlay_depth} ? 0 : GSP_OVL_ON_TOP;
    my (@pts, @lns, @lab);   # [float (k,n), byte (m,n)] の組、ラベルは [x,y,z,dx,dy,r,g,b,flags,text]

    # 軸(3 本)
    my @acol = ([255,80,80,255], [80,255,80,255], [80,160,255,255]);
    my $tips = $self->{axes}->slice('1:3')->transpose;            # (3 xyz, 3 本)
    push @lns, [ zeroes(3, 3)->glue(0, $tips)->glue(0, ones(1, 3)),
                 pdl(byte, [ map { [ @$_, GSP_OVL_ON_TOP | GSP_OVL_ARROW ] } @acol ]) ];
    push @lab, map { [ ($tips->slice(":,($_)") * 1.12)->list, 0, 0, @{ $acol[$_] }[0 .. 2],
                       GSP_OVL_ON_TOP, (qw(X Y Z))[$_] ] } 0 .. 2;

    # scene の lines (M,9): x0 y0 z0 x1 y1 z1 r g b(0..1)、アルファ 200
    if (defined $scene->{lines} && $scene->{lines}->dim(0)) {
        my $L = $scene->{lines};
        my $M = $L->dim(0);
        my $b = zeroes(byte, 5, $M);
        $b->slice('0:2') .= ($L->slice(':,6:8') * 255)->long->transpose;
        $b->slice('(3)') .= 200;
        $b->slice('(4)') .= $df;
        push @lns, [ $L->slice(':,0:5')->transpose->glue(0, ones(1, $M)), $b ];
    }

    # 点 (N,3) と色、ラベル
    if (defined $scene->{points} && $scene->{points}->dim(0)) {
        my $P = $scene->{points};
        my $N = $P->dim(0);
        my $b = zeroes(byte, 5, $N);
        $b->slice('0:2') .= ($scene->{colors} * 255)->long->transpose if defined $scene->{colors};
        $b->slice('0:2') .= 255 unless defined $scene->{colors};
        $b->slice('(3)') .= 255;
        $b->slice('(4)') .= $df;
        push @pts, [ $P->transpose->glue(0, ones(1, $N) * 4), $b ];
        my $labels = $scene->{labels} || [];
        my $xyz = $P->transpose;                                    # (3, N)
        push @lab, map { [ $xyz->slice(":,($_)")->list, 6, -6, 255, 255, 200, $df, $labels->[$_] ] }
                   grep { $_ < $N } 0 .. $#$labels;
    }

    # シード(段階 A と同じ配色を循環)
    my @pal = ([80,255,120],[255,170,40],[80,220,255],[255,90,220],[240,240,80],[160,120,255]);
    my $si = 0;
    for my $sd (@{ $self->{seeds} }) {
        my $c = $pal[$si % @pal];
        push @pts, [ pdl([[ $sd->{x}, $sd->{y}, $sd->{z}, 7 ]]), pdl(byte, [[ @$c, 255, $df ]]) ];
        push @lab, [ $sd->{x}, $sd->{y}, $sd->{z}, 8, 8, (map { int(($_ + 255) / 2) } @$c), $df,
                     sprintf('%d:%s', $si + 1, $sd->{label}) ];
        $si++;
    }

    # hover の読み取り(左上)とカラーバー: 画面座標
    push @lab, [ 12, 20, 0, 0, 0, 235, 235, 245, GSP_OVL_SCREEN, $self->{readout} ]
        if defined $self->{readout};
    if (defined(my $pl = $self->_play_label)) {
        push @lab, [ 12, $self->height - 14, 0, 0, 0, 235, 235, 245, GSP_OVL_SCREEN, $pl ];
    }
    if ($scene->{colorbar}) {
        my ($cl, $cbl) = $self->_colorbar_items;
        if (@$cl) {
            push @lns, [ pdl([ map { [ $_->{x0}, $_->{y0}, 0, $_->{x1}, $_->{y1}, 0, $_->{w} // 1 ] } @$cl ]),
                         pdl(byte, [ map { [ @{ $_->{rgba} }, GSP_OVL_SCREEN | ($_->{band} ? GSP_OVL_BAND : 0) ] } @$cl ]) ];
        }
        push @lab, map { [ $_->{x}, $_->{y}, 0, 0, 0, @{ $_->{rgb} }, GSP_OVL_SCREEN, $_->{text} ] } @$cbl;
    }

    my $block = sub {
        my ($list) = @_;
        return (0, '') unless @$list;
        my ($f, $b) = @{ $list->[0] };
        if (@$list > 1) {
            $f = $f->glue(1, map { $_->[0] } @$list[1 .. $#$list]);
            $b = $b->glue(1, map { $_->[1] } @$list[1 .. $#$list]);
        }
        return ($f->dim(1), _pack_records($f, $b));
    };
    my ($np, $pbytes) = $block->(\@pts);
    my ($nl, $lbytes) = $block->(\@lns);
    my $out = pack('f< V', $self->{overlay_eps}, $np) . $pbytes . pack('V', $nl) . $lbytes
            . pack('V', scalar @lab);
    for my $l (@lab) {
        my $text = $l->[9] // '';
        $text = Encode::encode('UTF-8', $text) if utf8::is_utf8($text);
        $text = PDL::Graphics::Cairo::Driver::GS::_clip_utf8($text, 255);
        $out .= pack('f<5 C3 C C', @$l[0 .. 8], length $text) . $text;
    }
    return $out;
}

# サーバからのメッセージを順に処理する。HOVERV はまとめて届いた中の最後の 1 つだけ使う。
sub _handle_b_msgs {
    my ($self, @msgs) = @_;
    my ($last_hover) = grep { $msgs[$_][0] == GSP_MSG_3D_HOVERV } reverse 0 .. $#msgs;
    my $nv = $self->_fine_mesh->{verts}->dim(0);
    for my $i (0 .. $#msgs) {
        my ($type, $p) = @{ $msgs[$i] };
        if ($type == GSP_MSG_3D_POSE && length($p) >= 33) {
            my @v = unpack('f<4 f< f<3 C', $p);
            $self->{qrot}        = [ @v[0 .. 3] ];
            $self->{rot}         = _q_to_rot(@v[0 .. 3]);
            $self->{zoom}        = $v[4];
            $self->{perspective} = $v[8] ? 1 : 0;
        }
        elsif ($type == GSP_MSG_3D_PICKV && length($p) >= 14) {
            my ($mid, $vtx, $btn, $fx, $fy) = unpack('C V C f< f<', $p);
            next if $mid != 0;
            if (($btn & 0x0F) == 2) {
                $self->_unpick_at_screen($fx * $self->width, $fy * $self->height);
            } elsif ($vtx != GSP_NO_VERTEX && $vtx < $nv) {
                $self->_add_seed($vtx);
            }
        }
        elsif ($type == GSP_MSG_3D_HOVERV && length($p) >= 13) {
            next unless $i == $last_hover;
            my ($mid, $vtx) = unpack('C V', $p);
            next if $mid != 0;
            $self->_readout_vertex(($vtx != GSP_NO_VERTEX && $vtx < $nv) ? $vtx : -1);
        }
        elsif ($type == GSP_MSG_3D_INPUT && length($p) >= 14) {
            my ($dx, $dy, $dz, $itype, $key) = unpack('f< f< f< C C', $p);
            $self->_client_key($key) if $itype == 2;
        }
        elsif ($type == GSP_MSG_RESIZE && length($p) >= 8) {
            my ($w, $h) = unpack('L L', $p);
            $self->width($w)  if $w;
            $self->height($h) if $h;
        }
        elsif ($type == GSP_MSG_3D_EXPORT && length $p) {
            $self->_export_scene(unpack('C', $p), length($p) > 1 ? substr($p, 1) : '');
        }
        elsif ($type == PDL::Graphics::Cairo::Driver::GS::GSP_MSG_ERR()) {
            warn "Driver::GS3D: server error: $p\n";
        }
    }
}

# ============================================================
# 視点の API(段階 A でも B でも同じに動く。B で窓が開いていれば 3D_VIEW を送る)
#
#   $drv->view(elev => 30, azim => -90);   # 度。elev 90 = 頭頂の上から(既定の姿勢)
#   $drv->view('left');                    # top bottom front back left right
#   $drv->view(look_at => [x, y, z]);      # 回転の中心(pivot)を移す
#   $drv->view(toward => 'O1');            # ラベルの付いた点(または [x,y,z])を正面に
#   $drv->view('front', zoom => 2);
#
# 目の向き(pivot から見る人へ)は e = (cos elev·sin azim, −cos elev·cos azim, sin elev):
# azim 0 は後ろ(−Y)、90 は右(+X)、−90 は左、180 は前(+Y、鼻)。画面の上は e を elev で
# 微分した向き(elev < 90 なら頭頂の側、elev = 90・azim = 0 なら鼻が上 = qrot (0,0,0,1))。
# ============================================================
my %NAMED_VIEW = (
    top   => [ 90,   0], bottom => [-90,   0],
    back  => [  0,   0], front  => [  0, 180],
    left  => [  0, -90], right  => [  0,  90],
);

# (elev, azim) 度 → qrot (w,x,y,z)。行列の行は −(画面の右)、−(画面の上)、目の向き。
sub _view_quat {
    my ($elev, $azim) = @_;
    my $d2r = atan2(1, 1) / 45;
    my ($el, $az) = ($elev * $d2r, $azim * $d2r);
    my @e = (cos($el) * sin($az), -cos($el) * cos($az), sin($el));
    my @u = (-sin($el) * sin($az), sin($el) * cos($az), cos($el));
    my @r = ($u[1] * $e[2] - $u[2] * $e[1], $u[2] * $e[0] - $u[0] * $e[2], $u[0] * $e[1] - $u[1] * $e[0]);
    my $R = PDL->pdl([ [ map { -$_ } @r ], [ map { -$_ } @u ], [@e] ]);
    my @q = _mat_to_quat($R);
    @q = map { -$_ } @q if $q[0] < 0 || ($q[0] == 0 && $q[3] < 0);   # 符号をそろえる
    return @q;
}

sub view {
    my ($self, @a) = @_;
    my %o = @a % 2 ? (name => @a) : @a;
    if (defined $o{look_at}) {
        my $p = pdl($o{look_at});
        die "Driver::GS3D: view(look_at => [x, y, z])\n" unless $p->nelem == 3;
        $self->{_pivot} = $p->flat->dummy(0);                       # (1,3)
    }
    $self->{zoom} = $o{zoom} if defined $o{zoom};
    my ($elev, $azim);
    if (defined $o{name}) {
        my $nv = $NAMED_VIEW{ lc $o{name} }
            or die "Driver::GS3D: unknown view '$o{name}' (" . join(' ', sort keys %NAMED_VIEW) . ")\n";
        ($elev, $azim) = @$nv;
    }
    if (defined $o{toward}) {
        my $p   = $self->_point_named($o{toward});
        my @pv  = defined $self->{_pivot} ? $self->{_pivot}->flat->list : (0, 0, 0);
        my @d   = map { $p->[$_] - $pv[$_] } 0 .. 2;
        my $len = sqrt($d[0]**2 + $d[1]**2 + $d[2]**2);
        die "Driver::GS3D: view(toward => ...) is at the pivot\n" unless $len > 1e-9;
        my $r2d = 45 / atan2(1, 1);
        $elev = $r2d * atan2($d[2], sqrt($d[0]**2 + $d[1]**2));
        $azim = $r2d * atan2($d[0], -$d[1]);
    }
    $elev = $o{elev} if defined $o{elev};
    $azim = $o{azim} if defined $o{azim};
    if (defined $elev || defined $azim) {
        $self->{qrot} = [ _view_quat($elev // 90, $azim // 0) ];
        $self->{rot}  = _q_to_rot(@{ $self->{qrot} });
    }
    $self->_send_b(GSP_MSG_3D_VIEW, $self->_view_payload) if $self->_stage_b_live;
    return $self;
}

# scene の labels・points から名前で点を引く([x,y,z] はそのまま)。
sub _point_named {
    my ($self, $what) = @_;
    return [ @$what ] if ref $what eq 'ARRAY';
    my $labels = $self->{scene}{labels} || [];
    my ($i) = grep { lc($labels->[$_] // '') eq lc $what } 0 .. $#$labels;
    die "Driver::GS3D: no point labelled '$what' in scene->{labels}\n"
        unless defined $i && defined $self->{scene}{points};
    return [ $self->{scene}{points}->slice("($i),:")->list ];
}

# 'ortho' | 'perspective'。引数が無ければ今のものを返す。
sub projection {
    my ($self, $p) = @_;
    return $self->{perspective} ? 'perspective' : 'ortho' unless defined $p;
    my $persp = $p =~ /\Apersp/i ? 1 : $p =~ /\Aortho/i ? 0
              : die "Driver::GS3D: projection('ortho' | 'perspective')\n";
    $self->{perspective} = $persp;
    $self->_send_b(GSP_MSG_3D_VIEW, $self->_view_payload) if $self->_stage_b_live;
    return $self;
}

# 今の姿勢(段階 B では最後の 3D_POSE の写し)。
sub pose {
    my ($self) = @_;
    return (
        qrot       => [ @{ $self->{qrot} } ],
        zoom       => $self->{zoom},
        pivot      => [ defined $self->{_pivot} ? $self->{_pivot}->flat->list : (0, 0, 0) ],
        projection => $self->projection,
    );
}

# 頂点の色 (Nv,3) 0..1 を差し替える。段階 B で窓が開いていれば 3D_COLORS(ACK を待つ)、
# 段階 A は次のコマから(zbuffer で描くときの vcolors)。LOD のときは fine に入れる。
sub set_vertex_colors {
    my ($self, $rgb) = @_;
    my $m  = $self->_fine_mesh or die "Driver::GS3D: set_vertex_colors needs scene->{mesh}\n";
    my $nv = $m->{verts}->dim(0);
    die sprintf("Driver::GS3D: set_vertex_colors wants (%d,3), got (%s)\n", $nv, join(',', $rgb->dims))
        unless $rgb->ndims == 2 && $rgb->dim(0) == $nv && $rgb->dim(1) == 3;
    $m->{vcolors} = $rgb;
    $self->_send_b(GSP_MSG_3D_COLORS, pack('C V', 0, $nv) . ${ _mesh_rgba($m)->get_dataref }, 1)
        if $self->_stage_b_live;
    return $self;
}

# ============================================================
# 頂点の色の時間変化を窓の中で再生する(源パワーの潜時をなめる)。
#
#   $drv->play(times  => $t,          # 潜時(ms)の列 (n)。昇順
#              colors => $rgb,        # (Nv, 3, n) 0..1、またはコード ($i, $t_ms) -> (Nv, 3)
#              speed  => 1,           # 実時間の何倍か(1 = 潜時 1 ms を 1 ms で流す)
#              loop   => 1);          # 最後まで行ったら先頭に戻る(0 なら最後で止まる)
#   $drv->run;                        # 窓を開いて時刻ゼロ(times の先頭)から再生
#
# 経過した時間に合う潜時のコマを描き、描き切れないコマは飛ばす。スペースで一時停止と
# 再開、$drv->pause(1|0) でも同じ。窓の左下に今の潜時を出す。段階 B は 3D_COLORS で
# 色だけを送り(陰影・回転はサーバ)、段階 A は頂点の色 vcolors を差し替えて 3D_FRAME で
# 描き直す(render => 'zbuffer' のときだけ色が出る)。run の前でも、on_pick などの
# コールバックの中からでも呼べる。
# ============================================================
sub play {
    my ($self, %o) = @_;
    my $m  = $self->_fine_mesh or die "Driver::GS3D: play needs scene->{mesh}\n";
    my $nv = $m->{verts}->dim(0);
    my $t  = ref $o{times} eq 'ARRAY' ? pdl($o{times}) : $o{times};
    die "Driver::GS3D: play(times => ...) is required\n" unless ref $t && $t->isa('PDL') && $t->nelem;
    $t = $t->flat->double;
    my $n = $t->nelem;
    die "Driver::GS3D: play(times => ...) must be ascending\n"
        if $n > 1 && (($t->slice('1:-1') - $t->slice('0:-2'))->min < 0);
    my $c = $o{colors} // die "Driver::GS3D: play(colors => ...) is required\n";
    if (ref $c eq 'CODE') {
        # 1 コマ目で形を確かめる
    } elsif (ref $c && $c->isa('PDL')) {
        die sprintf("Driver::GS3D: play colors want (%d,3,%d), got (%s)\n", $nv, $n, join(',', $c->dims))
            unless $c->ndims == 3 && $c->dim(0) == $nv && $c->dim(1) == 3 && $c->dim(2) == $n;
    } else {
        die "Driver::GS3D: play(colors => ...) wants a (Nv,3,n) PDL or a code ref\n";
    }
    my $speed = $o{speed} // 1;
    die "Driver::GS3D: play(speed => ...) must be > 0\n" unless $speed > 0;
    warn "Driver::GS3D: play in stage A shows the colours only with render => 'zbuffer'\n"
        if ($self->{render} // 'line') ne 'zbuffer' && ($self->{stage} eq 'A');
    $self->{_play} = {
        times => $t, list => [ $t->list ], colors => $c, speed => $speed,
        loop => $o{loop} // 1, paused => 0, start => undef, index => -1,
    };
    return $self;
}

# 一時停止(1)・再開(0)。引数が無ければ今の状態を返す。
sub pause {
    my ($self, $on) = @_;
    my $p = $self->{_play} or return;
    return $p->{paused} unless defined $on;
    my $now = time();
    if ($on && !$p->{paused}) {
        $p->{paused} = 1;
        $p->{paused_at} = $now;
    } elsif (!$on && $p->{paused}) {
        $p->{paused} = 0;
        $p->{start} += $now - $p->{paused_at} if defined $p->{start};
    }
    return $self;
}

sub _play_running {
    my ($self) = @_;
    my $p = $self->{_play} or return 0;
    return !$p->{paused} && !$p->{done};
}

# 今の時刻のコマ: 経過時間 × speed を先頭の潜時に足し、それ以下の最後のコマ。
sub _play_index {
    my ($self, $now) = @_;
    my $p = $self->{_play};
    my $L = $p->{list};
    $p->{start} //= $now;
    my $span = $L->[-1] - $L->[0];
    # 1e-6 ms: a time exactly on a sample (in decimal) lands on it despite rounding
    my $lat  = $L->[0] + ($now - $p->{start}) * 1000 * $p->{speed} + 1e-6;
    if ($lat > $L->[-1]) {
        if ($p->{loop} && $span > 0) {
            my $step = @$L > 1 ? ($span / (@$L - 1)) : 1;   # 最後のコマも 1 コマ分見せてから戻る
            my $period = $span + $step;
            $lat = $L->[0] + ($lat - $L->[0]) - $period * int(($lat - $L->[0]) / $period);
            $lat = $L->[-1] if $lat > $L->[-1];
        } else {
            $p->{done} = 1;
            return $#$L;
        }
    }
    # 二分探索: times[i] <= lat の最大の i
    my ($lo, $hi) = (0, $#$L);
    while ($lo < $hi) {
        my $mid = int(($lo + $hi + 1) / 2);
        if ($L->[$mid] <= $lat) { $lo = $mid } else { $hi = $mid - 1 }
    }
    return $lo;
}

# コマが変わっていれば頂点の色を差し替える(段階 B は 3D_COLORS)。変わったら 1。
sub _play_tick {
    my ($self) = @_;
    my $p = $self->{_play} or return 0;
    my $i = $self->_play_index(time());
    return 0 if $i == $p->{index};
    $p->{index} = $i;
    my $c = $p->{colors};
    my $rgb = ref $c eq 'CODE' ? $c->($i, $p->{list}[$i]) : $c->slice(":,:,($i)");
    $self->set_vertex_colors($rgb);
    return 1;
}

# 窓の左下に出す文字(再生していなければ undef)。
sub _play_label {
    my ($self) = @_;
    my $p = $self->{_play} or return undef;
    return undef if $p->{index} < 0;
    return sprintf('t = %g ms%s', $p->{list}[ $p->{index} ], $p->{paused} ? '  (paused)' : '');
}

# ============================================================
# 表示中シーン($self->{scene})を .obj / .usda に書き出す。
#   $fmt : 0 = obj, 1 = usda(GSP_MSG_3D_EXPORT のペイロード先頭バイト)。
#   $path: NSSavePanel で選んだ保存先(省略/空なら CWD に既定名を生成)。
# 出力座標は投影前の生ジオメトリ(MNI mm)。書式コアは PDL 非依存の
# PDL::Graphics::Cairo::SceneExport(検証済み)、PDL→プレーン変換のみ
# normalize_pdl_scene が担う。
#
# LOD 使用時は fine に切り替えてから書き出す(coarse のまま出すと間引かれた
# cortex になるため)。書いた絶対パスを STDERR に出す。電極半径は
# $self->{export_radius}(mm, 既定 3)で調整可。
# ============================================================
sub _export_scene {
    my ($self, $fmt, $path) = @_;
    my $ext = (defined $fmt && $fmt == 1) ? 'usda' : 'obj';

    # 間引かれていない cortex を書くため fine に上げる。
    if ($self->{_lod} && ($self->{_lod_state} // '') ne 'fine') {
        $self->_lod_set('fine');
    }

    my $out;
    if (defined $path && length $path) {
        $out = $path;   # パネルで選んだ保存先をそのまま尊重(拡張子もユーザ選択)。
    } else {
        my @t  = localtime;
        my $ts = sprintf '%04d%02d%02d_%02d%02d%02d',
                         $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0];
        my $base = $self->{export_base} // 'gs3d_export';
        $out = sprintf '%s_%s.%s', $base, $ts, $ext;
    }

    my $ok = eval {
        my $plain = PDL::Graphics::Cairo::SceneExport::normalize_pdl_scene($self->{scene});

        # 電極ラベル + picked seed(マーカ球 + "N:label" ラベル)を書き出しに含める。
        # ラベルは各電極/シードから外向き(radial)に浮かせた Helvetica 塗り面テキスト。
        # cairo/Helvetica 依存なので eval で握り、失敗しても mesh+電極は必ず出す。
        # labels か seeds があれば自動で有効($self->{export_labels} を 0 で抑止)。
        if ( (!defined $self->{export_labels} || $self->{export_labels})
             && ( ($self->{scene}{labels} && defined $self->{scene}{points})
                  || ($self->{seeds} && @{ $self->{seeds} }) ) ) {
            eval {
                require PDL::Graphics::Cairo::LabelCairo;
                my $size = $self->{export_label_size} // 6;

                # radial 配置の中心=頭中心。電極重心を使う(無ければ MNI 原点)。
                my $center = [0, 0, 0];
                if (defined $self->{scene}{points}) {
                    my $pts = $self->{scene}{points};
                    my $n = $pts->dim(0);
                    my @c = (0, 0, 0);
                    for my $i (0 .. $n-1) {
                        my @p = $pts->slice("($i),:")->list;
                        $c[0]+=$p[0]; $c[1]+=$p[1]; $c[2]+=$p[2];
                    }
                    $center = [ $c[0]/$n, $c[1]/$n, $c[2]/$n ] if $n;
                }

                my @labs3d;

                # 電極ラベル
                if ($self->{scene}{labels} && defined $self->{scene}{points}) {
                    my $pts = $self->{scene}{points};
                    my @P = map { [ $pts->slice("($_),:")->list ] } 0 .. $pts->dim(0)-1;
                    push @labs3d, @{ PDL::Graphics::Cairo::LabelCairo::electrode_labels_to_geom(
                        labels  => $self->{scene}{labels},
                        points  => \@P,
                        center  => $center,
                        size_mm => $size,
                        color   => [1, 1, 0.78],
                    ) };
                }

                # picked seeds: viewer と同じ配色でマーカ球(points に追記)+ "N:label"
                if ($self->{seeds} && @{ $self->{seeds} }) {
                    my @pal = ([0.31,1,0.47],[1,0.67,0.16],[0.31,0.86,1],
                               [1,0.35,0.86],[0.94,0.94,0.31],[0.63,0.47,1]);
                    # マーカ球用に points/pcolors を必ず用意(電極に per-point 色が
                    # 無い scene でも seed 色を出せるよう、無ければ電極分を既定色で埋める)。
                    $plain->{points}  ||= [];
                    my $ne = @{ $plain->{points} } / 3;
                    $plain->{pcolors} ||= [ (0.8, 0.8, 0.8) x $ne ];
                    my $mo = 4;   # seed は cortex 頂点上=球が埋もれる。外向きに浮かせて可視化
                    my $si = 0;
                    for my $sd (@{ $self->{seeds} }) {
                        my $col = $pal[$si % @pal];
                        # 頭中心から外向き単位ベクトル(マーカ/ラベルの浮かし方向)
                        my @d = ($sd->{x}-$center->[0], $sd->{y}-$center->[1], $sd->{z}-$center->[2]);
                        my $L = sqrt($d[0]**2 + $d[1]**2 + $d[2]**2) || 1;
                        my @o = ($sd->{x} + $d[0]/$L*$mo,
                                 $sd->{y} + $d[1]/$L*$mo,
                                 $sd->{z} + $d[2]/$L*$mo);
                        # マーカ球(皮質から少し浮かせた位置)
                        push @{ $plain->{points}  }, @o;
                        push @{ $plain->{pcolors} }, @$col;
                        # ラベル "N:label"(元の seed 位置から。electrode_labels_to_geom が
                        # さらに外向き offset_out=6mm するのでマーカのやや外側に出る)
                        push @labs3d, @{ PDL::Graphics::Cairo::LabelCairo::electrode_labels_to_geom(
                            labels  => [ sprintf('%d:%s', $si+1, $sd->{label}) ],
                            points  => [ [ $sd->{x}, $sd->{y}, $sd->{z} ] ],
                            center  => $center,
                            size_mm => $size,
                            color   => $col,
                        ) };
                        $si++;
                    }
                }

                $plain->{labels3d} = \@labs3d if @labs3d;
                1;
            } or warn "[GS3D export] label/seed geom skipped: $@";
        }

        my %opt;
        $opt{electrode_radius} = $self->{export_radius}    if defined $self->{export_radius};
        $opt{mesh_name}        = $self->{export_mesh_name} if defined $self->{export_mesh_name};
        PDL::Graphics::Cairo::SceneExport::write_scene($plain, $ext, $out, %opt);
        1;
    };
    if ($ok) {
        my $abs = eval { require Cwd; Cwd::abs_path($out) } // $out;
        printf STDERR "[GS3D export] wrote %s\n", $abs;
    } else {
        warn "[GS3D export] failed ($ext): $@";
    }
    return;
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
