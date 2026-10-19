use strict;
use warnings;
use utf8;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::Driver::GS;
use IO::Socket::UNIX;
use File::Temp qw(tempdir);
use Encode ();
use POSIX ();

# ==================================================================
# show_interactive(slider_labels => ...) puts the meaning of each slider in
# the window title: "title — ↔ <id 0> / ↕ <id 1>". A label given as code is
# called on every frame with the slider value, and the title is sent again
# only when it changed. Run against a fake giza-server that ACKs NEWWIN/PNG,
# moves the sliders, and records every TITLE it receives.
# Titles are sent as UTF-8 with a byte length in the header: a title from
# `use utf8` source (character string) no longer puts the stream out of step.
# ==================================================================

plan skip_all => 'needs fork and Unix sockets' if $^O eq 'MSWin32';

use constant {
    MAGIC => 0x47495A41, PNG => 0x10, TITLE => 0x11, NEWWIN => 0x12,
    SLIDER => 0x13, ACK => 0x21,
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

# Fake server. After each PNG it ACKs and sends the next slider move from
# @moves; after the last one it closes. Writes one line per received message
# to $log: "TITLE <hex of payload>", "PNG", or "BADMAGIC" if out of step.
sub fake_server {
    my ($path, $log, @moves) = @_;
    my $l = IO::Socket::UNIX->new(Type => SOCK_STREAM(), Local => $path, Listen => 5)
        or die "listen: $!";
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    return ($pid, $l) if $pid;
    open my $out, '>', $log or POSIX::_exit(1);
    $out->autoflush(1);
    while (my $c = $l->accept) {
        binmode $c;
        while (defined(my $h = read_n($c, 16))) {
            my ($magic, undef, $type, undef, $len) = unpack('L C C S L', $h);
            if ($magic != MAGIC) { print $out "BADMAGIC\n"; close $c; POSIX::_exit(0) }
            my $p = $len ? read_n($c, $len) : '';
            if ($type == NEWWIN) { syswrite($c, hdr(ACK)) }
            elsif ($type == TITLE) { print $out "TITLE ", unpack('H*', $p), "\n" }
            elsif ($type == PNG) {
                print $out "PNG\n";
                syswrite($c, hdr(ACK));
                my $mv = shift @moves;
                unless ($mv) { close $c; POSIX::_exit(0) }
                syswrite($c, hdr(SLIDER, 5) . pack('C f<', @$mv));
            }
        }
        close $c;
    }
    POSIX::_exit(0);
}

sub session {
    my (%o) = @_;
    my $dir = tempdir(CLEANUP => 1);
    local $ENV{GIZA_SERVER_SOCK} = "$dir/gs.sock";
    my $log = "$dir/log";
    my ($pid, $l) = fake_server($ENV{GIZA_SERVER_SOCK}, $log, @{ $o{moves} });
    close $l;
    my $gs = PDL::Graphics::Cairo::Driver::GS->new(
        width => 200, height => 150, start => 'connect', title => $o{title});
    $gs->show_interactive(
        init   => $o{init},
        render => sub {
            my $f = figure(width => $_[1], height => $_[2]);
            $f->axes->line(sequence(5), sequence(5));
            return $f;
        },
        ($o{labels} ? (slider_labels => $o{labels}) : ()),
    );
    waitpid($pid, 0);
    open my $in, '<', $log or die;
    my @lines = <$in>;
    chomp @lines;
    return map { /^TITLE (\S*)$/ ? 'TITLE ' . Encode::decode('UTF-8', pack('H*', $1)) : $_ } @lines;
}

# ---- labels, one of them showing the value ----
{
    my @got = session(
        title  => '波形.wav',
        init   => { 0 => 0.1, 1 => 0.5 },
        labels => { 0 => '表示位置', 1 => sub { sprintf '表示幅 %.2f', $_[0] } },
        moves  => [ [0, 0.3], [1, 0.75] ],
    );
    is_deeply(\@got, [
        'TITLE 波形.wav — ↔ 表示位置 / ↕ 表示幅 0.50',
        'PNG',
        'PNG',                                            # id 0 moved: title unchanged, not sent
        'TITLE 波形.wav — ↔ 表示位置 / ↕ 表示幅 0.75',
        'PNG',
    ], 'title with slider meanings; re-sent only when it changes')
        or diag explain \@got;
}

# ---- a label returning '' is left out; ids other than 0/1 get "#id" ----
{
    my @got = session(
        title  => 'plot',
        init   => { 0 => 0.2 },
        labels => { 0 => sub { $_[0] > 0.5 ? 'right half' : '' }, 2 => 'gain' },
        moves  => [ [0, 0.8] ],
    );
    is_deeply(\@got, [
        'TITLE plot — #2 gain', 'PNG',
        'TITLE plot — ↔ right half / #2 gain', 'PNG',
    ], "empty label left out, id 2 marked '#2'") or diag explain \@got;
}

# ---- byte-string title (no `use utf8` in the caller) is sent as it is ----
{
    no utf8;
    my $bytes = "\xe6\xb3\xa2.wav";     # "波.wav" as UTF-8 bytes
    my @got = session(title => $bytes, init => {}, labels => { 1 => 'width' },
                      moves => []);
    is($got[0], "TITLE \x{6ce2}.wav \x{2014} \x{2195} width",
       'UTF-8 byte title joined with labels without double encoding');
}

# ---- no slider_labels: the title as before, once ----
{
    my @got = session(title => 'Plain', init => { 0 => 0.5 },
                      moves => [ [0, 0.6] ]);
    is_deeply(\@got, [ 'TITLE Plain', 'PNG', 'PNG' ],
        'without slider_labels: one TITLE, the given title');
}

done_testing;
