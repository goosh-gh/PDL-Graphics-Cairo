use strict;
use warnings;
use Test::More;
use PDL::Graphics::Cairo::ColorMap;

for my $name (qw(viridis plasma jet hot cool gray RdBu)) {
    my $cm = PDL::Graphics::Cairo::ColorMap->new($name);
    isa_ok $cm, 'PDL::Graphics::Cairo::ColorMap', $name;

    my @rgb = $cm->rgb_at(0.0);
    is scalar @rgb, 3, "$name rgb_at(0) returns 3 values";
    ok $rgb[0] >= 0 && $rgb[0] <= 1, "$name R in [0,1]";

    @rgb = $cm->rgb_at(0.5);
    is scalar @rgb, 3, "$name rgb_at(0.5) returns 3 values";

    @rgb = $cm->rgb_at(1.0);
    is scalar @rgb, 3, "$name rgb_at(1) returns 3 values";
}

done_testing;
