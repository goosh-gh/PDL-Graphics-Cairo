use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

# ----------------------------------------------------------------
# 1. set_suptitle stores text
# ----------------------------------------------------------------
{
    my $fig = figure(width=>400, height=>300);
    $fig->set_suptitle('My Title');
    is $fig->suptitle, 'My Title', 'set_suptitle stores text';
}

# ----------------------------------------------------------------
# 2. suptitle() alias works
# ----------------------------------------------------------------
{
    my $fig = figure(width=>400, height=>300);
    $fig->suptitle('Alias Title');
    is $fig->suptitle, 'Alias Title', 'suptitle() alias works';
}

# ----------------------------------------------------------------
# 3. fontsize option
# ----------------------------------------------------------------
{
    my $fig = figure(width=>400, height=>300);
    $fig->set_suptitle('Big Title', fontsize=>20);
    is $fig->_suptitle_fontsize, 20, 'fontsize stored';
}

# ----------------------------------------------------------------
# 4. size option (alias for fontsize)
# ----------------------------------------------------------------
{
    my $fig = figure(width=>400, height=>300);
    $fig->set_suptitle('Big Title', size=>18);
    is $fig->_suptitle_fontsize, 18, 'size option stored as fontsize';
}

# ----------------------------------------------------------------
# 5. chaining — set_suptitle returns $fig
# ----------------------------------------------------------------
{
    my $fig = figure(width=>400, height=>300);
    is $fig->set_suptitle('T'), $fig, 'set_suptitle chains';
}

# ----------------------------------------------------------------
# 6. empty suptitle by default
# ----------------------------------------------------------------
{
    my $fig = figure(width=>400, height=>300);
    is $fig->suptitle, '', 'suptitle empty by default';
}

# ----------------------------------------------------------------
# 7. PNG smoke: suptitle renders without crash
# ----------------------------------------------------------------
{
    my ($fig, @ax) = subplots(1, 2, width=>600, height=>300);
    $ax[0]->line(pdl(1,2,3), pdl(1,4,9));
    $ax[1]->scatter(pdl(1,2,3), pdl(3,1,2));
    $fig->set_suptitle('Combined Plot');
    $fig->tight_layout;
    my $tmp = "/tmp/suptitle_smoke_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "suptitle smoke: no die ($@)";
    ok -f $tmp && -s $tmp > 1000, 'PNG has content';
    unlink $tmp;
}

# ----------------------------------------------------------------
# 8. PNG smoke: large fontsize
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1, 1, width=>500, height=>400);
    $ax->line(pdl(0..5), pdl(0,1,4,9,16,25));
    $fig->suptitle('Large Title', fontsize=>22);
    $fig->tight_layout;
    my $tmp = "/tmp/suptitle_large_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "large fontsize suptitle: no die ($@)";
    unlink $tmp;
}

# ----------------------------------------------------------------
# 9. tight_layout reserves space for suptitle
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1, 1, width=>400, height=>300);
    $ax->line(pdl(1,2,3), pdl(1,2,3));
    $fig->set_suptitle('Space Test');
    # just check no crash
    $fig->tight_layout;
    my $tmp = "/tmp/suptitle_space_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "tight_layout with suptitle: no die ($@)";
    unlink $tmp;
}

done_testing;
