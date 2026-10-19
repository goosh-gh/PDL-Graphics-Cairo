use strict;
use warnings;
use utf8;
use Test::More;
use Encode ();
use PDL::Graphics::Cairo::Driver::GS;

# giza_server keeps at most 255 bytes of a window title and reads them as
# UTF-8. Up to 0.42 Driver::GS sent longer titles as they were, so a cut in
# the middle of a Japanese character (3 bytes) made the title invalid UTF-8.
# Titles are now cut at a character boundary within 255 bytes.

sub valid_utf8 { my $b = shift; eval { Encode::decode('UTF-8', $b, Encode::FB_CROAK); 1 } ? 1 : 0 }

my $clip = \&PDL::Graphics::Cairo::Driver::GS::_clip_utf8;
is($clip->('abc', 255), 'abc', 'short title unchanged');
is(length $clip->('a' x 300, 255), 255, 'ASCII cut at 255');

# 265 bytes: byte 255 falls inside a 3-byte character
my $long = Encode::encode('UTF-8', 'タイトル長さ確認 ' . ('あいうえお' x 16));
is(length $long, 265, 'test title is 265 bytes');
ok(!valid_utf8(substr($long, 0, 255)), 'a plain 255-byte cut is invalid UTF-8 (negative control)');
my $c = $clip->($long, 255);
cmp_ok(length $c, '<=', 255, 'clipped to 255 bytes or less (' . length($c) . ')');
cmp_ok(length $c, '>=', 253, 'loses at most the partial character');
ok(valid_utf8($c), 'clipped title is valid UTF-8');
is($c, substr($long, 0, length $c), 'clipped title is a prefix of the original');

# The title actually written to the socket by _send_title.
{
    package FakeSock;
    sub new   { bless { out => '' }, shift }
    sub print { my $s = shift; $s->{out} .= join '', @_; 1 }
}
my $drv = PDL::Graphics::Cairo::Driver::GS->new(width => 100, height => 100,
    title => 'タイトル長さ確認 ' . ('あいうえお' x 16));
$drv->{_slider_labels} = { 0 => '表示位置' };
my $sock = FakeSock->new;
$drv->_send_title($sock, { 0 => 0.5 }, 0);
my ($len) = unpack 'x8 L', $sock->{out};
my $payload = substr($sock->{out}, 16);
is($len, length $payload, 'header length matches the payload');
cmp_ok($len, '<=', 255, "sent title within 255 bytes ($len)");
ok(valid_utf8($payload), 'sent title is valid UTF-8');

done_testing;
