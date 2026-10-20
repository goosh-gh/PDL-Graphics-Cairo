use strict;
use warnings;
use Test::More;
use PDL::Graphics::Cairo::Driver::GS3D;

# ==================================================================
# Driver::GS3D::_pack_tris: the triangle section of a 3D frame starts with
# n_tris as u16. With more than 65535 triangles the count wrapped around and
# the server read the triangles wrongly; now the 65535 nearest are kept
# (depth: larger is nearer; a triangle's depth is the sum over its corners),
# in their original order, with one warning.
# ==================================================================

my $REC = 3 * (4 * 3 + 3);                    # bytes per triangle

sub tri { my ($k, $z) = @_; [ map { [$k, $_, $z, 1, 2, 3] } 0 .. 2 ] }

sub unpack_tris {
    my ($bytes) = @_;
    my $n = unpack('S', $bytes);
    my @t;
    for my $i (0 .. $n - 1) {
        my @v = unpack('f<f<f<CCC' x 3, substr($bytes, 2 + $i * $REC, $REC));
        push @t, [ $v[0], $v[2] ];               # (id = x of the first corner, z of the first corner)
    }
    return ($n, length($bytes), \@t);
}

# ---- at most 65535: written as given ----
{
    my @t = map { tri($_, $_ % 7) } 0 .. 999;
    my @w;
    local $SIG{__WARN__} = sub { push @w, @_ };
    my ($n, $len, $got) = unpack_tris(PDL::Graphics::Cairo::Driver::GS3D::_pack_tris(\@t));
    is($n, 1000, '1000 triangles: count 1000');
    is($len, 2 + 1000 * $REC, '1000 triangles: all written');
    is_deeply([ map { $_->[0] } @$got ], [0 .. 999], 'order kept');
    is(scalar @w, 0, 'no warning');
}

# ---- more than 65535: the 65535 nearest, in their order ----
{
    my $N = 70000;
    # depth from a fixed shuffle (independent of the order), all distinct
    my @z = map { ($_ * 7919) % $N } 0 .. $N - 1;
    my @t = map { tri($_, $z[$_]) } 0 .. $N - 1;
    my @w;
    local $SIG{__WARN__} = sub { push @w, @_ };
    my ($n, $len, $got) = unpack_tris(PDL::Graphics::Cairo::Driver::GS3D::_pack_tris(\@t));
    is($n, 65535, "$N triangles: count 65535");
    is($len, 2 + 65535 * $REC, 'length matches the count');
    my $cut = $N - 65535;                        # depths 0 .. cut-1 are the farthest
    my @want = grep { $z[$_] >= $cut } 0 .. $N - 1;
    is_deeply([ map { $_->[0] } @$got ], \@want, 'the nearest 65535, in their original order');
    ok(!grep({ $_->[1] < $cut } @$got), 'none of the farthest kept');
    is(scalar @w, 1, 'one warning');
    like($w[0] // '', qr/70000 triangles exceed/, 'the warning gives the number');
    PDL::Graphics::Cairo::Driver::GS3D::_pack_tris(\@t);
    is(scalar @w, 1, 'warned only once');
}

done_testing;
