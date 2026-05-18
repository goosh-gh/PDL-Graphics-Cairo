package PDL::Graphics::Cairo::Tick;

# =============================================================
# matplotlib  AutoLocator 
#   nice_ticks($min, $max, $n_target) → @tick_values
# =============================================================

use strict;
use warnings;
use POSIX qw(floor ceil log10 fmod);
use Exporter 'import';
our @EXPORT_OK = qw(nice_ticks nice_range);

sub nice_ticks {
    my ($min, $max, $n) = @_;
    $n //= 6;
    return ($min) if $min == $max;

    my $range  = $max - $min;
    my $rough  = $range / $n;
    my $mag    = 10 ** floor(log10(abs($rough) || 1));
    my $frac   = $rough / $mag;

    # nice 
    my $step;
    if    ($frac <= 1.0) { $step = 1.0  * $mag }
    elsif ($frac <= 2.0) { $step = 2.0  * $mag }
    elsif ($frac <= 2.5) { $step = 2.5  * $mag }
    elsif ($frac <= 5.0) { $step = 5.0  * $mag }
    else                 { $step = 10.0 * $mag }

    # step 
    my $decimals = ($step >= 1) ? 0 : ceil(-log10($step));

    my $start = $step * ceil($min / $step - 1e-10);
    my @ticks;
    my $v = $start;
    while ($v <= $max + $step * 1e-6) {
        #

        my $rounded = ($decimals > 0)
            ? sprintf("%.${decimals}f", $v) + 0
            : int($v + 0.5 * ($v <=> 0));
        push @ticks, $rounded if $rounded >= $min - $step*1e-6
                              && $rounded <= $max + $step*1e-6;
        $v += $step;
        last if @ticks > 20;
    }
    return @ticks;
}

#  nice 
sub nice_range {
    my ($min, $max, $margin_ratio) = @_;
    $margin_ratio //= 0.05;
    my $span = $max - $min || 1;
    return ($min - $span * $margin_ratio,
            $max + $span * $margin_ratio);
}

1;
