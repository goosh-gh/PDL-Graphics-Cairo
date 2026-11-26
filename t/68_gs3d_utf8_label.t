use strict;
use warnings;
use utf8;
use Test::More;
use Socket qw(AF_UNIX SOCK_STREAM PF_UNSPEC);
use IO::Handle;
use Encode ();
use PDL;
use PDL::Graphics::Cairo::Driver::GS3D;

# ==================================================================
# Driver::GS3D::_send_3d_frame: a label that is a character string (Japanese,
# from `use utf8` source) used to be written with length() = characters as its
# u8 length, and pack-ing it upgraded the whole payload, which _send_msg then
# encoded as UTF-8: every byte >= 0x80 of the floats became two bytes and the
# server read garbage (found with gsp_wgpu, which checks that each frame is
# read to its last byte). Now the label goes as its UTF-8 bytes, cut at 255
# bytes on a character boundary.
# The frame is parsed here from the layout in giza-server's viewer/gsp_3d.h.
# ==================================================================

sub frame_for {
    my (@labels) = @_;
    socketpair(my $a_end, my $b_end, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die "socketpair: $!";
    $_->autoflush(1) for $a_end, $b_end;
    my $n   = scalar @labels;
    my $pts = (sequence($n, 3) * 10)->double;               # (N,3): dim 0 is the point
    my $drv = PDL::Graphics::Cairo::Driver::GS3D->new(
        scene  => { points => $pts, colors => ones($n, 3) * 0.5, labels => \@labels },
        width  => 300,
        height => 300,
    );
    $drv->{_ix3d} = { sock => $a_end, seq => 0 };
    $drv->_send_3d_frame;
    close $a_end;
    local $/;
    my $msg = <$b_end>;
    my ($magic, $ver, $type, $flags, $len) = unpack('L C C S L', $msg);
    return (substr($msg, 16), $len);
}

# labels from the payload, following gsp_3d.h; returns (\@texts, bytes used)
sub parse_labels {
    my ($p) = @_;
    my ($nl, $np) = unpack('S S', $p);
    my $at = 13 + 24 * $nl + 20 * $np;
    my $n  = unpack('S', substr($p, $at, 2));
    $at += 2;
    my @t;
    for (1 .. $n) {
        my $len = unpack('C', substr($p, $at + 13, 1));
        push @t, substr($p, $at + 14, $len);
        $at += 14 + $len;
    }
    return (\@t, $at);
}

{
    my ($p, $len) = frame_for('Cz', '頂点', 'T3');
    ok(!utf8::is_utf8($p), 'payload is bytes, not a character string');
    is(length($p), $len, 'header length = payload bytes');
    my ($t, $used) = parse_labels($p);
    is($used, length($p), 'labels end exactly at the end of the frame (no triangles)');
    my @mine = grep { $_ eq 'Cz' || $_ eq 'T3' || $_ eq Encode::encode('UTF-8', '頂点') } @$t;
    is(scalar @mine, 3, 'the three labels are there, the Japanese one as its 6 UTF-8 bytes');
    is(Encode::decode('UTF-8', (grep { length($_) == 6 } @$t)[0]), '頂点', 'and it decodes back');
}

{
    # 100 x "あ" = 300 bytes: cut to 255 bytes = 85 whole characters
    my ($p) = frame_for('あ' x 100);
    my ($t, $used) = parse_labels($p);
    is($used, length($p), 'a long label: the frame is still consistent');
    my ($long) = grep { length($_) > 100 } @$t;
    is(length($long), 255, 'cut to 255 bytes');
    is(Encode::decode('UTF-8', $long, Encode::FB_CROAK), 'あ' x 85, 'on a character boundary');
}

{
    # byte strings (ASCII, or already UTF-8 bytes) go as they are
    my ($p) = frame_for('Fp1', Encode::encode('UTF-8', '左'));
    my ($t, $used) = parse_labels($p);
    is($used, length($p), 'byte-string labels: consistent');
    ok((grep { $_ eq Encode::encode('UTF-8', '左') } @$t), 'UTF-8 bytes passed through unchanged');
}

done_testing();
