use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo;
use PDL::Graphics::Cairo::Tick qw(nice_ticks);

# Automatic ticks are evenly spaced, and each tick label reads back as the
# tick value. Up to 0.42 a step of 2.5 (or 0.25, 0.0025 ...) was rounded to
# whole numbers of the wrong size: 0..12.9 gave 0, 3, 5, 8, 10 (12.5 became 13
# and was dropped), and labels of 1 or more had one decimal ("1.2" for 1.25).

# The case seen on screen: x = 0..4*pi with the default margin.
is_deeply([nice_ticks(-0.3769908, 12.9433508, 6)], [0, 2.5, 5, 7.5, 10, 12.5],
    'step 2.5: 0, 2.5, ..., 12.5');
is_deeply([nice_ticks(0.001, 0.0023, 6)],
    [0.001, 0.00125, 0.0015, 0.00175, 0.002, 0.00225], 'step 0.00025');

# Many ranges: positions evenly spaced, within the range, labels exact.
CORE::srand(31);
my ($n, $bad_step, $bad_range, $bad_label) = (0, 0, 0, 0);
for my $e (-6 .. 6) {
    for (1 .. 40) {
        my $lo   = (CORE::rand() - 0.5) * 10 ** $e * 20;
        my $span = (0.2 + CORE::rand() * 20) * 10 ** $e;
        my $hi   = $lo + $span;
        my @t = nice_ticks($lo, $hi, 6);
        next unless @t >= 3;
        $n++;
        my $d0 = $t[1] - $t[0];
        $bad_step++ if grep { abs(($t[$_] - $t[$_-1]) - $d0) > 1e-9 * abs($d0) } 2 .. $#t;
        my $eps = $d0 * 1e-6;
        $bad_range++ if $t[0] < $lo - $eps || $t[-1] > $hi + $eps
                     || $t[0] - $d0 >= $lo - $eps || $t[-1] + $d0 <= $hi + $eps;
        for my $v (@t) {
            my $s = PDL::Graphics::Cairo::Axes::_fmt_tick($v);
            $bad_label++ if abs($s - $v) > 1e-9 * (abs($v) || 1);
        }
    }
}
cmp_ok($n, '>', 400, "$n ranges checked");
is($bad_step,  0, 'ticks evenly spaced');
is($bad_range, 0, 'ticks cover the range: first and last inside, no room for one more');
is($bad_label, 0, 'each label reads back as its tick value');

# Labels that were right before stay the same.
is_deeply([map { PDL::Graphics::Cairo::Axes::_fmt_tick($_) } 0, 5, -2, 0.5, 2.5, 1e4, 2.5e-4],
    ['0', '5', '-2', '0.5', '2.5', '1.00e+04', '2.50e-04'], 'unchanged labels');

done_testing;
