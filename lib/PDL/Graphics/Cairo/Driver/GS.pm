package PDL::Graphics::Cairo::Driver::GS;

# =============================================================
# Driver::GS — giza_server バックエンド（GSPプロトコル）
#
# 方式:
#   Cairo surface から write_to_png_stream でメモリにPNGを作り、
#   Unixソケット経由でGSPプロトコルに乗せて giza_server に送る。
#   テンポラリファイルは一切作らない。
#
#   サーバーが居なければ fork/exec で起動して常駐させる（setsid独立）。
#   一度起動したサーバーはプログラム終了後も生き続ける（pgxwin_server後継）。
#
# 起動方針 (start => ...):
#   'auto'    — 居なければ起動、居れば共存（デフォルト）
#   'connect' — 起動しない。居なければ die（手動起動前提）
#   'launch'  — 必ず新規起動を試みる
#
# 使い方:
#   $fig->show(backend => 'gs');
#   $fig->show(backend => 'gs', title => 'My Plot', start => 'connect');
#
# Linux/macOS 共通: クライアントから見た契約（デバイス/プロトコル/
# ソケットパス）は同一。giza_server の描画実態だけがOSで差し替わる。
# =============================================================

use strict;
use warnings;
use Time::HiRes;
use Moo;
use IO::Socket::UNIX;
use POSIX ();
use Encode ();
use PDL::Graphics::Cairo::Driver::Cairo;
use PDL::Graphics::Cairo::Interactive::Scrub;

has width   => (is => 'rw', required => 1);   # rw: RESIZE 逆チャネルで更新する
has height  => (is => 'rw', required => 1);
has title   => (is => 'ro', default  => sub { 'PDL::Graphics::Cairo' });
has start   => (is => 'ro', default  => sub { 'auto' });  # auto|connect|launch
has verbose => (is => 'ro', default  => sub { $ENV{PDLCAIRO_DEBUG} ? 1 : 0 });

# ---- GSP プロトコル定数（giza-server-protocol.h と一致）----
use constant {
    GSP_MAGIC      => 0x47495A41,   # "GIZA"
    GSP_VERSION    => 1,
    GSP_MSG_PING   => 0x01,
    GSP_MSG_PONG   => 0x02,
    GSP_MSG_PNG    => 0x10,
    GSP_MSG_TITLE  => 0x11,
    GSP_MSG_NEWWIN => 0x12,
    GSP_MSG_CLOSE  => 0x20,
    GSP_MSG_ACK    => 0x21,
    GSP_MSG_ERR    => 0xFF,
    GSP_MSG_SLIDER => 0x13,
    GSP_MSG_SAVEREQ  => 0x14,   # server→client: render & return vector
    GSP_MSG_SAVEDATA => 0x15,   # client→server: vector bytes for pending save
    GSP_MSG_RESIZE   => 0x16,   # server→client: window resized, re-render at new px
    GSP_MSG_ZOOM     => 0x17,   # server→client: zoom/pan changed (optional notify)
    GSP_MSG_CURSOR   => 0x18,   # server→client: cursor moved (image fraction)
    GSP_MSG_PICK     => 0x19,   # server→client: click (image fraction)
    GSP_SAVE_FMT_PDF => 0,
    GSP_SAVE_FMT_SVG => 1,
};

sub _sock_path {
    my $env = $ENV{GIZA_SERVER_SOCK};
    return $env if defined $env && length $env;   # isolated/parallel servers, tests
    return "/tmp/giza_server_$<.sock";            # default: one server per user
}

# ------------------------------------------------------------------
# サーバーバイナリ探索
# ------------------------------------------------------------------
sub _find_server {
    return $ENV{GIZA_SERVER}
        if $ENV{GIZA_SERVER} && -x $ENV{GIZA_SERVER};
    use File::Basename qw(dirname);
    my $base = dirname(__FILE__);
    # リポジトリ同梱のビルド済みバイナリ（開発時）。
    # よくある2レイアウトを両方見る:
    #   (a) <pgc>/giza-server/giza_server        … サブディレクトリ同梱
    #   (b) <pgc>/../giza-server/giza_server      … ~/src 下の兄弟チェックアウト
    for my $rel ("$base/../../../../../giza-server/giza_server",
                 "$base/../../../../../../giza-server/giza_server") {
        if (-x $rel) {
            require Cwd;
            return Cwd::realpath($rel);
        }
    }
    # PATH上を探す（execlp("giza_server")と同じ挙動）
    for my $dir (split /:/, $ENV{PATH} // "") {
        my $p = "$dir/giza_server";
        return $p if -x $p;
    }
    # フォールバック: 既知のprefixをハードコード
    for my $p (qw(/usr/local/bin/giza_server /opt/local/bin/giza_server)) {
        return $p if -x $p;
    }
    return undef;
}

# ------------------------------------------------------------------
# _available — このホストで 'gs' バックエンドが使えるか。
# 既に起動中、またはバイナリが見つかれば真。Figure::_default_backend が
# darwin で 'gs' を既定に採るかどうかの判定に使う。socket 接続を1回試す
# だけ（+ PATH 走査）なので軽量。クラスメソッド/関数どちらで呼んでも可。
# ------------------------------------------------------------------
sub _available {
    return 1 if _server_alive();
    return defined _find_server();
}

# ------------------------------------------------------------------
# 生存確認: 実際に接続できるか（ソケットファイルの有無では判断しない。
# giza_server は起動時に無条件 unlink するため、残骸ファイルがありうる）
# ------------------------------------------------------------------
sub _server_alive {
    my $s = IO::Socket::UNIX->new(
        Type => SOCK_STREAM(), Peer => _sock_path());
    if ($s) { $s->close; return 1; }
    return 0;
}

# ------------------------------------------------------------------
# fork/exec で giza_server を起動し、setsid で親から切り離す。
# listen 開始まで最大2秒ポーリング。
# ------------------------------------------------------------------
sub _launch_server {
    my $bin = _find_server();
    die "Driver::GS: giza_server binary not found.\n"
      . "  Build it, or set GIZA_SERVER=/path/to/giza_server\n"
        unless defined $bin;

    my $pid = fork();
    die "Driver::GS: fork failed: $!" unless defined $pid;
    if ($pid == 0) {
        POSIX::setsid();
        open(STDIN,  '<', '/dev/null');
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null');
        exec($bin) or POSIX::_exit(127);
    }
    for (1 .. 40) {                       # ~2s
        return $pid if _server_alive();
        select(undef, undef, undef, 0.05);
    }
    die "Driver::GS: giza_server did not start listening within timeout\n";
}

# ------------------------------------------------------------------
# 接続を確保（起動方針に従う）
# ------------------------------------------------------------------
sub _ensure_server {
    my ($self) = @_;
    my $mode = lc($self->start);

    if ($mode eq 'connect') {
        die "Driver::GS: no giza_server at " . _sock_path()
          . " (start => 'connect')\n" unless _server_alive();
        return;
    }
    if ($mode eq 'auto' && _server_alive()) {
        return;                           # 手動起動済みと共存
    }
    # auto(不在) または launch
    _launch_server();
}

# ------------------------------------------------------------------
# GSP ヘッダ/送受信
# 16バイト: magic(L) version(C) type(C) flags(S) length(L) seq(L)
# 同一マシン内ソケットなのでネイティブバイトオーダで揃える。
# ------------------------------------------------------------------
sub _pack_header {
    my ($type, $length, $seq) = @_;
    return pack('L C C S L L', GSP_MAGIC, GSP_VERSION, $type, 0, $length, $seq);
}

sub _send_msg {
    my ($sock, $type, $payload, $seq) = @_;
    $payload //= '';
    # The header carries length($payload) as a byte count. A character string
    # (a title from `use utf8` source) would be counted in characters but
    # written as more bytes, putting the stream out of step: send its UTF-8.
    $payload = Encode::encode('UTF-8', $payload) if utf8::is_utf8($payload);
    $sock->print(_pack_header($type, length($payload), $seq) . $payload)
        or die "Driver::GS: write failed: $!";
}

sub _read_exact {
    my ($sock, $n) = @_;
    my $buf = '';
    while (length($buf) < $n) {
        my $r = $sock->read(my $chunk, $n - length($buf));
        die "Driver::GS: read failed: $!" unless defined $r;
        die "Driver::GS: connection closed\n" if $r == 0;
        $buf .= $chunk;
    }
    return $buf;
}

sub _recv_ack {
    my ($sock, $what) = @_;
    my $hdr = _read_exact($sock, 16);
    my ($magic, $ver, $type) = unpack('L C C', $hdr);
    die "Driver::GS: bad magic\n" unless $magic == GSP_MAGIC;
    # ACK にペイロードは無いが、念のため length 分読み飛ばす
    my (undef, undef, undef, undef, $len) = unpack('L C C S L', $hdr);
    _read_exact($sock, $len) if $len;
    die "Driver::GS: $what expected ACK, got type 0x" . sprintf('%02X', $type) . "\n"
        unless $type == GSP_MSG_ACK;
}

# ---- interactive 経路は sysread 専用（バッファ混在を避ける）----
sub _sysread_exact {
    my ($self, $sock, $n) = @_;
    my $buf = '';
    while (length($buf) < $n) {
        my $r = sysread($sock, my $c, $n - length($buf));
        return undef unless $r;          # 0=EOF, undef=error → 窓クローズで抜ける
        $buf .= $c;
    }
    return $buf;
}

# ACK を待つ。待つ間に届いた SLIDER / RESIZE は捨てずに反映する。
# （ドラッグ中、PNG送信〜ACK受信の隙間に SLIDER/RESIZE が割り込むため。）
#   SLIDER → $state を最新値で上書き
#   RESIZE → $self->width/height を新サイズに更新（次フレームから反映）
# 戻り値: 待つ間に再描画要因（SLIDER か RESIZE）を1つ以上見たら 1、無ければ 0。
sub _recv_ack_sys {
    my ($self, $sock, $what, $state) = @_;
    my $need_redraw = 0;
    while (1) {
        my $hdr = $self->_sysread_exact($sock, 16);
        die "Driver::GS: connection closed waiting for $what ACK\n"
            unless defined $hdr;
        my ($magic, $ver, $type, $flags, $len) = unpack('L C C S L', $hdr);
        die "Driver::GS: bad magic\n" unless $magic == GSP_MAGIC;
        my $payload = $len ? $self->_sysread_exact($sock, $len) : '';
        die "Driver::GS: connection closed reading $what ACK payload\n"
            if $len && !defined $payload;

        if ($type == GSP_MSG_ACK) {
            return $need_redraw;                # 本命。割り込みの有無を返す
        }
        elsif ($type == GSP_MSG_SLIDER && $state) {
            my ($id, $val) = unpack('C f<', $payload);
            $state->{$id} = $val;               # 最新値で上書き（中間は捨てる）
            $need_redraw = 1;
        }
        elsif ($type == GSP_MSG_RESIZE) {
            my ($w, $h) = unpack('L L', $payload);
            $self->width($w)  if $w;            # 次の _figure_to_png から新サイズ
            $self->height($h) if $h;
            $need_redraw = 1;
        }
        elsif ($type == GSP_MSG_SAVEREQ) {
            # ドラッグ中に File>Save が押されると PNG送信〜ACK の隙間に
            # SAVEREQ が割り込む。ここで畳まず処理（再描画→SAVEDATA返送）
            # して ACK を待ち続ける。$need_redraw は変えない（画面再描画不要）。
            my ($f) = unpack('C', $payload);
            $self->_handle_savereq($f);
        }
        elsif ($type == GSP_MSG_CURSOR || $type == GSP_MSG_PICK
               || $type == GSP_MSG_ZOOM) {
            # マウスイベントは ACK 待ち中にも届きうる。コールバックを呼ぶ
            # だけで $need_redraw は変えない（giza_server 側で表示更新済み）。
            $self->_handle_mouse($type, $payload);
        }
        elsif ($type == GSP_MSG_ERR) {
            warn "Driver::GS: server error: $payload\n";
            return $need_redraw;
        }
        # その他の型は読み捨てて ACK を待ち続ける
    }
}


# render用のwidth/height（PDLCAIRO_RENDER_SCALE適用済み）
sub _render_w { int($_[0]->width  * ($ENV{PDLCAIRO_RENDER_SCALE} // 1.0)) || 1 }
sub _render_h { int($_[0]->height * ($ENV{PDLCAIRO_RENDER_SCALE} // 1.0)) || 1 }

# Figure → :memory: Cairo → メモリPNG（show() のロジックを再利用）
# $w, $h (optional): size of the image in pixels. Default: the driver's own
# size. show_grid_scrub passes the size of the figure, because each of its
# windows has its own size, which also changes when the window is resized.
sub _figure_to_png {
    my ($self, $figure, $w, $h) = @_;
    my $_t0 = Time::HiRes::time();
    $w = defined $w ? (int($w) || 1) : $self->_render_w;
    $h = defined $h ? (int($h) || 1) : $self->_render_h;
    my $cairo = PDL::Graphics::Cairo::Driver::Cairo->new(
        width => $w, height => $h, file => ':memory:');
    $figure->_render_to($cairo);
    my $_t1 = Time::HiRes::time();
    my $bytes = $cairo->png_bytes;
    my $_t2 = Time::HiRes::time();
    printf "  png: cairo_render=%.0fms  png_compress=%.0fms  size=%dKB\n",
        ($_t1-$_t0)*1000, ($_t2-$_t1)*1000, length($bytes)/1024
        if $self->verbose;
    return $bytes;
}

# Figure → PDF/SVG ベクタバイト列。
# Cairo の Pdf/SvgSurface はファイルパス必須なので、tempファイルに
# 出力 → slurp → unlink で取り出す（Transpiler と同じ隔離方針）。
#   $ext: 'pdf' または 'svg'
sub _figure_to_vector {
    my ($self, $figure, $ext) = @_;
    require File::Temp;
    my ($fh, $path) = File::Temp::tempfile(
        "giza_gs_save_XXXXXX", TMPDIR => 1, SUFFIX => ".$ext");
    close $fh;                            # Cairo はパス指定で書く
    # Figure::save が拡張子から PdfSurface/SvgSurface を選び、_render_to で
    # finish() まで完了する（= ファイルが閉じて完成する）。
    $figure->save($path);
    open my $in, '<:raw', $path
        or die "Driver::GS: cannot read vector temp $path: $!\n";
    local $/;
    my $bytes = <$in>;
    close $in;
    unlink $path;
    return $bytes // '';
}

# サーバー発のマウスイベント（CURSOR / PICK / ZOOM）を処理する。
# cursor_overlay モード時は $ix->{_cursor_pending} に座標を記録し、
# 再描画フラグを立てる（run ループ側でドレイン後に再描画）。
# interactive セッション外（$self->{_ix} 無し）なら黙って無視する。
sub _handle_mouse {
    my ($self, $type, $payload) = @_;
    my $ix = $self->{_ix} or return;
    if ($type == GSP_MSG_CURSOR) {
        my ($fx, $fy, $btn) = unpack('f< f< C', $payload);
        # cursor_overlay: 次 render で座標テキストを描かせるため state に記録
        if ($ix->{cursor_overlay}) {
            $ix->{_cursor_pending} = { fx => $fx, fy => $fy, btn => $btn, type => 'cursor' };
        }
        $ix->{on_cursor}->($fx, $fy, $btn) if $ix->{on_cursor};
    }
    elsif ($type == GSP_MSG_PICK) {
        my ($fx, $fy, $btn) = unpack('f< f< C', $payload);
        if ($ix->{cursor_overlay}) {
            $ix->{_cursor_pending} = { fx => $fx, fy => $fy, btn => $btn, type => 'pick' };
        }
        $ix->{on_pick}->($fx, $fy, $btn) if $ix->{on_pick};
    }
    elsif ($type == GSP_MSG_ZOOM) {
        my ($zoom, $px, $py) = unpack('f< f< f<', $payload);
        # zoom_pan_redraw: zoom/pan 状態を _ix に記録して run() 側で再描画
        if ($ix->{zoom_pan_redraw}) {
            $ix->{_zoom}  = $zoom;
            $ix->{_pan_x} = $px;
            $ix->{_pan_y} = $py;
        }
        $ix->{on_zoom}->($zoom, $px, $py) if $ix->{on_zoom};
    }
}


# サーバー発 SAVEREQ への応答。現在の $state で図を再描画し、PDF/SVG に
# 変換して SAVEDATA で返送する（撃ちっぱなし、ACK は待たない）。
# interactive セッション中のみ有効（$self->{_ix} が無ければ何もしない）。
sub _handle_savereq {
    my ($self, $fmt) = @_;
    my $ix = $self->{_ix} or return;     # interactive 外なら無視
    my $ext = ($fmt == GSP_SAVE_FMT_SVG) ? 'svg' : 'pdf';
    my $figure = $ix->{render}->($ix->{state}, $self->width, $self->height, {is_save => 1});
    my $bytes  = $self->_figure_to_vector($figure, $ext);
    # payload = [uint8 fmt][vector bytes]
    _send_msg($ix->{sock}, GSP_MSG_SAVEDATA,
              pack('C', $fmt) . $bytes, $ix->{save_seq}++);
}

# ------------------------------------------------------------------
# show_interactive — 描画後もソケットを保持し、サーバー発スライダ／
# リサイズで render コールバックを呼んで再描画し続ける（窓クローズ/EOF
# で return）。
#   render => sub { my ($state, $w, $h) = @_; ...; return $figure }   必須
#       $w/$h は現在の窓キャンバスサイズ(px)。リサイズ追従させるなら
#       figure(width => $w, height => $h) のようにこれを使う。使わなければ
#       従来どおり固定サイズ（リサイズ時は伸縮表示）。
#   init   => { 0 => k0, 1 => A0 }   初期スライダ値（任意）
#   slider_labels => { 0 => '表示位置', 1 => sub { my ($v, $state) = @_; ... } }
#       各スライダの意味を窓のタイトルの後ろに付ける(任意)。
#       "title — ↔ 表示位置 / ↕ 表示幅"。↔ は id 0(下の横スライダ)、
#       ↕ は id 1(右の縦スライダ)、それ以外は "#id"。値がコードなら
#       描くたびに (そのスライダの値 0..1, $state) で呼び、返した文字列を
#       使う(今の値をタイトルに出せる)。undef か '' を返した id は出さない。
#       タイトルは変わったときだけ送る(GSP_MSG_TITLE は ACK なし)。
# ------------------------------------------------------------------
sub show_interactive {
    my ($self, %opt) = @_;
    my $render = $opt{render}
        or die "Driver::GS: show_interactive needs render => sub {...}\n";
    my $state  = $opt{init} // {};

    $self->_ensure_server;

    my $sock = IO::Socket::UNIX->new(
        Type => SOCK_STREAM(), Peer => _sock_path())
        or die "Driver::GS: connect " . _sock_path() . ": $!\n";
    $sock->autoflush(1);
    binmode($sock);                       # バイナリ確実（crlf/encoding 層を排除）

    my $seq = 0;
    # NEWWIN payload: gsp_newwin_t (w,h) にスライダ初期つまみ位置を添付する。
    # 末尾に gsp_slider_t レコード [uint8 id][f< val] を並べると、giza_server が
    # 生成時点で正しいつまみ位置で窓を作る（既定0.0→initへ跳ぶチラつきを回避）。
    # val は正規化 [0,1]。8バイトだけの旧 NEWWIN とは後方互換。
    my $newwin = pack('L L', $self->width, $self->height);
    # スライダidは非負整数のみ（_pos・_cursor_* 等を除外）。並べる前に絞る
    # (先に数値として並べると、数字でないキーで "isn't numeric in sort" の警告が出る)
    for my $id (sort { $a <=> $b } grep { /\A[0-9]+\z/ } keys %$state) {
        my $v = $state->{$id};
        next unless defined $v && $v =~ /\A-?[0-9.eE+]+\z/;  # 数値のみ
        $v = 0 if $v < 0; $v = 1 if $v > 1;       # クランプ [0,1]
        $newwin .= pack('C f<', $id, $v);
    }
    _send_msg($sock, GSP_MSG_NEWWIN, $newwin, $seq++);
    $self->_recv_ack_sys($sock, 'NEWWIN');
    $self->{_slider_labels} = $opt{slider_labels};
    delete $self->{_title_sent};
    $seq = $self->_send_title($sock, $state, $seq);   # fire-and-forget

    # SAVEREQ（File>Save as PDF/SVG）への応答に必要なコンテキスト。
    # save_seq は SAVEDATA 専用の連番（サーバーは seq を順序判定に使わない）。
    # on_cursor/on_pick/on_zoom はマウスイベント用コールバック（任意）。
    #   on_cursor => sub { my ($fx, $fy) = @_; ... }   # 0..1 の画像内分率
    #   on_pick   => sub { my ($fx, $fy, $btn) = @_; ... } # btn: 1=左,2=中,3=右
    #   on_zoom   => sub { my ($zoom, $px, $py) = @_; ... }
    # cursor_overlay => 1 を指定すると CURSOR/PICK 受信時に自動再描画し、
    #   render コールバックの $state に以下のキーが入る:
    #     _cursor_fx, _cursor_fy  ... giza-server からの画像分率 (0..1)
    #     _cursor_x,  _cursor_y   ... データ座標（Figure の xlim/ylim で変換済み）
    #                                  プロット枠外なら undef
    #     _cursor_btn             ... ボタン番号（CURSOR時は0=移動、PICK時は1/2/3）
    #     _cursor_type            ... 'cursor' または 'pick'
    # 画像内分率 (fx,fy) は (0,0)=左上, (1,1)=右下。
    $self->{_ix} = {
        sock => $sock, render => $render, state => $state, save_seq => 900000,
        on_cursor      => $opt{on_cursor},
        on_pick        => $opt{on_pick},
        on_zoom        => $opt{on_zoom},
        cursor_overlay => $opt{cursor_overlay} // 0,
        zoom_pan_redraw => $opt{zoom_pan_redraw} // 0,
        _cursor_pending => undef,
        _zoom  => 1.0, _pan_x => 0.0, _pan_y => 0.0,
    };

    # warm-up: Cairo JIT・フォントキャッシュ初期化（初回フレームの遅延を隠す）
    {
        my $wu = PDL::Graphics::Cairo::Driver::Cairo->new(
            width => $self->_render_w, height => $self->_render_h, file => ':memory:');
        $wu->png_bytes;   # 空のCairoサーフェスをPNG化してキャッシュを温める
    }

    # 初期フレーム
    {
        my $fig = $render->($state, $self->_render_w, $self->_render_h);
        $self->{_ix}{_last_figure} = $fig;
        $seq = $self->_send_title($sock, $state, $seq);
        _send_msg($sock, GSP_MSG_PNG, $self->_figure_to_png($fig), $seq++);
    }
    $self->_recv_ack_sys($sock, 'PNG', $state);

    $seq = $self->run($sock, $render, $state, $seq);
    delete $self->{_ix};
    delete $self->{_slider_labels};
    # CLOSE は送らない（窓を残す）— ループ終了後にソケットだけ閉じる
    $sock->close;
    return;
}

# ------------------------------------------------------------------
# _compose_title($state): the window title, with the meaning of each slider
# from slider_labels appended: "title — ↔ position / ↕ width".
# Returned as bytes (UTF-8): the title and the labels may each be a
# character string (`use utf8`) or bytes already in UTF-8; joining the two
# kinds as they are would turn the bytes into Latin-1 characters.
# ------------------------------------------------------------------
my %SLIDER_MARK = (0 => "\x{2194}", 1 => "\x{2195}");   # ↔ horizontal, ↕ vertical
sub _utf8_bytes {
    my ($s) = @_;
    $s //= '';
    return utf8::is_utf8($s) ? Encode::encode('UTF-8', $s) : $s;
}
sub _compose_title {
    my ($self, $state) = @_;
    my $title = _utf8_bytes($self->title);
    my $labels = $self->{_slider_labels};
    return $title unless ref $labels eq 'HASH' && %$labels;
    my @parts;
    for my $id (sort { $a <=> $b } grep { /\A[0-9]+\z/ } keys %$labels) {
        my $l = $labels->{$id};
        my $text = ref $l eq 'CODE' ? $l->($state->{$id}, $state) : $l;
        next unless defined $text && $text ne '';
        my $mark = $SLIDER_MARK{$id} // "#$id";
        push @parts, _utf8_bytes($mark) . ' ' . _utf8_bytes($text);
    }
    return $title unless @parts;
    my $sep = _utf8_bytes(" \x{2014} ");                       # em dash
    return ($title eq '' ? '' : $title . $sep) . join(' / ', @parts);
}

# _send_title($sock, $state, $seq): send GSP_MSG_TITLE if the title changed
# since the last one sent on this connection. Returns the next $seq.
# giza_server keeps at most 255 bytes of a title and reads them as UTF-8: a
# cut in the middle of a character makes the whole title invalid (Cocoa's
# stringWithUTF8String returns nil). Cut at a character boundary here.
use constant GS_TITLE_MAX => 255;
sub _clip_utf8 {
    my ($bytes, $max) = @_;
    return $bytes if length($bytes) <= $max;
    my $n = $max;
    # step back over continuation bytes (10xxxxxx) to the start of a character
    $n-- while $n > 0 && (ord(substr($bytes, $n, 1)) & 0xC0) == 0x80;
    return substr($bytes, 0, $n);
}

sub _send_title {
    my ($self, $sock, $state, $seq) = @_;
    my $t = _clip_utf8($self->_compose_title($state), GS_TITLE_MAX);
    return $seq if defined $self->{_title_sent} && $self->{_title_sent} eq $t;
    _send_msg($sock, GSP_MSG_TITLE, $t, $seq++);
    $self->{_title_sent} = $t;
    return $seq;
}

# ------------------------------------------------------------------
# run — 受信ループ（C の client_slider.c main() と等価）
# ------------------------------------------------------------------
sub run {
    my ($self, $sock, $render, $state, $seq) = @_;
    require IO::Select;
    my $sel = IO::Select->new($sock);
    $seq //= 100;

    while (1) {
        my $hdr = $self->_sysread_exact($sock, 16);
        last unless defined $hdr;                     # EOF = 窓クローズ/サーバ消失
        my ($magic, $ver, $type, $flags, $len, $sq) = unpack('L C C S L L', $hdr);
        die "Driver::GS: bad magic in run loop\n" unless $magic == GSP_MAGIC;

        # SLIDER（値変化）と RESIZE（窓サイズ変化）は同じ再描画経路に乗せる。
        # どちらも「状態を更新 → 溜まった分を畳む → 再描画 → 送信 → ACK」。
        if ($type == GSP_MSG_SLIDER || $type == GSP_MSG_RESIZE) {
            my $p = $self->_sysread_exact($sock, $len);
            last unless defined $p;
            if ($type == GSP_MSG_SLIDER) {
                my ($id, $val) = unpack('C f<', $p);
                $state->{$id} = $val;
            } else {                              # RESIZE
                my ($w, $h) = unpack('L L', $p);
                $self->width($w)  if $w;
                $self->height($h) if $h;
            }

            # --- coalescing: 溜まった SLIDER/RESIZE を全部吸って最新値で上書き ---
            # （ドラッグ中は両方が連続して届く。中間フレームは捨てて最後だけ描く。）
            my $eof = 0;
            while ($sel->can_read(0)) {
                my $h2 = $self->_sysread_exact($sock, 16);
                if (!defined $h2) { $eof = 1; last }
                my ($m2, undef, $t2, undef, $l2) = unpack('L C C S L', $h2);
                my $p2 = $l2 ? $self->_sysread_exact($sock, $l2) : '';
                if (!defined $p2) { $eof = 1; last }
                if ($t2 == GSP_MSG_SLIDER) {
                    my ($i, $v) = unpack('C f<', $p2);
                    $state->{$i} = $v;
                } elsif ($t2 == GSP_MSG_RESIZE) {
                    my ($w, $h) = unpack('L L', $p2);
                    $self->width($w)  if $w;
                    $self->height($h) if $h;
                } elsif ($t2 == GSP_MSG_SAVEREQ) {
                    my ($f) = unpack('C', $p2);
                    $self->_handle_savereq($f);    # ドラッグ中の保存要求も取りこぼさない
                } elsif ($t2 == GSP_MSG_CURSOR || $t2 == GSP_MSG_PICK
                         || $t2 == GSP_MSG_ZOOM) {
                    $self->_handle_mouse($t2, $p2); # マウスイベントも消費（desync 防止）
                } elsif ($t2 == GSP_MSG_ERR) {
                    warn "Driver::GS: server error: $p2\n";
                    last;
                } else {
                    last;                              # 想定外型: 消費済みで desync なし、drain 終了
                }
            }
            last if $eof;

            # 再計算 → 再描画 → 送信 → ACK（ACK待ち中に割り込んだ SLIDER/RESIZE も吸収）
            while (1) {
                my $fig = $render->($state, $self->_render_w, $self->_render_h);
                $self->{_ix}{_last_figure} = $fig if $self->{_ix};
                $seq = $self->_send_title($sock, $state, $seq);
                _send_msg($sock, GSP_MSG_PNG, $self->_figure_to_png($fig), $seq++);
                my $more = $self->_recv_ack_sys($sock, 'PNG', $state);
                last unless $more;     # ACK待ち中に SLIDER/RESIZE が来ていたら再描画
            }

        }
        elsif ($type == GSP_MSG_SAVEREQ) {
            my $p = $len ? $self->_sysread_exact($sock, $len) : '';
            last if $len && !defined $p;
            my ($f) = unpack('C', $p);
            $self->_handle_savereq($f);           # 再描画→PDF/SVG→SAVEDATA返送
        }
        elsif ($type == GSP_MSG_CURSOR || $type == GSP_MSG_PICK
               || $type == GSP_MSG_ZOOM) {
            my $p = $len ? $self->_sysread_exact($sock, $len) : '';
            last if $len && !defined $p;
            $self->_handle_mouse($type, $p);

            my $ix = $self->{_ix};

            # zoom_pan_redraw モード: ZOOM 受信時に xlim/ylim を更新して再描画
            if ($ix && $ix->{zoom_pan_redraw} && $type == GSP_MSG_ZOOM) {
                # coalescing: 溜まった ZOOM を全部吸う
                while ($sel->can_read(0)) {
                    my $h2 = $self->_sysread_exact($sock, 16);
                    last unless defined $h2;
                    my ($m2, undef, $t2, undef, $l2) = unpack('L C C S L', $h2);
                    my $p2 = $l2 ? $self->_sysread_exact($sock, $l2) : '';
                    last unless defined $p2;
                    if ($t2 == GSP_MSG_ZOOM) {
                        $self->_handle_mouse($t2, $p2);
                    } else {
                        last;
                    }
                }
                # state に zoom/pan を書き込む
                $state->{_zoom}  = $ix->{_zoom};
                $state->{_pan_x} = $ix->{_pan_x};
                $state->{_pan_y} = $ix->{_pan_y};
                # _last_figure の xlim/ylim から新しい表示範囲を計算
                if (my $fig = $ix->{_last_figure}) {
                    _apply_zoom_to_state($state, $fig, $ix->{_zoom}, $ix->{_pan_x}, $ix->{_pan_y});
                }
                # 再描画
                my $fig = $render->($state, $self->_render_w, $self->_render_h);
                $ix->{_last_figure} = $fig;
                $seq = $self->_send_title($sock, $state, $seq);
                _send_msg($sock, GSP_MSG_PNG, $self->_figure_to_png($fig), $seq++);
                $self->_recv_ack_sys($sock, 'PNG', $state);
            }
            if ($ix && $ix->{cursor_overlay} && $ix->{_cursor_pending}
                && ($type == GSP_MSG_CURSOR || $type == GSP_MSG_PICK)) {
                # coalescing: キューに残っている CURSOR を全部吸う
                while ($sel->can_read(0)) {
                    my $h2 = $self->_sysread_exact($sock, 16);
                    last unless defined $h2;
                    my ($m2, undef, $t2, undef, $l2) = unpack('L C C S L', $h2);
                    my $p2 = $l2 ? $self->_sysread_exact($sock, $l2) : '';
                    last unless defined $p2;
                    if ($t2 == GSP_MSG_CURSOR || $t2 == GSP_MSG_PICK) {
                        $self->_handle_mouse($t2, $p2);   # _cursor_pending を上書き
                    } else {
                        # CURSOR以外が来たら戻せないので溢れたことにする（稀）
                        last;
                    }
                }
                # state に座標を書き込む
                my $ev = $ix->{_cursor_pending};
                $state->{_cursor_fx}   = $ev->{fx};
                $state->{_cursor_fy}   = $ev->{fy};
                $state->{_cursor_btn}  = $ev->{btn};
                $state->{_cursor_type} = $ev->{type};
                $ix->{_cursor_pending} = undef;
                # Axes ベースのデータ座標変換（Figure が axes_list を持つ場合）
                # render が最後に返した Figure を _last_figure に保存してあれば使う
                if (my $fig = $ix->{_last_figure}) {
                    my ($xd, $yd) = (undef, undef);
                    my $ax_idx = undef;
                    my $i = 0;
                    for my $ax (@{ $fig->axes_list }) {
                        ($xd, $yd) = $ax->image_frac_to_data($ev->{fx}, $ev->{fy});
                        if (defined $xd) { $ax_idx = $i; last }
                        $i++;
                    }
                    $state->{_cursor_x}      = $xd;
                    $state->{_cursor_y}      = $yd;   # マウスのY座標（通常は使わない）
                    $state->{_cursor_ax_idx} = $ax_idx;  # ヒットしたAxesのインデックス
                } else {
                    $state->{_cursor_x} = undef;
                    $state->{_cursor_y} = undef;
                }
                # 再描画
                my $fig = $render->($state, $self->_render_w, $self->_render_h);
                $ix->{_last_figure} = $fig;
                $seq = $self->_send_title($sock, $state, $seq);
                _send_msg($sock, GSP_MSG_PNG, $self->_figure_to_png($fig), $seq++);
                $self->_recv_ack_sys($sock, 'PNG', $state);
            }
        }
        elsif ($type == GSP_MSG_ERR) {
            my $msg = $len ? $self->_sysread_exact($sock, $len) : '';
            warn "Driver::GS: server error: " . ($msg // '') . "\n";
        }
        else {
            $self->_sysread_exact($sock, $len) if $len;   # 未知型はペイロード読み飛ばし
        }
    }
    return $seq;
}



# _apply_zoom_to_state — giza-server の zoom/pan 値から
# state に _xlim_lo/_xlim_hi/_ylim_lo/_ylim_hi を書き込む。
# render コールバック側でこれを使って xlim/ylim を設定することで
# データ座標レベルの zoom/pan が実現できる。
#
# giza-server の zoom/pan 定義:
#   zoom=1.0, pan=0,0  → 全体表示
#   zoom>1             → 中心を基準に拡大
#   pan_x/pan_y        → ズーム済み画像の中心オフセット（-0.5..+0.5）
#                        （正=右/上方向に移動）
#
# データ座標への変換:
#   表示中心 = (xmid + pan_x*(xrange/zoom), ymid - pan_y*(yrange/zoom))
#   表示幅   = xrange / zoom
sub _apply_zoom_to_state {
    my ($state, $fig, $zoom, $pan_x, $pan_y) = @_;
    $zoom //= 1.0; $pan_x //= 0.0; $pan_y //= 0.0;

    # _orig_xlim/_orig_ylim: zoom=1.0のときの元のデータ範囲
    # 最初のZOOM受信時に保存、zoom=1.0に戻ったらクリア
    if ($zoom <= 1.0 + 1e-4 && abs($pan_x) < 1e-4 && abs($pan_y) < 1e-4) {
        # ほぼリセット状態: 元の範囲を使う
        delete $state->{_zoom_xlim_lo};
        delete $state->{_zoom_xlim_hi};
        delete $state->{_zoom_ylim_lo};
        delete $state->{_zoom_ylim_hi};
        return;
    }

    # 元レンジを Figure の最初の Axes から取得（未保存なら今の表示レンジを保存）
    my $ax0 = $fig->axes_list->[0] or return;
    my $ox0 = $state->{_orig_xmin} // $ax0->xmin // 0;
    my $ox1 = $state->{_orig_xmax} // $ax0->xmax // 1;
    my $oy0 = $state->{_orig_ymin} // $ax0->ymin // 0;
    my $oy1 = $state->{_orig_ymax} // $ax0->ymax // 1;
    # 元レンジを記憶（zoom=1のときに更新）
    $state->{_orig_xmin} //= $ox0;
    $state->{_orig_xmax} //= $ox1;
    $state->{_orig_ymin} //= $oy0;
    $state->{_orig_ymax} //= $oy1;

    my $xmid  = ($ox0 + $ox1) / 2;
    my $ymid  = ($oy0 + $oy1) / 2;
    my $xspan = ($ox1 - $ox0) / $zoom;
    my $yspan = ($oy1 - $oy0) / $zoom;

    # pan: giza-server では pan_x>0 = 画像を右にずらす = データを左に移動
    my $cx = $xmid - $pan_x * ($ox1 - $ox0);
    my $cy = $ymid + $pan_y * ($oy1 - $oy0);

    $state->{_zoom_xlim_lo} = $cx - $xspan/2;
    $state->{_zoom_xlim_hi} = $cx + $xspan/2;
    $state->{_zoom_ylim_lo} = $cy - $yspan/2;
    $state->{_zoom_ylim_hi} = $cy + $yspan/2;
}


sub show {
    my ($self, $figure) = @_;

    # 1) サーバー確保（起動方針に従う）
    $self->_ensure_server;

    # 2) Figure を :memory: モードの Cairo ドライバで描画 → メモリPNG
    my $cairo = PDL::Graphics::Cairo::Driver::Cairo->new(
        width  => $self->width,
        height => $self->height,
        file   => ':memory:',
    );
    $figure->_render_to($cairo);          # 最後に finish() されるが :memory: は no-op
    my $png = $cairo->png_bytes;          # ファイルを介さない

    # 3) GSP で送信
    my $sock = IO::Socket::UNIX->new(
        Type => SOCK_STREAM(), Peer => _sock_path())
        or die "Driver::GS: connect " . _sock_path() . ": $!\n";
    $sock->autoflush(1);

    my $seq = 0;
    _send_msg($sock, GSP_MSG_NEWWIN, pack('L L', $self->width, $self->height), $seq++);
    _recv_ack($sock, 'NEWWIN');

    _send_msg($sock, GSP_MSG_TITLE, $self->title, $seq++);  # fire-and-forget

    _send_msg($sock, GSP_MSG_PNG, $png, $seq++);
    _recv_ack($sock, 'PNG');

    $sock->close;                          # CLOSE は送らない（窓を残す）
    return;
}


# ---------------------------------------------------------------------
# show_grid_scrub — マルチ窓の対話セッション。
#
# 5x5 等のサブプロット図(親窓)を出し、サブプロットを *ダブルクリック* すると
# そのセルだけを拡大した子窓を新規に開く。子窓でマウスを動かすと直近データ点の
# (x,y)を右上に表示し、*ドラッグ*するとその点にマーカを描き、同じ潜時の縦線を
# 親窓の全サブプロットに引く。
#
# 単一窓の show_interactive/run とは独立の経路(_run_windows)で、既存機能には触れ
# ない。giza-server は各窓=各ソケットなので、複数ソケットを1つの select ループで
# 多重化する。
#
# 必須オプション:
#   grid_render => sub { my ($state,$w,$h)=@_; ...; return $figure }
#       親窓(5x5等)の Figure を返す。$state->{_scrub_lat} が定義されていれば、
#       ドライバが返り値の各 Axes に縦線(その潜時)を後付けする。
#   cell_render => sub { my ($ax_idx,$state,$w,$h)=@_; ...; return $figure }
#       ダブルクリックされたセル(親 Figure の axes_list インデックス)を単独 Axes
#       のフルサイズ図として返す。ドライバがカーソル直近点のマーカと右上読み取り
#       を後付けする。
# 任意オプション:
#   init         => \%state          共有状態(全窓で共有)
#   zoom_size    => [w,h]            子窓のピクセルサイズ(既定=親と同じ)
#   vline        => { color=>[r,g,b], lw=>.. }   親窓の潜時縦線スタイル
#   marker       => { color=>[r,g,b], ms=>.., marker=>'o' }  子窓マーカ
#   readout      => sub { my ($x,$y)=@_; return "x=..." }    右上テキスト整形
#   cell_title   => sub { my ($ax_idx)=@_; return "Cell $ax_idx" }  子窓タイトル
#   main_scrub   => 1                親窓でのクリック/ドラッグでも潜時を選ぶ
#                                    (既定 0 = 親窓はダブルクリックのみ)
#
# grid_render が返す Figure の Axes に $ax->{_scrub_skip} = 1 を立てると、その
# パネルには潜時縦線を引かず、main_scrub のクリック対象にもしない(頭皮マップ
# など時間軸でないパネル用)。ダブルクリックでの拡大は従来どおり効く。
# ---------------------------------------------------------------------
sub show_grid_scrub {
    my ($self, %opt) = @_;
    my $grid_render = $opt{grid_render}
        or die "show_grid_scrub: grid_render => sub {...} が必要です\n";
    my $cell_render = $opt{cell_render}
        or die "show_grid_scrub: cell_render => sub {...} が必要です\n";

    $self->_ensure_server;

    my $state = $opt{init} // {};
    my $wm = {
        state       => $state,
        grid_render => $grid_render,
        cell_render => $cell_render,
        zoom_w      => ($opt{zoom_size} && $opt{zoom_size}[0]) || $self->width,
        zoom_h      => ($opt{zoom_size} && $opt{zoom_size}[1]) || $self->height,
        vline       => $opt{vline}   || { color => [1,0,0], lw => 1.2 },
        marker      => $opt{marker}  || { color => [1,0,0], ms => 7, marker => 'o' },
        readout     => $opt{readout} || sub { sprintf("x=%.4g\ny=%.4g", $_[0], $_[1]) },
        cell_title  => $opt{cell_title} || sub { "cell $_[0]" },
        main_scrub  => $opt{main_scrub} ? 1 : 0,
        wins        => [],            # 全窓レコード
        cells       => {},            # ax_idx => 子窓レコード(重複オープン防止)
    };

    # 親窓を開く
    my $main = $self->_open_window($wm,
        kind  => 'main',
        w     => $self->width, h => $self->height,
        title => $self->title,
        render => sub { my ($win) = @_; $self->_paint_main($wm, $win) },
    );
    $wm->{main} = $main;

    $self->_run_windows($wm);

    # 後始末: ソケットを閉じる(CLOSE は送らない=窓は残す)
    for my $w (@{ $wm->{wins} }) {
        eval { $w->{sock}->close } if $w->{sock};
    }
    return;
}

# 新しい giza-server 窓を1つ開いてレコードを返す。NEWWIN→初期フレーム送信まで。
sub _open_window {
    my ($self, $wm, %a) = @_;
    require IO::Socket::UNIX;
    my $sock = IO::Socket::UNIX->new(
        Type => IO::Socket::UNIX::SOCK_STREAM(), Peer => _sock_path())
        or die "Driver::GS: connect " . _sock_path() . ": $!\n";
    $sock->autoflush(1);
    binmode($sock);

    my $win = {
        sock => $sock, seq => 0,
        kind => $a{kind}, ax_idx => $a{ax_idx},
        w => $a{w}, h => $a{h},
        render => $a{render},
        cursor => undef, last_fig => undef,
        dirty => 0, await_ack => 0, alive => 1,
    };

    _send_msg($sock, GSP_MSG_NEWWIN, pack('L L', $a{w}, $a{h}), $win->{seq}++);
    # NEWWIN の ACK を1つ待つ(この時点では他窓トラフィックはまだ無いので単純待ち)
    $self->_await_one_ack($win, 'NEWWIN');
    _send_msg($sock, GSP_MSG_TITLE, $a{title} // '', $win->{seq}++);  # fire-and-forget

    # 初期フレーム(装飾なし=カーソル未設定)。last_fig に描画済み図を保持し、
    # 以後 image_frac_to_data(プロット枠が確定した図が必要)に使う。
    $self->_send_frame($win);

    push @{ $wm->{wins} }, $win;
    return $win;
}

# 単発 ACK 待ち(窓オープン直後専用)。ACK 以外(まず来ない)は読み捨てる。
sub _await_one_ack {
    my ($self, $win, $what) = @_;
    while (1) {
        my $hdr = $self->_sysread_exact($win->{sock}, 16);
        die "Driver::GS: closed waiting $what ACK\n" unless defined $hdr;
        my ($magic, undef, $type, undef, $len) = unpack('L C C S L', $hdr);
        die "Driver::GS: bad magic ($what)\n" unless $magic == GSP_MAGIC;
        my $pl = $len ? $self->_sysread_exact($win->{sock}, $len) : '';
        return if $type == GSP_MSG_ACK;
    }
}

# ---------------------------------------------------------------------
# _run_windows — 複数窓を1ループで多重化。
#   フロー制御: 1窓につき PNG は同時1枚(await_ack)。窓が dirty かつ ACK 待ちで
#   なければ描画→送信→await_ack=1。ACK 到着で await_ack=0、まだ dirty なら再描画。
#   これで速いドラッグでも中間フレームは自然に畳まれ、窓間で相互ブロックしない。
# ---------------------------------------------------------------------
sub _run_windows {
    my ($self, $wm) = @_;
    require IO::Select;

    while (1) {
        # 生きている窓が親を含め全滅したら終了
        my @live = grep { $_->{alive} } @{ $wm->{wins} };
        last unless @live;
        last unless $wm->{main}{alive};       # 親を閉じたらセッション終了

        my $sel = IO::Select->new(map { $_->{sock} } @live);
        my @ready = $sel->can_read(0.05);

        for my $s (@ready) {
            my $win = _win_by_sock($wm, $s) or next;
            my $hdr = $self->_sysread_exact($s, 16);
            unless (defined $hdr) { $self->_close_window($win); next; }
            my ($magic, undef, $type, undef, $len) = unpack('L C C S L', $hdr);
            unless ($magic == GSP_MAGIC) { warn "Driver::GS: bad magic in run\n"; next; }
            my $pl = $len ? $self->_sysread_exact($s, $len) : '';
            if ($len && !defined $pl) { $self->_close_window($win); next; }
            $self->_dispatch($wm, $win, $type, $pl // '');
        }

        # ドラッグ中の間引き: ドラッグ中は _cell_cursor が「操作中セル + 親」だけ
        # dirty にし、他セルは _scrub_stale フラグに保留する。イベントが途切れた
        # (= ボタン解放 or 一時停止で select がタイムアウト)瞬間にだけ、保留して
        # いた全セルを最新の選択潜時へ追いつかせる。連続した速いドラッグ中は
        # イベントが切れ目なく届くのでここは走らず、他セルは再描画されない。
        if (!@ready && $wm->{_scrub_stale}) {
            $wm->{_scrub_stale} = 0;
            for my $w (@{ $wm->{wins} }) {
                $w->{dirty} = 1 if $w->{alive} && ($w->{kind} // '') eq 'cell';
            }
        }

        # dirty かつ ACK 非待ちの窓を描画
        for my $win (grep { $_->{alive} } @{ $wm->{wins} }) {
            next unless $win->{dirty} && !$win->{await_ack};
            $win->{dirty} = 0;
            $self->_send_frame($win);
        }
    }
}

# Build the window's figure, send it as a PNG and wait for its ACK.
# last_fig keeps the drawn figure (image_frac_to_data needs a figure whose
# plot frame is fixed). With verbose, prints after the "png:" line
#   frame: build=..ms png=..ms send=..ms
# where build is the render callback (grid_render / cell_render, so any
# map computation the caller does), png is _figure_to_png (cairo_render +
# png_compress) and send is the write to the socket; and when the ACK
# arrives,
#   ack: ..ms after send
# which is the time giza-server took to take the PNG in and show it.
sub _send_frame {
    my ($self, $win) = @_;
    my $t0  = Time::HiRes::time();
    my $fig = $win->{render}->($win);
    $win->{last_fig} = $fig;
    my $t1  = Time::HiRes::time();
    my $png = $self->_window_png($fig);
    my $t2  = Time::HiRes::time();
    _send_msg($win->{sock}, GSP_MSG_PNG, $png, $win->{seq}++);
    my $t3  = Time::HiRes::time();
    $win->{await_ack} = 1;
    $win->{sent_at}   = $t3;
    if ($self->verbose) {
        # gap: since this window's previous frame started. events: input
        # messages (CURSOR/PICK/RESIZE, any window) since then. age: how old
        # the newest of them was when this frame started.
        my $gap = defined $win->{frame_at} ? sprintf('%.0fms', ($t0 - $win->{frame_at}) * 1000) : '-';
        my $age = defined $self->{_input_at} ? sprintf('%.0fms', ($t0 - $self->{_input_at}) * 1000) : '-';
        printf "  frame: build=%.0fms  png=%.0fms  send=%.0fms  gap=%s  events=%d  age=%s\n",
            ($t1 - $t0) * 1000, ($t2 - $t1) * 1000, ($t3 - $t2) * 1000,
            $gap, ($self->{_n_input} // 0) - ($win->{n_input_at_frame} // 0), $age;
    }
    $win->{frame_at}         = $t0;
    $win->{n_input_at_frame} = $self->{_n_input} // 0;
    return $fig;
}

# PNG of a show_grid_scrub window: an image of the figure's own size. The
# figure was laid out for the current size of that window (grid_render /
# cell_render get it as $w, $h), which is not the driver's size for the
# enlarged windows, nor for any window after it was resized.
sub _window_png {
    my ($self, $fig) = @_;
    return $self->_figure_to_png($fig, $fig->width, $fig->height);
}

sub _win_by_sock {
    my ($wm, $s) = @_;
    for my $w (@{ $wm->{wins} }) { return $w if $w->{sock} && $w->{sock} == $s }
    return undef;
}

sub _close_window {
    my ($self, $win) = @_;
    $win->{alive} = 0;
    eval { $win->{sock}->close } if $win->{sock};
    $win->{sock} = undef;
}

# 1メッセージを窓種別に応じて処理。
sub _dispatch {
    my ($self, $wm, $win, $type, $pl) = @_;

    if ($type == GSP_MSG_RESIZE || $type == GSP_MSG_CURSOR || $type == GSP_MSG_PICK) {
        $self->{_n_input}++;                        # for the verbose frame line
        $self->{_input_at} = Time::HiRes::time();
    }

    if ($type == GSP_MSG_ACK) {
        $win->{await_ack} = 0;
        if ($self->verbose && defined $win->{sent_at}) {
            printf "  ack: %.0fms after send\n",
                (Time::HiRes::time() - $win->{sent_at}) * 1000;
            $win->{sent_at} = undef;
        }
    }
    elsif ($type == GSP_MSG_RESIZE) {
        my ($w, $h) = unpack('L L', $pl);
        $win->{w} = $w if $w; $win->{h} = $h if $h;
        $win->{dirty} = 1;
    }
    elsif ($type == GSP_MSG_CURSOR || $type == GSP_MSG_PICK) {
        my ($fx, $fy, $btn) = unpack('f< f< C', $pl);
        if ($win->{kind} eq 'main') {
            # 親窓: ダブルクリック(btn の 0x10 ビット)だけ拾ってセル拡大
            if ($type == GSP_MSG_PICK && ($btn & 0x10)) {
                $self->_dblclick_main($wm, $win, $fx, $fy);
            }
            elsif ($wm->{main_scrub}
                   && ($type == GSP_MSG_PICK || ($btn & 0x0F))) {
                # main_scrub: 親窓でのクリック/ドラッグでも潜時を選ぶ
                $self->_main_scrub($wm, $win, $fx, $fy);
            }
        } else {
            $self->_cell_cursor($wm, $win, $type, $fx, $fy, $btn);
        }
    }
    elsif ($type == GSP_MSG_ZOOM) {
        # v1 では未使用(親のネイティブ zoom/pan は使わない前提)。読み捨て済み。
    }
    elsif ($type == GSP_MSG_SAVEREQ) {
        my ($fmt) = unpack('C', $pl);
        $self->_save_window($win, $fmt);
    }
    elsif ($type == GSP_MSG_ERR) {
        warn "Driver::GS: server error: $pl\n";
    }
    # 未知型は読み捨て済み
}

# 親窓ダブルクリック → どのセルか判定 → 子窓オープン。
sub _dblclick_main {
    my ($self, $wm, $win, $fx, $fy) = @_;
    my $fig = $win->{last_fig} or return;
    my $idx; my $i = 0;
    for my $ax (@{ $fig->axes_list }) {
        my ($xd, $yd) = $ax->image_frac_to_data($fx, $fy);
        if (defined $xd) { $idx = $i; last }
        $i++;
    }
    return unless defined $idx;
    return if $wm->{cells}{$idx} && $wm->{cells}{$idx}{alive};  # 既に開いている

    my $cell = $self->_open_window($wm,
        kind   => 'cell', ax_idx => $idx,
        w      => $wm->{zoom_w}, h => $wm->{zoom_h},
        title  => $wm->{cell_title}->($idx),
        render => sub { my ($w) = @_; $self->_paint_cell($wm, $w) },
    );
    $wm->{cells}{$idx} = $cell;
}

# 親窓でのクリック/ドラッグ(main_scrub => 1 のとき)。ポインタ下のパネルの x を
# 共有潜時にする。_scrub_skip を立てた Axes(時間軸でないパネル)は対象外。
# 子窓でのドラッグと同じく、親窓は即時に、開いているセル窓はドラッグが途切れた
# ときにまとめて更新する。
sub _main_scrub {
    my ($self, $wm, $win, $fx, $fy) = @_;
    my $fig = $win->{last_fig} or return;
    for my $ax (@{ $fig->axes_list }) {
        next if $ax->{_scrub_skip};
        my ($xd, $yd) = $ax->image_frac_to_data($fx, $fy);
        next unless defined $xd;
        $wm->{state}{_scrub_lat} = $xd;
        $win->{dirty} = 1;
        $wm->{_scrub_stale} = 1;
        return 1;
    }
    return 0;
}

# 子窓カーソル/ドラッグ。
sub _cell_cursor {
    my ($self, $wm, $win, $type, $fx, $fy, $btn) = @_;
    my $fig = $win->{last_fig} or return;
    my $ax  = $fig->axes_list->[0] or return;
    my ($xd, $yd) = $ax->image_frac_to_data($fx, $fy);
    return unless defined $xd;                 # プロット枠外は無視

    my $is_drag = ($type == GSP_MSG_PICK) || ($btn & 0x0F);  # クリック or ボタン保持
    $win->{cursor} = { xd => $xd, yd => $yd };  # ライブ位置(選択前 hover の読み取り用)

    if ($is_drag) {
        # ドラッグ/クリック = 選択確定。潜時は「共有」状態へ。
        $wm->{state}{_scrub_lat} = $xd;
        # ドラッグ中の即時更新は「操作中のこのセル + 親窓(縦線)」だけに絞る。
        # 他のセル窓は _scrub_stale に保留し、ドラッグが途切れた時(解放/一時停止)に
        # _run_windows のアイドル検出でまとめて追いつかせる(窓が増えても軽い)。
        $win->{dirty} = 1;
        $wm->{main}{dirty} = 1 if $wm->{main} && $wm->{main}{alive};
        $wm->{_scrub_stale} = 1;
    }
    elsif (!defined $wm->{state}{_scrub_lat}) {
        # 選択前の hover のみ読み取りが動く → この窓だけ再描画。
        # 選択後の hover は表示不変(読み取り・マーカは選択潜時で固定)なので
        # 再描画しない(= マウス解放後に動かしても値をキープ + 無駄な再描画抑制)。
        $win->{dirty} = 1;
    }
}

# 親窓の描画: grid_render の返り Figure に、潜時縦線を全 Axes へ後付け。
# render コールバックが Axes に _figure 後ろ盾を張らない層(PGPLOT 互換など、
# _build_panels は axes_list には積むが $ax->_figure を設定しない)でも
# image_frac_to_data / data_to_image_frac が使えるよう、図の全 Axes に
# 後ろ盾を張る。既に張ってあるものは触らない。
sub _bind_axes {
    my ($self, $fig) = @_;
    for my $ax (@{ $fig->axes_list }) {
        $ax->_figure($fig) unless $ax->_figure;
    }
    return $fig;
}

sub _paint_main {
    my ($self, $wm, $win) = @_;
    my $fig = $wm->{grid_render}->($wm->{state}, $win->{w}, $win->{h});
    $self->_bind_axes($fig);
    my $lat = $wm->{state}{_scrub_lat};
    if (defined $lat) {
        my $vs = $wm->{vline};
        for my $ax (@{ $fig->axes_list }) {
            next if $ax->{_scrub_skip};          # 時間軸でないパネルには引かない
            $ax->axvline($lat, color => $vs->{color}, lw => $vs->{lw});
        }
    }
    return $fig;
}

# 子窓の描画: cell_render の返り Figure に、直近点マーカ(ドラッグ時)と
# 右上読み取りテキストを後付け。2パス(1回目でプロット枠確定→座標変換、
# 2回目で装飾込み)。
sub _paint_cell {
    my ($self, $wm, $win) = @_;
    my $fig = $wm->{cell_render}->($win->{ax_idx}, $wm->{state}, $win->{w}, $win->{h});
    $self->_bind_axes($fig);

    my $lat = $wm->{state}{_scrub_lat};        # 共有選択潜時(全窓で同一)
    my $cur = $win->{cursor};
    # 選択も(選択前の)カーソルも無ければ素の図
    return $fig unless defined $lat || $cur;

    my $ax = $fig->axes_list->[0] or return $fig;

    # このセルのライン標本を集める
    my @lines = grep { ($_->{type}//'') eq 'line' } @{ $ax->_queue };
    return $fig unless @lines;

    my ($xmin, $xmax) = ($ax->xmin, $ax->xmax);
    my ($ymin, $ymax) = ($ax->ymin, $ax->ymax);
    my $xr = (defined $xmin && defined $xmax) ? ($xmax - $xmin) : 1;
    my $yr = (defined $ymin && defined $ymax) ? ($ymax - $ymin) : 1;

    # 読み取り位置: 選択があれば「選択潜時(固定・全窓共有)」、無ければライブカーソル。
    # → マウス解放後は選択潜時のまま。動かしても右上のピーク値をキープする。
    my $read_x = defined $lat ? $lat : $cur->{xd};

    # 右上読み取り(x のみスナップ=このセルの波形の read_x での値)。
    {
        my ($li, $pi, $xa, $ya) =
            PDL::Graphics::Cairo::Interactive::Scrub::nearest_on_lines(
                \@lines, $read_x, undef, $xr, $yr);
        if (defined $xa) {
            my $tx = (defined $xmax) ? $xmax : $xa;
            my $ty;
            if ($ax->{_y_reversed}) { $ty = (defined $ymin) ? $ymin : $ya; }
            else                    { $ty = (defined $ymax) ? $ymax : $ya; }
            $ax->text($tx, $ty, $wm->{readout}->($xa, $ya),
                      ha => 'right', va => 'top', fontsize => 11, color => [0.1,0.1,0.1]);
        }
    }

    # マーカ = 共有選択潜時。全セル窓が同じ潜時に赤丸を出す(後から開いた窓も
    # 即座に表示される)。親窓の縦線とも必ず同じ潜時を指す。
    if (defined $lat) {
        my ($li, $pi, $xa, $ya) =
            PDL::Graphics::Cairo::Interactive::Scrub::nearest_on_lines(
                \@lines, $lat, undef, $xr, $yr);
        if (defined $xa) {
            my $ms = $wm->{marker};
            $ax->line([$xa], [$ya],
                      marker => $ms->{marker} // 'o',
                      ms     => $ms->{ms}     // 7,
                      color  => $ms->{color}  // [1,0,0],
                      lw     => 0);
        }
    }
    return $fig;
}

# 子/親窓の File>Save(PDF/SVG)。窓の最新 Figure をベクタ化して返送。
sub _save_window {
    my ($self, $win, $fmt) = @_;
    my $fig = $win->{last_fig} or return;
    my $ext = ($fmt == GSP_SAVE_FMT_SVG) ? 'svg' : 'pdf';
    my $bytes = $self->_figure_to_vector($fig, $ext);
    _send_msg($win->{sock}, GSP_MSG_SAVEDATA, pack('C', $fmt) . $bytes, $win->{seq}++);
}

1;

__END__

=head1 NAME

PDL::Graphics::Cairo::Driver::GS - giza_server backend via GSP protocol

=head1 SYNOPSIS

  # サーバーが無ければ自動起動して表示（窓は残る）
  $fig->show(backend => 'gs');

  # タイトル指定
  $fig->show(backend => 'gs', title => 'My Plot');

  # 手動起動した giza_server に接続（起動はしない）
  $fig->show(backend => 'gs', start => 'connect');

=head1 DESCRIPTION

Cairo surface から C<write_to_png_stream> でメモリ上に PNG を生成し、
Unix ドメインソケット経由で GSP (giza-server protocol) に乗せて
giza_server に送って表示する。テンポラリファイルを一切作らない。

giza_server は Linux では GTK3+Cairo、macOS では Cocoa(NSWindow) で
描画するが、クライアントから見た契約（デバイス名/プロトコル/ソケット
パス）は同一。

=head1 START MODES

  start => 'auto'     居なければ起動、居れば共存（デフォルト）
  start => 'connect'  起動しない。居なければ die
  start => 'launch'   必ず新規起動を試みる

=head1 ENVIRONMENT

  GIZA_SERVER   giza_server バイナリのフルパスを指定

=cut
