use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

# $fig->subplots(N,1) / (1,N) in list context gives the Axes (one or many).
# In scalar context N=1 gives the Axes but N>=2 gives their count: that
# case warns (like MxN already did); list context and 1x1 do not.

sub warnings_of {
    my ($code) = @_;
    my @w;
    local $SIG{__WARN__} = sub { push @w, $_[0] };
    $code->();
    return @w;
}

for my $shape ([2, 1], [1, 3]) {
    my ($r, $c) = @$shape;
    my @w = warnings_of(sub { my $n = figure()->subplots($r, $c) });
    is(scalar @w, 1, "subplots($r,$c) in scalar context warns");
    like($w[0] // '', qr/in scalar context you get their count/, '... saying what it returns');

    my @ax;
    @w = warnings_of(sub { @ax = figure()->subplots($r, $c) });
    is(scalar @w, 0, "subplots($r,$c) in list context does not warn");
    is(scalar(grep { ref $_ eq 'PDL::Graphics::Cairo::Axes' } @ax), $r * $c,
       "... and gives $r*$c Axes");
}

{
    my $ax;
    my @w = warnings_of(sub { $ax = figure()->subplots(1, 1) });
    is(scalar @w, 0, 'subplots(1,1) in scalar context: no warning');
    isa_ok($ax, 'PDL::Graphics::Cairo::Axes');
    my ($fig, @b);
    @w = warnings_of(sub { ($fig, @b) = subplots(3, 1) });
    is(scalar @w, 0, 'function subplots(3,1): no warning');
    is(scalar @b, 3, '... three Axes');
}

done_testing;
