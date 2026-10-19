use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);

# Every plot method takes the line width as either `linewidth` or `lw`
# (Axes::_opt_lw). Up to 0.42 step/errorbar/stem read only linewidth and
# qqplot only lw; the other key was ignored without a word. The legend line
# has the width of the plotted line (it was fixed at 1.5 for step/errorbar,
# and line read only linewidth for it).

my $x = sequence(5);
my %call = (
    line     => sub { $_[0]->line($x, $x, @_[1..$#_]) },
    step     => sub { $_[0]->step($x, $x, @_[1..$#_]) },
    stem     => sub { $_[0]->stem($x, $x, @_[1..$#_]) },
    errorbar => sub { $_[0]->errorbar($x, $x, yerr => 0.1, @_[1..$#_]) },
    qqplot   => sub { $_[0]->qqplot($x, @_[1..$#_]) },
    axhline  => sub { $_[0]->axhline(1, @_[1..$#_]) },
    axvline  => sub { $_[0]->axvline(1, @_[1..$#_]) },
);
for my $m (sort keys %call) {
    for my $k (qw(lw linewidth)) {
        my $ax = figure(width => 100, height => 100)->axes;
        $call{$m}->($ax, $k => 7);
        is($ax->_queue->[-1]{lw}, 7, "$m: $k => 7");
    }
}

for my $m (qw(line step errorbar)) {
    for my $k (qw(lw linewidth)) {
        my $ax = figure(width => 100, height => 100)->axes;
        $call{$m}->($ax, $k => 3, label => 'a');
        is($ax->_legends->[-1]{lw}, 3, "$m: legend line width follows $k");
    }
}

# errorbar with lw => 0: the points are not joined; the legend shows the marker.
{
    my $ax = figure(width => 100, height => 100)->axes;
    $ax->errorbar($x, $x, yerr => 0.1, lw => 0, marker => 's', label => 'a');
    is($ax->_legends->[-1]{type}, 'marker', 'errorbar lw 0: legend shows the marker');
    is($ax->_legends->[-1]{marker}, 's', '... with its marker');

    # pixels between two points: joined with lw 1.5, empty with lw 0
    my @dark;
    for my $lw (1.5, 0) {
        my $f  = figure(width => 200, height => 200);
        my $a2 = $f->axes;
        $a2->errorbar(pdl(0, 4), pdl(0, 4), yerr => 0.1, lw => $lw, color => 'black');
        $a2->xlim(-1, 5); $a2->ylim(-1, 5);
        my $d = PDL::Graphics::Cairo::Driver::Cairo->new(width => 200, height => 200, file => ':memory:');
        $f->_render_to($d);
        my $s = $d->{surface}; $s->flush;
        my ($px, $py) = map { int } $a2->data_to_pixel(2, 2);   # midway on the joining line
        my $n = 0;
        for my $dy (-2 .. 2) { for my $dx (-2 .. 2) {
            my @c = unpack 'C4', substr($s->get_data, ($py+$dy) * $s->get_stride + ($px+$dx) * 4, 4);
            $n++ if $c[0] < 128 && $c[1] < 128 && $c[2] < 128;
        } }
        push @dark, $n;
    }
    cmp_ok($dark[0], '>', 0, "lw 1.5: joining line drawn ($dark[0] dark pixels)");
    is($dark[1], 0, 'lw 0: no joining line');
}

# color => undef means "no color given": the colour cycle, not black, and no
# warning (errorbar_stats passes color => undef when the caller gave none).
{
    my @warn;
    local $SIG{__WARN__} = sub { push @warn, @_ };
    my $ax = figure(width => 100, height => 100)->axes;
    $ax->errorbar($x, $x, yerr => 0.1, color => undef);
    $ax->line($x, $x, color => undef);
    is(scalar @warn, 0, 'color => undef: no warning') or diag @warn;
    isnt(join(',', @{ $ax->_queue->[0]{color} }), '0,0,0', 'color => undef: cycle colour, not black');
}

SKIP: {
    skip 'PDL::Stats::Basic not installed', 2 unless eval { require PDL::Stats::Basic; 1 };
    my @g = (pdl(1, 2, 3), pdl(2, 3, 4));
    my $ax = figure(width => 100, height => 100)->axes;
    $ax->errorbar_stats(\@g);
    is($ax->_queue->[-1]{lw}, 0, 'errorbar_stats: points not joined by default');
    $ax->errorbar_stats(\@g, lw => 1.5);
    is($ax->_queue->[-1]{lw}, 1.5, 'errorbar_stats: lw joins them');
}

done_testing;
