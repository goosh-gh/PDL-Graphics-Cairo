use strict;
use warnings;
use Test::More;
use PDL;
use Test::PDL qw(is_pdl);
use PDL::Graphics::Cairo::Driver::GS3D;
use IO::Socket::UNIX;
use IO::Select;
use File::Temp qw(tempdir);
use POSIX ();
use Time::HiRes ();

# ==================================================================
# Driver::GS3D::play: vertex colours over time, in the window.
#  - the frame at a time is the last one whose latency is <= the start
#    latency + elapsed * speed (held, like a USDA's time samples); past the
#    end it loops (the last frame shown for one step) or stops;
#  - pause shifts the start by the paused time; space toggles it;
#  - _play_tick replaces the colours only when the frame changes (a PDL
#    slice, or the code ref's result for ($i, $t_ms));
#  - the latency label "t = .. ms" is in the stage A frame and the stage B
#    overlay;
#  - stage B against a fake server: 3D_COLORS frames arrive over time and end
#    on the last frame when loop => 0.
# ==================================================================

my $GS3D = 'PDL::Graphics::Cairo::Driver::GS3D';
my $verts = pdl([[40,0,0],[-40,0,0],[0,40,0],[0,-40,0],[0,0,40],[0,0,-40]])->transpose;
my $faces = pdl(long, [[0,2,4],[2,1,4],[1,3,4],[3,0,4],[2,0,5],[1,2,5],[3,1,5],[0,3,5]])->transpose;
sub scene { { mesh => { verts => $verts, faces => $faces } } }
sub drv { $GS3D->new(width => 400, height => 300, start => 'connect', scene => scene(), render => 'zbuffer', @_) }

# ---- argument checks ----
{
    my $d = drv();
    ok(!eval { $d->play(colors => zeroes(6, 3, 2)); 1 } && $@ =~ /times/, 'times required');
    ok(!eval { $d->play(times => [0, 1]); 1 } && $@ =~ /colors/, 'colors required');
    ok(!eval { $d->play(times => [0, 1], colors => zeroes(5, 3, 2)); 1 } && $@ =~ /\(6,3,2\)/, 'colour dims checked');
    ok(!eval { $d->play(times => [2, 1], colors => zeroes(6, 3, 2)); 1 } && $@ =~ /ascending/, 'times must ascend');
    ok(!eval { $d->play(times => [0, 1], colors => zeroes(6, 3, 2), speed => 0); 1 } && $@ =~ /speed/, 'speed > 0');
    my $w = '';
    { local $SIG{__WARN__} = sub { $w .= $_[0] };
      $GS3D->new(width => 400, height => 300, start => 'connect', scene => scene(), stage => 'A')->play(times => [0], colors => zeroes(6, 3, 1)); }
    like($w, qr/zbuffer/, "stage A with render 'line' warns that colours need zbuffer");
}

# ---- the frame for a time ----
{
    my $d = drv();
    $d->play(times => sequence(500), colors => zeroes(6, 3, 500));             # 0..499 ms, 1 ms steps
    my $at = sub { $d->_play_index(100 + $_[0]) };                               # start = 100 s
    is($at->(0), 0, 'start: frame 0');
    is($at->(0.25), 250, 'real time: 250 ms after the start, frame 250');
    is($at->(0.4995), 499, 'last frame');
    is($at->(0.5), 0, 'loop: one step after the last frame, back to frame 0');
    is($at->(0.7504), 250, 'second round');
    ok($d->_play_running, 'still running when looping');

    my $s = drv();
    $s->play(times => [ map { $_ * 2 } 0 .. 99 ], colors => zeroes(6, 3, 100), speed => 0.1, loop => 0);
    is($s->_play_index(10), 0, 'speed 0.1: start');
    is($s->_play_index(11), 50, 'speed 0.1: 1 s later = 100 ms = frame 50 (2 ms steps)');
    is($s->_play_index(11.0049), 50, 'held between samples (no blending)');
    is($s->_play_index(13), 99, 'loop 0: past the end, the last frame');
    ok(!$s->_play_running, '... and stopped');

    my $u = drv();
    $u->play(times => [10, 20, 50], colors => zeroes(6, 3, 3));                 # uneven, not from 0
    is_deeply([ map { $u->_play_index(5 + $_) } 0, 0.0099, 0.010, 0.039, 0.040 ], [0, 0, 1, 1, 2],
              'uneven times: the last frame at or before the latency');
}

# ---- pause ----
{
    my $d = drv();
    $d->play(times => sequence(10), colors => zeroes(6, 3, 10));
    $d->_play_index(50);
    $d->pause(1);
    ok($d->pause && !$d->_play_running, 'paused');
    Time::HiRes::sleep(0.2);
    $d->pause(0);
    my $shift = $d->{_play}{start} - 50;
    ok($shift > 0.15 && $shift < 0.5, sprintf('resume shifts the start by the paused time (%.3f s)', $shift));
    $d->_client_key(ord ' ');
    ok($d->pause, 'space pauses');
    $d->_client_key(ord ' ');
    ok(!$d->pause, 'space resumes');
}

# ---- colours per frame, the label ----
{
    my $col = sequence(6, 3, 4) / 72;
    my $d = drv();
    $d->play(times => [0, 10, 20, 30], colors => $col, speed => 1);
    $d->{_play}{start} = Time::HiRes::time() - 0.015;                            # now: frame 1
    ok($d->_play_tick, 'tick: the frame changed');
    is_pdl($d->{scene}{mesh}{vcolors}, $col->slice(':,:,(1)'), 'vcolors = frame 1 of the colours');
    ok(!$d->_play_tick, 'tick again in the same frame: nothing to do');
    is($d->_play_label, 't = 10 ms', 'label');
    $d->pause(1);
    is($d->_play_label, 't = 10 ms  (paused)', 'label when paused');

    my @calls;
    my $c = drv();
    $c->play(times => [0, 5], colors => sub { push @calls, [@_]; ones(6, 3) * $_[0] / 2 });
    $c->{_play}{start} = Time::HiRes::time() - 0.006;
    $c->_play_tick;
    is_deeply(\@calls, [[1, 5]], 'code ref called with (index, latency)');
    is_pdl($c->{scene}{mesh}{vcolors}, ones(6, 3) * 0.5, '... and its colours used');

    # stage A frame and stage B overlay carry the label
    my @sent;
    { no warnings 'redefine'; local *PDL::Graphics::Cairo::Driver::GS::_send_msg = sub { push @sent, $_[2] };
      $c->{_ix3d} = { sock => undef, seq => 0 }; $c->_send_3d_frame; delete $c->{_ix3d}; }
    like($sent[0], qr/t = 5 ms/, 'stage A frame: the latency label');
    like($c->_overlay_payload, qr/t = 5 ms/, 'stage B overlay: the latency label');
}

# ---- stage B: 3D_COLORS over time against a fake server ----
SKIP: {
    skip 'needs fork and Unix sockets', 4 if $^O eq 'MSWin32';
    use constant { MAGIC => 0x47495A41, PING => 0x01, PONG => 0x02, NEWWIN => 0x12, ACK => 0x21,
                   COLORS => 0x2A, OVERLAY => 0x2C };
    my $hdr = sub { pack('L C C S L L', MAGIC, 1, $_[0], 0, $_[1] // 0, 0) };
    my $read_n = sub { my ($s, $n) = @_; my $b = '';
        while (length $b < $n) { my $r = sysread($s, $b, $n - length $b, length $b); return undef unless $r } $b };
    my $read_msg = sub { my ($c) = @_; my $h = $read_n->($c, 16) // return;
        my (undef, undef, $t, undef, $len) = unpack('L C C S L', $h); ($t, $len ? $read_n->($c, $len) : '') };
    my $dir = tempdir(CLEANUP => 1);
    local $ENV{GIZA_SERVER_SOCK} = "$dir/gs.sock";
    local $ENV{GS3D_STAGE};
    my $l = IO::Socket::UNIX->new(Type => SOCK_STREAM(), Local => $ENV{GIZA_SERVER_SOCK}, Listen => 5) or die $!;
    my $pid = fork() // die;
    unless ($pid) {
        open my $out, '>', "$dir/log" or POSIX::_exit(1);
        $out->autoflush(1);
        my $c;
        ACCEPT: while ($c = $l->accept) {
            while (my ($t, $p) = $read_msg->($c)) {
                if ($t == PING)   { syswrite($c, $hdr->(PONG, 4) . pack('V', 1)) }
                if ($t == NEWWIN) { syswrite($c, $hdr->(ACK)); last ACCEPT }
            }
        }
        POSIX::_exit(1) unless $c;
        my $sel = IO::Select->new($c);
        my $t0 = Time::HiRes::time();
        while (Time::HiRes::time() - $t0 < 0.8 && $sel->can_read(0.8)) {          # 200 ms of frames, then quiet
            my ($t, $p) = $read_msg->($c) or last;
            if ($t == COLORS) {
                printf $out "colors %.3f %d\n", Time::HiRes::time() - $t0, unpack('C', substr($p, 5, 1));
                syswrite($c, $hdr->(ACK));
            } elsif ($t == OVERLAY) {
                my ($lab) = $p =~ /(t = \d+ ms)/;
                print $out "label $lab\n" if $lab;
                syswrite($c, $hdr->(ACK));
            } elsif ($t == 0x29) { syswrite($c, $hdr->(ACK)) }
        }
        close $c;
        POSIX::_exit(0);
    }
    close $l;
    my $d = drv();
    # frame i: every vertex red = i (0..199), 1 ms apart, played once
    $d->play(times => sequence(200), colors => sub { ones(6, 3) * $_[0] / 255 }, loop => 0);
    { local *STDERR; open STDERR, '>', '/dev/null'; $d->run; }
    waitpid($pid, 0);
    open my $in, '<', "$dir/log" or die;
    my (@col, @lab);
    while (<$in>) { push @col, [ split ' ', (split / /, $_, 2)[1] ] if /^colors/; push @lab, $1 if /^label (.*)/ }
    ok(@col >= 5, sprintf('several 3D_COLORS frames (%d) over 200 ms', scalar @col));
    is($col[-1][1], 199, 'the last frame sent is the last one');
    ok($col[-1][0] > 0.15 && $col[-1][0] < 0.6, sprintf('it arrived about 200 ms after the start (%.3f s)', $col[-1][0]));
    is($lab[-1], 't = 199 ms', 'the overlay label ends on the last latency');
}

done_testing;
