use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

# ================================================================
# TICK FORMATTER
# ================================================================

# ----------------------------------------------------------------
# 1. xaxis_formatter stores coderef
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $fmt = sub { sprintf "%.1f%%", $_[0]*100 };
    $ax->xaxis_formatter($fmt);
    is $ax->_xformatter, $fmt, 'xaxis_formatter stores coderef';
}

# ----------------------------------------------------------------
# 2. yaxis_formatter stores coderef
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $fmt = sub { sprintf "%dk", $_[0]/1000 };
    $ax->yaxis_formatter($fmt);
    is $ax->_yformatter, $fmt, 'yaxis_formatter stores coderef';
}

# ----------------------------------------------------------------
# 3. set_major_formatter dispatches by axis
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $xfmt = sub { "x$_[0]" };
    my $yfmt = sub { "y$_[0]" };
    $ax->set_major_formatter('x', $xfmt);
    $ax->set_major_formatter('y', $yfmt);
    is $ax->_xformatter, $xfmt, 'set_major_formatter x';
    is $ax->_yformatter, $yfmt, 'set_major_formatter y';
}

# ----------------------------------------------------------------
# 4. xaxis_formatter chains
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    is $ax->xaxis_formatter(sub { $_[0] }), $ax, 'xaxis_formatter chains';
}

# ----------------------------------------------------------------
# 5. PNG smoke: percentage formatter on x axis
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    $ax->line(pdl(0, 0.25, 0.5, 0.75, 1.0), pdl(0,1,4,9,16));
    $ax->xaxis_formatter(sub { sprintf "%.0f%%", $_[0]*100 });
    $ax->xlabel('Completion');
    $fig->tight_layout;
    my $tmp = "/tmp/fmt_pct_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "percentage x formatter: no die ($@)";
    ok -f $tmp && -s $tmp > 500, 'PNG has content';
    unlink $tmp;
}

# ----------------------------------------------------------------
# 6. PNG smoke: engineering notation on y axis
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    $ax->line(pdl(1..5), pdl(1000, 5000, 10000, 50000, 100000));
    $ax->yaxis_formatter(sub { sprintf "%dk", int($_[0]/1000) });
    $ax->ylabel('Count');
    $fig->tight_layout;
    my $tmp = "/tmp/fmt_eng_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "engineering y formatter: no die ($@)";
    unlink $tmp;
}

# ----------------------------------------------------------------
# 7. PNG smoke: both axes formatted
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    $ax->scatter(pdl(map { rand() } 1..20), pdl(map { rand() } 1..20));
    $ax->xaxis_formatter(sub { sprintf "%.2f", $_[0] });
    $ax->yaxis_formatter(sub { sprintf "%.2f", $_[0] });
    $fig->tight_layout;
    my $tmp = "/tmp/fmt_both_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "both axes formatted: no die ($@)";
    unlink $tmp;
}

# ================================================================
# HEXBIN
# ================================================================

# ----------------------------------------------------------------
# 8. hexbin queues a command
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->hexbin(pdl(1..10), pdl(1..10));
    my $q = $ax->_queue;
    is $q->[-1]{type}, 'hexbin', 'hexbin queued';
}

# ----------------------------------------------------------------
# 9. hexbin default gridsize=20
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->hexbin(pdl(1..10), pdl(1..10));
    is $ax->_queue->[-1]{gridsize}, 20, 'default gridsize=20';
}

# ----------------------------------------------------------------
# 10. hexbin custom gridsize
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->hexbin(pdl(1..10), pdl(1..10), gridsize=>10);
    is $ax->_queue->[-1]{gridsize}, 10, 'custom gridsize=10';
}

# ----------------------------------------------------------------
# 11. hexbin mincnt
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->hexbin(pdl(1..10), pdl(1..10), mincnt=>2);
    is $ax->_queue->[-1]{mincnt}, 2, 'mincnt=2 stored';
}

# ----------------------------------------------------------------
# 12. hexbin sets colorbar
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->hexbin(pdl(1..10), pdl(1..10));
    ok defined($ax->_colorbar), 'hexbin sets colorbar';
}

# ----------------------------------------------------------------
# 13. hexbin chains
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    is $ax->hexbin(pdl(1..5), pdl(1..5)), $ax, 'hexbin chains';
}

# ----------------------------------------------------------------
# 14. PNG smoke: basic hexbin
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>450);
    # Generate clustered data
    my @xd = map { 2 + rand()*2 } 1..200;
    my @yd = map { 3 + rand()*2 } 1..200;
    push @xd, map { 5 + rand()*2 } 1..100;
    push @yd, map { 5 + rand()*2 } 1..100;
    $ax->hexbin(pdl(@xd), pdl(@yd), gridsize=>15, cmap=>'viridis');
    $ax->xlabel('X'); $ax->ylabel('Y');
    $ax->title('Hexbin density');
    $fig->tight_layout;
    my $tmp = "/tmp/hexbin_basic_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "hexbin basic smoke: no die ($@)";
    ok -f $tmp && -s $tmp > 1000, 'PNG has content';
    unlink $tmp;
}

# ----------------------------------------------------------------
# 15. PNG smoke: hexbin with plasma cmap and mincnt
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>450);
    my @xd = map { rand()*10 } 1..500;
    my @yd = map { rand()*10 } 1..500;
    $ax->hexbin(pdl(@xd), pdl(@yd), gridsize=>20, cmap=>'plasma', mincnt=>2);
    $fig->tight_layout;
    my $tmp = "/tmp/hexbin_plasma_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "hexbin plasma/mincnt smoke: no die ($@)";
    unlink $tmp;
}

# ----------------------------------------------------------------
# 16. PNG smoke: hexbin with formatter on colorbar axis
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>450);
    my @xd = map { rand()*4 } 1..300;
    my @yd = map { rand()*4 } 1..300;
    $ax->hexbin(pdl(@xd), pdl(@yd), gridsize=>12, cmap=>'inferno');
    $ax->xaxis_formatter(sub { sprintf "%.1f", $_[0] });
    $ax->yaxis_formatter(sub { sprintf "%.1f", $_[0] });
    $fig->tight_layout;
    my $tmp = "/tmp/hexbin_fmt_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "hexbin + formatter smoke: no die ($@)";
    unlink $tmp;
}

done_testing;
