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
# Driver::GS3D stage B (giza-server viewer/gsp_3d.h, 0x29-0x2F).
#  - run asks for the capabilities with a PING carrying u32 1. An empty PONG
#    (an older server) means stage A: the first message after NEWWIN is a
#    3D_FRAME. A 4-byte PONG with bit 0 means stage B: 3D_MESH (ACKed) and
#    3D_VIEW, then the driver only answers what the server sends.
#  - GS3D_STAGE=A, stage => 'A', and a scene without a mesh stay in stage A.
#  - In stage B: 3D_POSE updates the pose copy, 3D_PICKV left adds a seed
#    (on_pick gets the vertex), right removes the nearest seed, 3D_HOVERV gives
#    on_hover the vertex (the last of a burst), 3D_INPUT 'u' undoes a seed.
#    set_vertex_colors and view() called from on_pick send 3D_COLORS (waiting
#    for its ACK while other messages arrive) and 3D_VIEW.
#  - view(): named views, elev/azim, toward, look_at; projection; pose.
# ==================================================================

plan skip_all => 'needs fork and Unix sockets' if $^O eq 'MSWin32';

use constant {
    MAGIC => 0x47495A41, PING => 0x01, PONG => 0x02, NEWWIN => 0x12, ACK => 0x21,
    F3D => 0x24, INPUT => 0x25, MESH => 0x29, COLORS => 0x2A, VIEW => 0x2B,
    OVERLAY => 0x2C, POSE => 0x2D, PICKV => 0x2E, HOVERV => 0x2F,
};
my $GS3D = 'PDL::Graphics::Cairo::Driver::GS3D';

sub hdr { pack('L C C S L L', MAGIC, 1, $_[0], 0, $_[1] // 0, 0) }
sub msg { my ($t, $p) = @_; $p //= ''; hdr($t, length $p) . $p }

sub read_n {
    my ($s, $n) = @_;
    my $buf = '';
    while (length($buf) < $n) {
        my $r = sysread($s, $buf, $n - length($buf), length($buf));
        return undef unless $r;
    }
    return $buf;
}

sub read_msg {
    my ($c) = @_;
    my $h = read_n($c, 16) // return;
    my (undef, undef, $type, undef, $len) = unpack('L C C S L', $h);
    my $p = $len ? read_n($c, $len) : '';
    return ($type, $p);
}

# An octahedron, 0-based faces, outward counter-clockwise.
my $verts = pdl([[ 40, 0, 0], [-40, 0, 0], [0, 40, 0], [0, -40, 0], [0, 0, 40], [0, 0, -40]])->transpose;
my $faces = pdl(long, [[0,2,4],[2,1,4],[1,3,4],[3,0,4],[2,0,5],[1,2,5],[3,1,5],[0,3,5]])->transpose;
my $vcol  = pdl([[1,0,0],[0,1,0],[0,0,1],[1,1,0],[0,1,1],[1,0,1]])->transpose * 0.8;

sub scene { { mesh => { verts => $verts, faces => $faces, vcolors => $vcol } } }

# Fake giza-server. $caps: undef = empty PONG, else the u32 mask. $script runs on
# the session connection after NEWWIN; it writes "key value" lines to $log.
sub fake_server {
    my ($path, $log, $caps, $script) = @_;
    my $l = IO::Socket::UNIX->new(Type => SOCK_STREAM(), Local => $path, Listen => 5)
        or die "listen: $!";
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    return ($pid, $l) if $pid;
    open my $out, '>', $log or POSIX::_exit(1);
    binmode $out;
    $out->autoflush(1);
    my $marked;
    my $say = sub {
        $marked = 1 if $_[0] eq 'mark';
        print $out "order ", ($_[0] eq 'mark' ? $_[1] : $_[0]), "\n" if $marked && ($_[0] eq 'mark' || $_[0] eq 'ovl');
        print $out join(' ', @_), "\n";
    };
    my $c;
    # The driver first connects once to see that a server is there and closes.
    ACCEPT: while ($c = $l->accept) {
        binmode $c;
        while (my ($t, $p) = read_msg($c)) {
            if ($t == PING) {
                $say->('ping', length $p, length $p == 4 ? unpack('V', $p) : '-');
                syswrite($c, defined $caps ? msg(PONG, pack('V', $caps)) : msg(PONG));
            } elsif ($t == NEWWIN) {
                syswrite($c, msg(ACK));
                last ACCEPT;
            }
        }
        close $c;
    }
    POSIX::_exit(1) unless $c;
    $script->($c, $say);
    close $c;
    POSIX::_exit(0);
}

# Stage A scripts: report the first message type after NEWWIN. Stage A sends
# the next frame as soon as the ACK comes, so read that one too and close
# without an ACK: the driver then sees the end while it waits (closing right
# after the ACK would make its next write fail with SIGPIPE).
my $first_type = sub {
    my ($c, $say) = @_;
    my ($t) = read_msg($c);
    $say->('first', sprintf('0x%02X', $t // 0));
    return unless defined $t;
    syswrite($c, msg(ACK));
    read_msg($c);
};

sub session {
    my (%o) = @_;
    my $dir = tempdir(CLEANUP => 1);
    local $ENV{GIZA_SERVER_SOCK} = "$dir/gs.sock";
    local $ENV{GS3D_STAGE} = $o{env};
    my $log = "$dir/log";
    my ($pid, $l) = fake_server($ENV{GIZA_SERVER_SOCK}, $log, $o{caps}, $o{script} // $first_type);
    close $l;
    my $drv = $GS3D->new(width => 400, height => 300, start => 'connect',
                         scene => $o{scene} // scene(), %{ $o{args} // {} });
    $o{setup}->($drv) if $o{setup};
    my @warn;
    {
        local $SIG{__WARN__} = sub { push @warn, $_[0] };
        local *STDERR;                       # [GS3D pick] lines
        open STDERR, '>', '/dev/null';
        $drv->run;
    }
    waitpid($pid, 0);
    open my $in, '<', $log or die;
    my %got;
    while (<$in>) { chomp; my ($k, @v) = split / /; push @{ $got{$k} }, @v ? join(' ', @v) : '' }
    return (\%got, $drv, \@warn);
}

# ---- capability check and the choice of stage ----
{
    my ($got, $drv) = session(caps => undef);
    is_deeply($got->{ping}, ['4 1'], 'run sends a PING with u32 1 before NEWWIN');
    is_deeply($got->{first}, ['0x24'], 'empty PONG (older server): stage A, a 3D_FRAME');
    is($drv->{_stage}, 'A', 'stage A recorded');
}
{
    my ($got) = session(caps => 1, env => 'A');
    is_deeply($got->{first}, ['0x24'], 'GS3D_STAGE=A keeps stage A with a stage B server');
}
{
    my ($got) = session(caps => 1, args => { stage => 'A' });
    is_deeply($got->{first}, ['0x24'], "stage => 'A' keeps stage A");
}
{
    my ($got) = session(caps => 1, scene => { points => pdl([[0, 0, 70]])->transpose,
                                               colors => pdl([[1, 1, 1]])->transpose });
    is_deeply($got->{first}, ['0x24'], 'a scene without a mesh stays in stage A');
}
{
    my ($got, undef, $warn) = session(caps => undef, args => { stage => 'B' });
    is_deeply($got->{first}, ['0x24'], "stage => 'B' with an older server falls back to A");
    ok(scalar(grep { /does not speak stage B/ } @$warn), '... and warns');
}
{
    my ($got) = session(caps => 0, args => { stage => 'B' });
    is_deeply($got->{first}, ['0x24'], 'a 4-byte PONG without bit 0 is stage A');
}

# ---- stage B ----
my %pose1 = (q => [ $GS3D->can('_view_quat')->(0, 90) ], zoom => 1.5, persp => 0);
my $newcol = pdl([[0.1,0.2,0.3],[0.4,0.5,0.6],[0.7,0.8,0.9],[1,1,1],[0,0,0],[0.5,0.5,0.5]])->transpose;
# Where vertex 2 (the first seed) is on screen after view('front') with the
# pose's zoom and orthographic projection: the right click there removes it.
my ($rfx, $rfy) = do {
    my $d = $GS3D->new(width => 400, height => 300, start => 'connect', scene => scene(),
                       pivot => [1, 2, 3]);
    $d->view('front');
    @{$d}{qw(zoom perspective)} = (1.5, 0);
    my ($sx, $sy) = $d->_project($d->_rotate_points($d->_rotation, $verts->slice('2:2')));
    ($sx->sclr / 400, $sy->sclr / 300);
};
my $stage_b_script = sub {
    my ($c, $say) = @_;
    my $hexp = sub { unpack('H*', $_[0]) };
    # The next message that is not a 3D_OVERLAY; overlays are logged and ACKed.
    my $next = sub {
        while (my ($t, $p) = read_msg($c)) {
            return ($t, $p) unless $t == OVERLAY;
            $say->('ovl', $hexp->($p));
            syswrite($c, msg(ACK));
        }
        return;
    };
    # Wait $secs, ACKing overlays (instead of sleeping: the driver waits for them).
    my $drain = sub {
        my ($secs) = @_;
        my $sel = IO::Select->new($c);
        my $end = Time::HiRes::time() + $secs;
        while ((my $left = $end - Time::HiRes::time()) > 0) {
            next unless $sel->can_read($left);
            my ($t, $p) = read_msg($c) or return;
            next unless $t == OVERLAY;
            $say->('ovl', $hexp->($p));
            syswrite($c, msg(ACK));
        }
    };
    my ($t, $p) = $next->();
    $say->('mesh_type', sprintf('0x%02X', $t)); $say->('mesh', $hexp->($p));
    syswrite($c, msg(ACK));
    ($t, $p) = $next->();
    $say->('view_type', sprintf('0x%02X', $t)); $say->('view', $hexp->($p));
    syswrite($c, msg(POSE, pack('f<4 f< f<3 C', @{ $pose1{q} }, $pose1{zoom}, 1, 2, 3, $pose1{persp})));
    # A click on vertex 2. on_pick (first seed) sends 3D_COLORS and 3D_VIEW;
    # a burst of hovers is sent before the ACK, so it arrives while the driver
    # waits for the ACK and must be kept for later.
    syswrite($c, msg(PICKV, pack('C V C f< f<', 0, 2, 1, 0.5, 0.5)));
    ($t, $p) = $next->();
    $say->('colors_type', sprintf('0x%02X', $t)); $say->('colors', $hexp->($p));
    syswrite($c, msg(HOVERV, pack('C V f< f<', 0, 3, 0.4, 0.4))
               . msg(HOVERV, pack('C V f< f<', 0, 4, 0.4, 0.4)));
    select(undef, undef, undef, 0.1);
    syswrite($c, msg(ACK));
    ($t, $p) = $next->();
    $say->('view2_type', sprintf('0x%02X', $t)); $say->('view2', $hexp->($p));
    syswrite($c,
          msg(PICKV, pack('C V C f< f<', 0, 1, 1, 0.5, 0.5))            # seed vertex 1
        . msg(INPUT, pack('f< f< f< C C', 0, 0, 0, 2, ord 'u'))          # undo it
        . msg(PICKV, pack('C V C f< f<', 0, 0xFFFFFFFF, 1, 0.0, 0.0))   # nothing under the click
        . msg(PICKV, pack('C V C f< f<', 0, 5, 1, 0.5, 0.5))            # seed vertex 5
        . msg(PICKV, pack('C V C f< f<', 0, 0xFFFFFFFF, 2, $rfx, $rfy))); # right click on vertex 2
    # Later, on its own: the pointer leaves the mesh. (Sent with the burst
    # above it would be the last hover of the same batch, and the kept hovers
    # 3 and 4 would rightly never reach on_hover.)
    $drain->(0.3);
    # A pose alone changes nothing in the overlay: no 3D_OVERLAY may follow.
    # (The same pose as view('front') left, so pose() stays as checked below.)
    $say->('mark', 'pose-alone');
    syswrite($c, msg(POSE, pack('f<4 f< f<3 C', $GS3D->can('_view_quat')->(0, 180), 1.5, 1, 2, 3, 0)));
    $drain->(0.3);
    $say->('mark', 'hover-off');
    syswrite($c, msg(HOVERV, pack('C V f< f<', 0, 0xFFFFFFFF, 0, 0)));
    $drain->(0.3);
};

# Unpack a 3D_OVERLAY payload (giza-server viewer/gsp_3d.h).
sub decode_overlay {
    my ($p) = @_;
    my ($eps, $np) = unpack('f< V', $p);
    my $o = 8;
    my @pts = map { [ unpack('f<4 C5', substr($p, $o + 21 * $_, 21)) ] } 0 .. $np - 1;
    $o += 21 * $np;
    my $nl = unpack('V', substr($p, $o, 4)); $o += 4;
    my @lns = map { [ unpack('f<7 C5', substr($p, $o + 33 * $_, 33)) ] } 0 .. $nl - 1;
    $o += 33 * $nl;
    my $nt = unpack('V', substr($p, $o, 4)); $o += 4;
    my @lab;
    for (1 .. $nt) {
        my @h = unpack('f<5 C3 C C', substr($p, $o, 25)); $o += 25;
        push @lab, [ @h[0 .. 8], substr($p, $o, $h[9]) ];
        $o += $h[9];
    }
    return { eps => $eps, points => \@pts, lines => \@lns, labels => \@lab, used => $o, len => length $p };
}
{
    my (@picked, @hovered);
    my ($got, $drv) = session(
        caps   => 1, script => $stage_b_script,
        args   => {
            pivot    => [1, 2, 3],
            on_pick  => sub { my ($i, $x, $y, $z, $n) = @_; push @picked, $i;
                              if ($n == 0) { $_[5]{drv}->set_vertex_colors($newcol); $_[5]{drv}->view('front') }
                              return "P$i" },
            on_hover => sub { push @hovered, $_[0]; "area$_[0]" },
        },
        setup  => sub { my ($d) = @_; my $cb = $d->{on_pick};
                        $d->{on_pick} = sub { $cb->(@_[0 .. 4], { drv => $d }) } },
    );
    is($drv->{_stage}, 'B', '4-byte PONG with bit 0 and a mesh: stage B');
    is_deeply([ @{$got}{qw(mesh_type view_type colors_type view2_type)} ],
              [ ['0x29'], ['0x2B'], ['0x2A'], ['0x2B'] ], 'MESH, VIEW, COLORS, VIEW in order')
        or diag explain $got;

    # 3D_MESH payload
    my $m = pack('H*', $got->{mesh}[0]);
    my ($id, $flags, $nv, $nf) = unpack('C C V V', $m);
    is_deeply([$id, $flags, $nv, $nf], [0, 0x01, 6, 8], 'mesh header: id 0, normals, ccw, 6 vertices, 8 faces');
    is(length $m, 10 + 6 * 28 + 8 * 12, 'mesh payload length');
    my $off = 10;
    my $pos = pdl(float, [ unpack('f<18', substr($m, $off, 72)) ])->reshape(3, 6); $off += 72;
    my $nrm = pdl(float, [ unpack('f<18', substr($m, $off, 72)) ])->reshape(3, 6); $off += 72;
    my $rgba = pdl(byte, [ unpack('C24', substr($m, $off, 24)) ])->reshape(4, 6); $off += 24;
    my $fc  = pdl(long, [ unpack('V24', substr($m, $off, 96)) ])->reshape(3, 8);
    is_pdl($pos, $verts->transpose->float, 'mesh positions (model coordinates)');
    is_pdl($nrm, ($verts / 40)->transpose->float, { atol => 1e-6, test_name => 'outward unit normals' });
    is_pdl($rgba->slice('0:2'), ($vcol * 255 + 0.5)->byte->transpose, 'unshaded vertex colours');
    is_pdl($rgba->slice('(3)'), pdl(byte, (255) x 6), 'alpha 255');
    is_pdl($fc, $faces->transpose, 'faces, 0-based');

    my @v1 = unpack('f<4 f< f<3 C', pack('H*', $got->{view}[0]));
    is_deeply([ map { sprintf '%.4f', $_ } @v1 ],
              [ map { sprintf '%.4f', $_ } 0, 0, 0, 1, 1, 1, 2, 3, 1 ],
              'first VIEW: Cz from above, zoom 1, the pivot, perspective');

    my $cp = pack('H*', $got->{colors}[0]);
    is_deeply([ unpack('C V', $cp) ], [0, 6], 'COLORS header');
    is_pdl(pdl(byte, [ unpack('C24', substr($cp, 5)) ])->reshape(4, 6)->slice('0:2'),
           ($newcol * 255 + 0.5)->byte->transpose, 'COLORS: the new colours');
    is_pdl($drv->{scene}{mesh}{vcolors}, $newcol, 'vcolors replaced');

    my @v2 = unpack('f<4 f< f<3 C', pack('H*', $got->{view2}[0]));
    my @qf = $GS3D->can('_view_quat')->(0, 180);
    is_deeply([ map { sprintf '%.4f', $_ } @v2 ],
              [ map { sprintf '%.4f', $_ } @qf, 1.5, 1, 2, 3, 0 ],
              "view('front') from on_pick: front quaternion, the pose's zoom and projection");

    my %pose = $drv->pose;
    is_deeply([ map { sprintf '%.4f', $_ } @{ $pose{qrot} }, $pose{zoom} ],
              [ map { sprintf '%.4f', $_ } @qf, 1.5 ], 'pose: the last view');
    is($pose{projection}, 'ortho', 'pose: orthographic from 3D_POSE');
    is_deeply(\@picked, [2, 1, 5], 'on_pick got the vertices of the left clicks');
    is_deeply([ map { $_->{index} } @{ $drv->{seeds} } ], [5],
              "'u' undid seed 1, the right click removed seed 2");
    is($drv->{seeds}[0]{label}, 'P5', 'seed label from on_pick');
    is_deeply(\@hovered, [4], 'on_hover: only the last hover of the burst');
    is($drv->{readout}, undef, 'hover off the mesh clears the readout');

    # 3D_OVERLAY: sent after the first VIEW, then again whenever it changes
    my @ovl = map { decode_overlay(pack('H*', $_)) } @{ $got->{ovl} || [] };
    ok(@ovl >= 3, 'overlays sent: ' . scalar @ovl);
    ok(!grep({ $_->{used} != $_->{len} } @ovl), 'every overlay is read to its last byte');
    my @txt = map { join '|', map { $_->[9] } @{ $_->{labels} } } @ovl;
    is($txt[0], 'X|Y|Z', 'first overlay: the axis labels only');
    is_deeply([ map { [ @$_[3 .. 6], $_->[11] ] } @{ $ovl[0]{lines} } ],
              [ [100, 0, 0, 1, 0x06], [0, 100, 0, 1, 0x06], [0, 0, 100, 1, 0x06] ],
              'axes: lines to the tips, width 1, on top with arrow heads');
    is(sprintf('%.1f', $ovl[0]{eps}), '2.0', 'depth_eps 2 mm');
    # (which seeds share an overlay with the readout depends on how the messages batch)
    ok(scalar(grep { $_ eq 'X|Y|Z|1:P2' } @txt), 'an overlay with seed 1:P2') or diag explain \@txt;
    ok(scalar(grep { /\|x=0\.0 y=0\.0 z=40\.0  area4$/ } @txt), 'an overlay with the readout of vertex 4')
        or diag explain \@txt;
    for my $i (1 .. $#txt) {
        if ($txt[$i] eq $txt[$i - 1] && unpack('H*', join '', map { pack 'f<4', @$_[0 .. 3] } @{ $ovl[$i]{points} })
                                     eq unpack('H*', join '', map { pack 'f<4', @$_[0 .. 3] } @{ $ovl[$i - 1]{points} })) {
            fail("overlay $i repeats overlay " . ($i - 1)); last;
        }
    }
    is_deeply($got->{order}, [ 'pose-alone', 'hover-off', 'ovl' ],
              'nothing re-sent after a pose alone; the hover leaving the mesh re-sends')
        or diag explain $got->{order};
    my $last = $ovl[-1];
    is($txt[-1], 'X|Y|Z|1:P5', 'last overlay: seed 5, no readout');
    is_deeply([ map { [ map { sprintf '%g', $_ } @$_ ] } @{ $last->{points} } ],
              [ [ 0, 0, -40, 7, 80, 255, 120, 255, 0 ] ],
              'seed point: vertex 5, radius 7, first palette colour, hidden by the mesh');
    is_deeply([ @{ $last->{labels}[3] }[0 .. 4, 8] ], [ 0, 0, -40, 8, 8, 0 ], 'seed label at (8,8) from the point');
}

# ---- 3D_OVERLAY payload from a full scene (no server) ----
{
    my $sc = { %{ scene() },
               points => pdl([[0, 0, 60], [30, -30, 30]])->transpose,
               colors => pdl([[1, 1, 1], [1, 0.5, 0]])->transpose,
               labels => ['Cz', "\x{96fb}\x{6975}"],
               lines  => pdl([[0, 0, 0, 50, 50, 50, 1, 0, 0]])->transpose,
               colorbar => { colors => [[0, 0, 255], [255, 0, 0]], ticks => [[0, '0'], [1, '1']], title => 'p' } };
    my $d = $GS3D->new(width => 400, height => 300, start => 'connect', scene => $sc);
    $d->{readout} = 'x=1';
    my $o = decode_overlay($d->_overlay_payload);
    is($o->{used}, $o->{len}, 'full overlay read to its last byte');
    is_deeply([ map { $_->[9] } @{ $o->{labels} } ],
              [ 'X', 'Y', 'Z', 'Cz', "\xE9\x9B\xBB\xE6\xA5\xB5", 'x=1', '0', '1', 'p' ],
              'labels: axes, points (UTF-8 bytes), readout, colour bar');
    is_deeply([ map { [ map { sprintf '%g', $_ } @$_ ] } @{ $o->{points} } ],
              [ [0, 0, 60, 4, 255, 255, 255, 255, 0], [30, -30, 30, 4, 255, 127, 0, 255, 0] ],
              'electrodes: model coordinates, radius 4, colours as stage A, depth-tested');
    is_deeply([ @{ $o->{labels}[3] }[3 .. 8] ], [6, -6, 255, 255, 200, 0], 'electrode label offset (6,-6)');
    is_deeply([ @{ $o->{labels}[5] }[0, 1, 8] ], [12, 20, 1], 'readout in window pixels at (12,20)');
    is_deeply([ map { sprintf '%g', $_ } @{ $o->{lines}[3] } ], [ 0, 0, 0, 50, 50, 50, 1, 255, 0, 0, 200, 0 ],
              'scene line: model coordinates, alpha 200, depth-tested');
    my @band = grep { $_->[11] == 0x09 } @{ $o->{lines} };
    my ($cl) = $d->_colorbar_items;
    is(scalar @band, scalar(grep { $_->{band} } @$cl), 'colour bar rows as screen bands');
    is_deeply([ @{ $band[0] }[0, 1, 3, 6] ], [ $cl->[0]{x0}, $cl->[0]{y0}, $cl->[0]{x1}, 1 ], 'band position as stage A');
    my $top = decode_overlay($GS3D->new(width => 400, height => 300, start => 'connect', scene => $sc,
                                        overlay_depth => 0, overlay_eps => 5)->_overlay_payload);
    ok(!grep({ $_->[8] != 0x02 } @{ $top->{points} }) && $top->{lines}[3][11] == 0x02 && $top->{labels}[3][8] == 0x02,
       'overlay_depth => 0: points, lines and labels on top');
    is(sprintf('%.1f', $top->{eps}), '5.0', 'overlay_eps');
}

# ---- view(), projection(), pose() without a server ----
{
    my $d = $GS3D->new(width => 400, height => 300, start => 'connect', scene => scene());
    my $where = sub {     # rotated point and screen position of a model point
        my ($p) = @_;
        my $r = $d->_rotate_points($d->_rotation, pdl([$p])->transpose);
        my ($sx, $sy) = $d->_project($r);
        return ([ $r->list ], $sx->sclr - 200, $sy->sclr - 150);
    };
    my $q = sub { [ map { sprintf '%.6f', abs($_) < 5e-7 ? 0 : $_ } @{ $d->{qrot} } ] };
    is_deeply($q->(), [ map { sprintf '%.6f', $_ } 0, 0, 0, 1 ], 'default qrot (0,0,0,1)');
    $d->view(elev => 90, azim => 0);
    is_deeply($q->(), [ map { sprintf '%.6f', $_ } 0, 0, 0, 1 ], 'view(elev => 90, azim => 0) is the default');
    $d->view('front');
    $d->view('top');
    is_deeply($q->(), [ map { sprintf '%.6f', $_ } 0, 0, 0, 1 ], "view('top') is the default");

    my %expect = (                       # point toward the viewer; [point, screen x sign, screen y sign]
        front  => [[0, 100, 0],  [[ 100, 0, 0], -1, 0], [[0, 0, 100], 0, -1]],
        back   => [[0, -100, 0], [[ 100, 0, 0], +1, 0], [[0, 0, 100], 0, -1]],
        left   => [[-100, 0, 0], [[0, 100, 0], -1, 0],  [[0, 0, 100], 0, -1]],
        right  => [[100, 0, 0],  [[0, 100, 0], +1, 0],  [[0, 0, 100], 0, -1]],
        top    => [[0, 0, 100],  [[ 100, 0, 0], +1, 0], [[0, 100, 0], 0, -1]],
        bottom => [[0, 0, -100], [[ 100, 0, 0], +1, 0], [[0, 100, 0], 0, +1]],
    );
    for my $name (sort keys %expect) {
        my ($toward, @screen) = @{ $expect{$name} };
        $d->view($name);
        my ($r) = $where->($toward);
        ok(abs($r->[0]) < 1e-6 && abs($r->[1]) < 1e-6 && $r->[2] > 99.99, "view('$name'): the point faces the viewer");
        for my $s (@screen) {
            my ($p, $xs, $ys) = @$s;
            my (undef, $sx, $sy) = $where->($p);
            ok(($xs ? $sx * $xs > 1 : abs($sx) < 1e-6) && ($ys ? $sy * $ys > 1 : abs($sy) < 1e-6),
               "view('$name'): (@$p) on screen at (" . sprintf('%.1f, %.1f', $sx, $sy) . ')');
        }
    }
    # Continuous toward the top: elev 89.999 is close to the default.
    $d->view(elev => 89.999, azim => 0);
    ok(abs($d->{qrot}[3] - 1) < 1e-6, 'elev near 90 is near the default');
    # elev 30 azim -90 (from the left, above): the left ear is nearer than the right.
    $d->view(elev => 30, azim => -90);
    my ($rl) = $where->([-100, 0, 0]); my ($rr) = $where->([100, 0, 0]);
    ok($rl->[2] > $rr->[2] && $rl->[2] > 50, 'elev 30 azim -90: seen from the left');

    $d->view(look_at => [10, 20, 30]);
    my %p = $d->pose;
    is_deeply($p{pivot}, [10, 20, 30], 'look_at moves the pivot');
    is_deeply([ map { sprintf '%.6f', $_ } @{ $p{qrot} } ],
              [ map { sprintf '%.6f', $_ } $GS3D->can('_view_quat')->(30, -90) ],
              'look_at alone keeps the orientation');
    $d->view(toward => [10, 20 + 50, 30 + 50]);   # up and in front of the pivot
    my ($rt) = $where->([10, 70, 80]);
    ok(abs($rt->[0]) < 1e-6 && abs($rt->[1]) < 1e-6 && $rt->[2] > 0, 'toward: the point faces the viewer');

    my $ds = $GS3D->new(width => 400, height => 300, start => 'connect',
                        scene => { %{ scene() }, points => pdl([[0, -80, 20]])->transpose, labels => ['Oz'] });
    $ds->view(toward => 'oz');
    my ($ro) = do { my $r = $ds->_rotate_points($ds->_rotation, pdl([[0, -80, 20]])->transpose); [ $r->list ] };
    ok(abs($ro->[0]) < 1e-6 && abs($ro->[1]) < 1e-6 && $ro->[2] > 0, 'toward => label name');

    $d->view('front', zoom => 2);
    is($d->{zoom}, 2, "view('front', zoom => 2)");
    is($d->projection, 'perspective', 'projection default');
    $d->projection('ortho');
    is($d->projection, 'ortho', "projection('ortho')");
    ok(!eval { $d->view('sideways'); 1 } && $@ =~ /unknown view/, 'unknown view name dies');
    ok(!eval { $d->set_vertex_colors(zeroes(5, 3)); 1 } && $@ =~ /wants \(6,3\)/, 'set_vertex_colors checks dims');
    ok(!eval { $GS3D->new(scene => scene(), stage => 'C'); 1 }, "stage => 'C' dies");
}

done_testing;
