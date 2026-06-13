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
use Moo;
use IO::Socket::UNIX;
use POSIX ();
use PDL::Graphics::Cairo::Driver::Cairo;

has width  => (is => 'rw', required => 1);   # rw: RESIZE 逆チャネルで更新する
has height => (is => 'rw', required => 1);
has title  => (is => 'ro', default  => sub { 'PDL::Graphics::Cairo' });
has start  => (is => 'ro', default  => sub { 'auto' });  # auto|connect|launch

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


# Figure → :memory: Cairo → メモリPNG（show() のロジックを再利用）
sub _figure_to_png {
    my ($self, $figure) = @_;
    my $cairo = PDL::Graphics::Cairo::Driver::Cairo->new(
        width => $self->width, height => $self->height, file => ':memory:');
    $figure->_render_to($cairo);
    return $cairo->png_bytes;
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
    _send_msg($sock, GSP_MSG_NEWWIN, pack('L L', $self->width, $self->height), $seq++);
    $self->_recv_ack_sys($sock, 'NEWWIN');
    _send_msg($sock, GSP_MSG_TITLE, $self->title, $seq++);   # fire-and-forget

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

    # 初期フレーム
    {
        my $fig = $render->($state, $self->width, $self->height);
        $self->{_ix}{_last_figure} = $fig;
        _send_msg($sock, GSP_MSG_PNG, $self->_figure_to_png($fig), $seq++);
    }
    $self->_recv_ack_sys($sock, 'PNG', $state);

    $seq = $self->run($sock, $render, $state, $seq);
    delete $self->{_ix};
    # CLOSE は送らない（窓を残す）— ループ終了後にソケットだけ閉じる
    $sock->close;
    return;
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
                my $fig = $render->($state, $self->width, $self->height);
                $self->{_ix}{_last_figure} = $fig if $self->{_ix};
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
                my $fig = $render->($state, $self->width, $self->height);
                $ix->{_last_figure} = $fig;
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
                    for my $ax (@{ $fig->axes_list }) {
                        ($xd, $yd) = $ax->image_frac_to_data($ev->{fx}, $ev->{fy});
                        last if defined $xd;   # プロット枠内の最初の Axes を使う
                    }
                    $state->{_cursor_x} = $xd;
                    $state->{_cursor_y} = $yd;
                } else {
                    $state->{_cursor_x} = undef;
                    $state->{_cursor_y} = undef;
                }
                # 再描画
                my $fig = $render->($state, $self->width, $self->height);
                $ix->{_last_figure} = $fig;
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
