use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);

# ==================================================================
# The shared axis of a twin (x of twinx, y of twiny) has the parent's range,
# as in matplotlib: xlim / set_xlim on a twinx (ylim / set_ylim on a twiny)
# sets the parent's range, so both are drawn with it. Given on both, the
# later call wins. The twin's own axis (y of twinx, x of twiny) stays its own.
# Before, the limit given on the twin was ignored without a word.
# ==================================================================

sub drawn {
    my ($fig) = @_;
    $fig->to_png;
    return $fig;
}

sub near { my ($got, $want) = @_; abs($got - $want) < 1e-9 }

# ---- twinx: xlim on the twin ----
{
    my $fig = figure(width => 400, height => 300);
    my $ax  = $fig->axes;
    $ax->line(sequence(11), sequence(11));
    my $tw = $ax->twinx;
    $tw->line(sequence(11), sequence(11) * 100);
    $tw->xlim(2, 8);
    $tw->ylim(0, 2000);
    drawn($fig);
    my @px = $ax->get_xlim;
    my @tx = $tw->get_xlim;
    ok(near($px[0], 2) && near($px[1], 8), "twinx: parent x range is the one given on the twin (@px)");
    ok(near($tx[0], 2) && near($tx[1], 8), "twinx: twin x range too (@tx)");
    my @ty = $tw->get_ylim;
    ok(near($ty[0], 0) && near($ty[1], 2000), "twinx: the twin's own y range stays its own (@ty)");
    my @py = $ax->get_ylim;
    ok(!near($py[1], 2000), "twinx: the parent's y range is not touched (@py)");
    my ($l1) = $ax->data_to_pixel(pdl(2), pdl(0));
    my ($l2) = $tw->data_to_pixel(pdl(2), pdl(0));
    ok(near($l1->sclr, $l2->sclr), 'twinx: x = 2 at the same pixel in both');
}

# ---- set_xlim alias, and the later of the two calls wins ----
{
    my $fig = figure(width => 400, height => 300);
    my $ax  = $fig->axes;
    $ax->line(sequence(11), sequence(11));
    my $tw = $ax->twinx;
    $ax->xlim(0, 10);
    $tw->set_xlim(3, 7);
    drawn($fig);
    my @px = $ax->get_xlim;
    ok(near($px[0], 3) && near($px[1], 7), "parent then twin: the twin's range wins (@px)");

    my $fig2 = figure(width => 400, height => 300);
    my $ax2  = $fig2->axes;
    $ax2->line(sequence(11), sequence(11));
    my $tw2 = $ax2->twinx;
    $tw2->xlim(3, 7);
    $ax2->xlim(1, 9);
    drawn($fig2);
    my @px2 = $ax2->get_xlim;
    my @tx2 = $tw2->get_xlim;
    ok(near($px2[0], 1) && near($px2[1], 9) && near($tx2[0], 1) && near($tx2[1], 9),
       "twin then parent: the parent's range wins in both (@px2 / @tx2)");
}

# ---- twiny: ylim on the twin, including negative-up ----
{
    my $fig = figure(width => 400, height => 300);
    my $ax  = $fig->axes;
    $ax->line(sequence(11), sequence(11));
    my $tw = $ax->twiny;
    $tw->line(sequence(11) * 10, sequence(11));
    $tw->ylim(-2, 12);
    drawn($fig);
    my @py = $ax->get_ylim;
    my @ty = $tw->get_ylim;
    ok(near($py[0], -2) && near($py[1], 12), "twiny: parent y range is the one given on the twin (@py)");
    ok(near($ty[0], -2) && near($ty[1], 12), "twiny: twin y range too (@ty)");

    my $fig2 = figure(width => 400, height => 300);
    my $ax2  = $fig2->axes;
    $ax2->line(sequence(11), sequence(11));
    my $tw2 = $ax2->twiny;
    $tw2->ylim(10, 0);                          # negative up
    drawn($fig2);
    my (undef, $p_top) = $ax2->data_to_pixel(pdl(0), pdl(10));
    my (undef, $p_bot) = $ax2->data_to_pixel(pdl(0), pdl(0));
    ok($p_top->sclr > $p_bot->sclr, 'twiny ylim(10, 0): the parent is drawn negative up (10 lower than 0)');
    my (undef, $t_top) = $tw2->data_to_pixel(pdl(0), pdl(10));
    ok(near($t_top->sclr, $p_top->sclr), 'twiny ylim(10, 0): y = 10 at the same pixel in the twin');
}

# ---- not a twin: unchanged ----
{
    my $fig = figure(width => 400, height => 300);
    my $ax  = $fig->axes;
    $ax->line(sequence(11), sequence(11));
    $ax->xlim(4, 6);
    drawn($fig);
    my @px = $ax->get_xlim;
    ok(near($px[0], 4) && near($px[1], 6), "plain axes: xlim as before (@px)");
}

done_testing;
