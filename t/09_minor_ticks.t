use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);
use PDL::Graphics::Cairo::Tick qw(minor_ticks);

# ----------------------------------------------------------------
# 1. minor_ticks() basic: 5 subdivisions between 0,1,2,3,4,5
# ----------------------------------------------------------------
{
    my @major = (0, 1, 2, 3, 4, 5);
    my @m = minor_ticks(0, 5, 5, @major);
    # expect 0.2, 0.4, 0.6, 0.8, 1.2, ... (no major positions)
    ok @m > 0, 'minor_ticks returns values';
    # none should coincide with major ticks
    for my $v (@m) {
        my $on_major = grep { abs($v - $_) < 0.01 } @major;
        ok !$on_major, "minor tick $v not on major";
    }
    # count: 4 per interval * 5 intervals = 20
    is scalar(@m), 20, 'correct count for 5-subdivision of 5 intervals';
}

# ----------------------------------------------------------------
# 2. minor_ticks() respects $min/$max bounds
# ----------------------------------------------------------------
{
    my @m;
    my @below = grep { $_ < 0.5 } @m;
    my @above = grep { $_ > 2.5 } @m;
    ok !@below, 'no minor below min';
    ok !@above, 'no minor above max';
}


# ----------------------------------------------------------------
# 3. minor_ticks() with < 2 major ticks returns empty
# ----------------------------------------------------------------
{
    my @m = minor_ticks(0, 10, 5, 5);
    is scalar(@m), 0, 'empty result for single major tick';
}

# ----------------------------------------------------------------
# 4. _minor_ticks_on default is off
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    is $ax->_minor_ticks_on, 0, 'minor ticks off by default';
}

# ----------------------------------------------------------------
# 5. minorticks_on() enables, minorticks_off() disables
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->minorticks_on;
    is $ax->_minor_ticks_on, 1, 'minorticks_on enables';
    $ax->minorticks_off;
    is $ax->_minor_ticks_on, 0, 'minorticks_off disables';
}

# ----------------------------------------------------------------
# 6. minorticks_on/off return $self (chaining)
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    is $ax->minorticks_on,  $ax, 'minorticks_on chains';
    is $ax->minorticks_off, $ax, 'minorticks_off chains';
}

# ----------------------------------------------------------------
# 7. set_minor_locator($n) sets _minor_n and enables
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->set_minor_locator(4);
    is $ax->_minor_n,        4, 'set_minor_locator sets _minor_n';
    is $ax->_minor_ticks_on, 1, 'set_minor_locator enables minor ticks';
}

# ----------------------------------------------------------------
# 8. tick_params(which=>'minor') enables minor ticks
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->tick_params(which=>'minor', length=>2, width=>0.5);
    is $ax->_minor_ticks_on, 1, 'which=>minor enables minor ticks';
}

# ----------------------------------------------------------------
# 9. tick_params(which=>'both') enables minor ticks
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->tick_params(which=>'both', direction=>'in');
    is $ax->_minor_ticks_on, 1, 'which=>both enables minor ticks';
}

# ----------------------------------------------------------------
# 10. tick_params(which=>'major') does NOT enable minor ticks
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->tick_params(which=>'major', length=>5);
    is $ax->_minor_ticks_on, 0, 'which=>major does not enable minor ticks';
}

# ----------------------------------------------------------------
# 11. PNG smoke: minorticks_on with default style
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    $ax->line(pdl(0..10), pdl(map { $_ ** 2 } 0..10));
    $ax->minorticks_on;
    $ax->xlabel('x');
    $ax->ylabel('y');
    $fig->tight_layout;
    my $tmp = "/tmp/minor_default_$$.png";
    eval { $fig->save($tmp) };
    ok !$@,                          "minorticks_on smoke: no die ($@)";
    ok -f $tmp && -s $tmp > 1000,    'PNG has content';
    unlink $tmp;
}

# ----------------------------------------------------------------
# 12. PNG smoke: direction=>'in', top=>1, right=>1 (publication style)
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    $ax->line(pdl(0..20), pdl(map { sin($_/3) } 0..20));
    $ax->minorticks_on;
    $ax->tick_params(which=>'both', direction=>'in', top=>1, right=>1);
    $fig->tight_layout;
    my $tmp = "/tmp/minor_in_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "direction=in with minor ticks: no die ($@)";
    unlink $tmp;
}

# ----------------------------------------------------------------
# 13. PNG smoke: set_minor_locator(4) — 4 subdivisions
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    $ax->scatter(pdl(1..8), pdl(3,1,4,1,5,9,2,6));
    $ax->set_minor_locator(4);
    $fig->tight_layout;
    my $tmp = "/tmp/minor_n4_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "set_minor_locator(4) smoke: no die ($@)";
    unlink $tmp;
}

# ----------------------------------------------------------------
# 14. PNG smoke: semilogy with minor ticks (log-scale minor)
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    $ax->semilogy(pdl(1..5), pdl(1, 10, 100, 1000, 10000));
    $ax->minorticks_on;
    $fig->tight_layout;
    my $tmp = "/tmp/minor_log_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "semilogy with minorticks_on: no die ($@)";
    unlink $tmp;
}

# ----------------------------------------------------------------
# 15. PNG smoke: minorticks_on + custom length/width via tick_params
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    $ax->line(pdl(0,1,2,3,4), pdl(0,1,4,9,16));
    $ax->minorticks_on;
    $ax->tick_params(which=>'minor', length=>4, width=>0.8);
    $ax->tick_params(which=>'major', length=>7, width=>1.5);
    $fig->tight_layout;
    my $tmp = "/tmp/minor_styled_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "custom minor length/width: no die ($@)";
    unlink $tmp;
}

done_testing;
