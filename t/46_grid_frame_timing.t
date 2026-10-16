use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::Driver::GS;
use IO::Socket::UNIX;
use File::Temp qw(tempdir);
use POSIX ();
use Time::HiRes ();

# ==================================================================
# show_grid_scrub の送信ループ(_run_windows → _send_frame)を、ACK を返す
# だけの偽の giza-server に対して実際に回す。
#   - verbose のとき、1 コマごとに "frame: build=.. png=.. send=.. gap=.. events=.. age=.." と、
#     ACK が来たときに "ack: ..ms after send" が出る
#   - 偽サーバは PNG を受けてから 30 ms 待って ACK を返すので、ack は 30 ms 以上
#   - verbose でなければ何も出ない(否定対照)
# ==================================================================

plan skip_all => 'needs fork and Unix sockets' if $^O eq 'MSWin32';

use constant {
    MAGIC => 0x47495A41, PNG => 0x10, NEWWIN => 0x12, ACK => 0x21, RESIZE => 0x16,
};
my $N_FRAMES = 4;          # 初期フレーム + RESIZE 3 回
my $ACK_DELAY = 0.03;

sub hdr { pack('L C C S L L', MAGIC, 1, $_[0], 0, $_[1] // 0, 0) }

sub read_n {
    my ($s, $n) = @_;
    my $buf = '';
    while (length($buf) < $n) {
        my $r = sysread($s, $buf, $n - length($buf), length($buf));
        return undef unless $r;
    }
    return $buf;
}

# 偽サーバ: 接続を受け、NEWWIN と PNG に ACK を返す。PNG を $N_FRAMES 枚
# 受けたら閉じる。それまでは PNG の ACK の後に RESIZE を送って再描画させる。
# 接続確認だけの接続(すぐ閉じる)は読み捨てる。
sub fake_server {
    my ($path) = @_;
    my $l = IO::Socket::UNIX->new(Type => SOCK_STREAM(), Local => $path, Listen => 5)
        or die "listen: $!";
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    return ($pid, $l) if $pid;
    my $npng = 0;
    while (my $c = $l->accept) {
        binmode $c;
        while (defined(my $h = read_n($c, 16))) {
            my (undef, undef, $type, undef, $len) = unpack('L C C S L', $h);
            read_n($c, $len) if $len;
            if ($type == NEWWIN) { syswrite($c, hdr(ACK)) }
            elsif ($type == PNG) {
                $npng++;
                Time::HiRes::sleep($ACK_DELAY);
                syswrite($c, hdr(ACK));
                if ($npng >= $N_FRAMES) { close $c; POSIX::_exit(0) }
                syswrite($c, hdr(RESIZE, 8) . pack('L L', 400 + 10 * $npng, 300));
            }
        }
        close $c;
    }
    POSIX::_exit(0);
}

sub run_session {
    my ($verbose) = @_;
    my $dir  = tempdir(CLEANUP => 1);
    local $ENV{GIZA_SERVER_SOCK} = "$dir/gs.sock";
    my ($pid, $l) = fake_server($ENV{GIZA_SERVER_SOCK});
    close $l;

    my $gs = PDL::Graphics::Cairo::Driver::GS->new(
        width => 400, height => 300, start => 'connect', verbose => $verbose);
    my $out = '';
    {
        open my $fh, '>', \$out or die;
        my $old = select $fh;
        local $| = 1;
        $gs->show_grid_scrub(
            grid_render => sub {
                my ($state, $w, $h) = @_;
                my $fig = figure(width => $w, height => $h);
                my $ax  = $fig->add_subplot(1, 1, 1);
                $ax->plot(sequence(100), sin(sequence(100) / 10));
                return $fig;
            },
            cell_render => sub { figure(width => $_[2], height => $_[3]) },
        );
        select $old;
    }
    waitpid($pid, 0);
    return $out;
}

{
    my $out = run_session(1);
    my @frame = $out =~ /^\s*frame: build=(\d+)ms\s+png=(\d+)ms\s+send=(\d+)ms\s+gap=\S+\s+events=\d+\s+age=\S+$/mg;
    # gap / events / age: 初回は前のコマも入力も無いので '-' と 0。
    # 2 コマ目以降は、偽サーバが ACK(30 ms 待ち)の後に RESIZE を 1 つ送るので、
    # events=1、gap は 30 ms 以上、age は gap より小さい。
    my @rest = $out =~ /^\s*frame: .*gap=(\S+)\s+events=(\d+)\s+age=(\S+)$/mg;
    my @first = splice(@rest, 0, 3);
    is_deeply(\@first, ['-', 0, '-'], 'first frame: gap and age are "-", events 0');
    my ($ok, @seen) = (1);
    while (my ($gap, $ev, $age) = splice(@rest, 0, 3)) {
        my ($g) = $gap =~ /^(\d+)ms$/; my ($a_ms) = $age =~ /^(\d+)ms$/;
        push @seen, "gap=$gap events=$ev age=$age";
        $ok = 0 unless defined $g && defined $a_ms && $ev == 1
                    && $g >= 1000 * $ACK_DELAY - 1 && $a_ms <= $g;
    }
    ok($ok && @seen == $N_FRAMES - 1, "later frames: events=1, gap >= 30 ms, age <= gap (@seen)");
    my @ack   = $out =~ /^\s*ack: (\d+)ms after send$/mg;
    is(scalar(@frame) / 3, $N_FRAMES, "verbose: one 'frame:' line per frame ($N_FRAMES)");
    is(scalar(@ack), $N_FRAMES, "verbose: one 'ack:' line per frame ($N_FRAMES)");
    ok(!grep({ $_ < 1000 * $ACK_DELAY - 1 } @ack),
       "ack times include the server's ${\ (1000 * $ACK_DELAY)} ms delay (@ack)");
    my @png = $out =~ /^\s*png: cairo_render=/mg;
    is(scalar(@png), $N_FRAMES, "the 'png:' line is still printed once per frame");
}

{
    my $out = run_session(0);
    unlike($out, qr/frame:|ack:|png:/, 'not verbose: nothing is printed');
}

done_testing;
