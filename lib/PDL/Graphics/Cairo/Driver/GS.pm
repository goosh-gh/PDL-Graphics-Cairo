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

has width  => (is => 'ro', required => 1);
has height => (is => 'ro', required => 1);
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
};

sub _sock_path { "/tmp/giza_server_$<.sock" }

# ------------------------------------------------------------------
# サーバーバイナリ探索
# ------------------------------------------------------------------
sub _find_server {
    return $ENV{GIZA_SERVER}
        if $ENV{GIZA_SERVER} && -x $ENV{GIZA_SERVER};
    use File::Basename qw(dirname);
    my $base = dirname(__FILE__);
    # リポジトリ同梱のビルド済みバイナリ（開発時）
    my $dev = "$base/../../../../../giza-server/giza_server";
    if (-x $dev) {
        require Cwd;
        return Cwd::realpath($dev);
    }
    for my $p (qw(/usr/local/bin/giza_server /opt/local/bin/giza_server)) {
        return $p if -x $p;
    }
    return undef;
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

# ------------------------------------------------------------------
# show($figure) — メモリPNGを作って giza_server に送る
# ------------------------------------------------------------------
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
