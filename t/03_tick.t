use strict;
use warnings;
use Test::More;
use PDL::Graphics::Cairo::Tick qw(nice_ticks nice_range);

# nice_ticks: returns values within range
my @ticks = nice_ticks(0, 10, 5);
ok @ticks >= 3,       'nice_ticks returns some ticks';
ok $ticks[0] >= 0,    'first tick >= min';
ok $ticks[-1] <= 10,  'last tick <= max';

# nice_range: expands the range
my ($lo, $hi) = nice_range(1, 9);
ok $lo < 1, 'nice_range expands below min';
ok $hi > 9, 'nice_range expands above max';

done_testing;
