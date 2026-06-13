use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

# ----------------------------------------------------------------
# 1. inset_axes returns an Axes object
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    $fig->tight_layout;
    my $axin = $ax->inset_axes([0.6, 0.6, 0.35, 0.35]);
    isa_ok $axin, 'PDL::Graphics::Cairo::Axes', 'inset_axes returns Axes';
}

# ----------------------------------------------------------------
# 2. inset axes is_inset flag
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    $fig->tight_layout;
    my $axin = $ax->inset_axes([0.6, 0.6, 0.35, 0.35]);
    is $axin->_is_inset, 1, 'inset axes has _is_inset=1';
    is $ax->_is_inset,   0, 'parent axes has _is_inset=0';
}

# ----------------------------------------------------------------
# 3. inset axes registered in parent _inset_axes
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    $fig->tight_layout;
    my $axin = $ax->inset_axes([0.6, 0.6, 0.35, 0.35]);
    is scalar(@{ $ax->_inset_axes }), 1, 'inset axes in parent _inset_axes';
    is $ax->_inset_axes->[0], $axin, 'correct inset axes object';
}

# ----------------------------------------------------------------
# 4. inset axes added to figure axes_list
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    my $n_before = scalar @{ $fig->axes_list };
    $fig->tight_layout;
    $ax->inset_axes([0.6, 0.6, 0.35, 0.35]);
    my $n_after = scalar @{ $fig->axes_list };
    is $n_after, $n_before + 1, 'inset axes added to figure axes_list';
}

# ----------------------------------------------------------------
# 5. inset axes pixel position is within parent
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    $fig->tight_layout;
    my $axin = $ax->inset_axes([0.6, 0.6, 0.35, 0.35]);
    ok $axin->fig_x >= $ax->fig_x, 'inset x >= parent x';
    ok $axin->fig_y >= $ax->fig_y, 'inset y >= parent y';
    ok $axin->width  > 0, 'inset width > 0';
    ok $axin->height > 0, 'inset height > 0';
    ok $axin->fig_x + $axin->width  <= $ax->fig_x + $ax->width,
        'inset right edge within parent';
    ok $axin->fig_y + $axin->height <= $ax->fig_y + $ax->height,
        'inset bottom edge within parent';
}

# ----------------------------------------------------------------
# 6. multiple inset axes
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    $fig->tight_layout;
    my $ax1 = $ax->inset_axes([0.1, 0.6, 0.3, 0.3]);
    my $ax2 = $ax->inset_axes([0.6, 0.1, 0.3, 0.3]);
    is scalar(@{ $ax->_inset_axes }), 2, 'two inset axes registered';
    isnt $ax1->fig_x, $ax2->fig_x, 'inset axes at different positions';
}

# ----------------------------------------------------------------
# 7. PNG smoke: basic inset zoom
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>600, height=>500);
    $ax->line(pdl(0..10), pdl(map { sin($_) } 0..10));
    $ax->set_xlim(0, 10);
    $ax->xlabel('x'); $ax->ylabel('sin(x)');
    $fig->tight_layout;

    my $axin = $ax->inset_axes([0.55, 0.55, 0.4, 0.35]);
    $axin->line(pdl(0,1,2,3), pdl(map { sin($_) } 0,1,2,3));
    $axin->title('Zoom');

    $fig->tight_layout;
    my $tmp = "/tmp/inset_basic_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "inset_axes basic smoke: no die ($@)";
    ok -f $tmp && -s $tmp > 1000, 'PNG has content';
    unlink $tmp;
}

# ----------------------------------------------------------------
# 8. PNG smoke: inset with scatter and different data
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>600, height=>500);
    $ax->scatter(pdl(map { rand()*10 } 1..50),
                 pdl(map { rand()*10 } 1..50));
    $fig->tight_layout;

    my $axin = $ax->inset_axes([0.05, 0.6, 0.35, 0.35]);
    $axin->hist(pdl(map { rand()*10 } 1..50), bins=>8);
    $axin->title('Histogram');
    $fig->tight_layout;

    my $tmp = "/tmp/inset_scatter_hist_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "inset scatter+hist smoke: no die ($@)";
    unlink $tmp;
}

# ----------------------------------------------------------------
# 9. PNG smoke: inset in subplot grid
# ----------------------------------------------------------------
{
    my ($fig, @ax) = subplots(1, 2, width=>700, height=>400);
    $ax[0]->line(pdl(0..5), pdl(0,1,4,9,16,25));
    $ax[1]->bar(pdl(1..4), pdl(3,1,4,2));
    $fig->tight_layout;

    my $axin = $ax[0]->inset_axes([0.5, 0.05, 0.45, 0.4]);
    $axin->line(pdl(3,4,5), pdl(9,16,25));
    $axin->title('zoom');
    $fig->tight_layout;

    my $tmp = "/tmp/inset_subplots_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "inset in subplot grid: no die ($@)";
    unlink $tmp;
}

done_testing;
