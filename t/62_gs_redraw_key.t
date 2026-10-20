use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::Driver::GS;
use IO::Socket::UNIX;
use IO::Select;
use File::Temp qw(tempdir);
use POSIX ();

# ==================================================================
# show_interactive(cursor_overlay => 1, redraw_key => sub { ... }):
# on a CURSOR message the figure is drawn again only when the string the
# callback returns (with the window size) differs from the one of the last
# frame drawn for a cursor. Without redraw_key every CURSOR draws a frame.
# Run against a fake giza-server: after the first frame it sends one CURSOR
# at a time and waits up to 1 s for a PNG, logging "PNG" or "-".
# ==================================================================

plan skip_all => 'needs fork and Unix sockets' if $^O eq 'MSWin32';

use constant {
    MAGIC => 0x47495A41, PNG => 0x10, NEWWIN => 0x12, CURSOR => 0x18, ACK => 0x21,
};

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

# Reads one message; returns its type, or undef on EOF.
sub read_msg {
    my ($c) = @_;
    my $h = read_n($c, 16) // return undef;
    my (undef, undef, $type, undef, $len) = unpack('L C C S L', $h);
    read_n($c, $len) if $len;
    return $type;
}

sub fake_server {
    my ($path, $log, @cursors) = @_;
    my $l = IO::Socket::UNIX->new(Type => SOCK_STREAM(), Local => $path, Listen => 5)
        or die "listen: $!";
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    return ($pid, $l) if $pid;
    open my $out, '>', $log or POSIX::_exit(1);
    $out->autoflush(1);
    # The driver first connects once to see that a server is there and closes;
    # the session is the next connection that sends NEWWIN and a first frame.
    my $c;
    ACCEPT: while ($c = $l->accept) {
        binmode $c;
        while (defined(my $t = read_msg($c))) {
            if ($t == NEWWIN) { syswrite($c, hdr(ACK)) }
            elsif ($t == PNG) { print $out "PNG\n"; syswrite($c, hdr(ACK)); last ACCEPT }
        }
        close $c;
    }
    POSIX::_exit(1) unless $c;
    my $sel = IO::Select->new($c);
    for my $cur (@cursors) {
        syswrite($c, hdr(CURSOR, 9) . pack('f< f< C', @$cur, 0));
        my $got = '-';
        while ($sel->can_read(1)) {
            my $t = read_msg($c);
            last unless defined $t;
            if ($t == PNG) { $got = 'PNG'; syswrite($c, hdr(ACK)); last }
        }
        print $out "$got\n";
    }
    close $c;
    POSIX::_exit(0);
}

sub session {
    my (%o) = @_;
    my $dir = tempdir(CLEANUP => 1);
    local $ENV{GIZA_SERVER_SOCK} = "$dir/gs.sock";
    my $log = "$dir/log";
    my ($pid, $l) = fake_server($ENV{GIZA_SERVER_SOCK}, $log, @{ $o{cursors} });
    close $l;
    my $gs = PDL::Graphics::Cairo::Driver::GS->new(
        width => 300, height => 300, start => 'connect', title => 'redraw_key');
    my $renders = 0;
    $gs->show_interactive(
        init           => {},
        cursor_overlay => 1,
        render         => sub {
            $renders++;
            my $f = figure(width => $_[1], height => $_[2]);
            my @ax = $f->subplots(2, 1);
            $_->line(sequence(5), sequence(5)) for @ax;
            return $f;
        },
        ($o{key} ? (redraw_key => $o{key}) : ()),
    );
    waitpid($pid, 0);
    open my $in, '<', $log or die;
    my @lines = <$in>;
    chomp @lines;
    return (\@lines, $renders);
}

# image fractions: upper panel, the same panel again, lower panel, outside both, outside again
my @cursors = ([0.5, 0.25], [0.55, 0.27], [0.5, 0.75], [0.01, 0.01], [0.02, 0.01]);

{
    my ($got, $n) = session(
        cursors => \@cursors,
        key     => sub { my ($s) = @_; defined $s->{_cursor_ax_idx} ? "ax$s->{_cursor_ax_idx}" : 'none' },
    );
    is_deeply($got, [qw(PNG PNG - PNG PNG -)],
        'redraw_key: a cursor that changes nothing drawn is not drawn again') or diag explain $got;
    is($n, 4, 'render called for the first frame and three changed keys');
}

{
    my ($got, $n) = session(cursors => \@cursors);
    is_deeply($got, [qw(PNG PNG PNG PNG PNG PNG)],
        'without redraw_key every CURSOR draws a frame') or diag explain $got;
    is($n, 6, 'render called for every frame');
}

done_testing;
