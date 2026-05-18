package PDL::Graphics::Cairo::Scale::Log;

use Moo;
use POSIX qw(floor log10 ceil);

has base => (is => 'ro', default => sub { 10 });

sub transform { log($_[1]) / log($_[0]->base) }
sub inverse   { $_[0]->base ** $_[1] }

sub nice_ticks {
    my ($self, $min, $max) = @_;
    $min = 1e-10 if $min <= 0;
    my $lo = floor(log10($min));
    my $hi = ceil( log10($max));
    my @ticks;
    for my $e ($lo .. $hi) {
        for my $m (1, 2, 5) {
            my $v = $m * (10 ** $e);
            push @ticks, $v if $v >= $min * 0.999 && $v <= $max * 1.001;
        }
    }
    return @ticks;
}

sub fmt_tick {
    my ($self, $v) = @_;
    my $e = floor(log10(abs($v) || 1) + 1e-9);
    return sprintf("10^%d", $e) if abs($v - 10**$e) < $v * 0.001;
    return sprintf("%.3g", $v);
}

1;
