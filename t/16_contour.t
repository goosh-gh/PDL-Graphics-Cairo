use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

my $PI = 3.14159265358979;

# ----------------------------------------------------------------
# 1. contour queues a command
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $x = sequence(10);
    my $y = sequence(10);
    my $z = $x->slice(':,*1') + $y->slice('*1,:');
    $ax->contour($x, $y, $z);
    is $ax->_queue->[-1]{type}, 'contour', 'contour queued';
}

# ----------------------------------------------------------------
# 2. default levels count
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $x = sequence(10);
    my $y = sequence(10);
    my $z = $x->slice(':,*1') * $y->slice('*1,:');
    $ax->contour($x, $y, $z, levels=>5);
    is scalar(@{ $ax->_queue->[-1]{levels} }), 5, 'levels=5 stored';
}

# ----------------------------------------------------------------
# 3. explicit levels array
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $x = sequence(10);
    my $y = sequence(10);
    my $z = $x->slice(':,*1') + $y->slice('*1,:');
    $ax->contour($x, $y, $z, levels=>[2,4,6,8,10]);
    my $lvls = $ax->_queue->[-1]{levels};
    is scalar(@$lvls), 5, 'explicit 5 levels';
    is $lvls->[0], 2, 'first level=2';
    is $lvls->[-1], 10, 'last level=10';
}

# ----------------------------------------------------------------
# 4. color option stored
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $x = sequence(5); my $y = sequence(5);
    my $z = $x->slice(':,*1') + $y->slice('*1,:');
    $ax->contour($x, $y, $z, colors=>'red');
    is $ax->_queue->[-1]{colors}, 'red', 'colors stored';
}

# ----------------------------------------------------------------
# 5. linewidths stored
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $x = sequence(5); my $y = sequence(5);
    my $z = $x->slice(':,*1') + $y->slice('*1,:');
    $ax->contour($x, $y, $z, linewidths=>2.0);
    is $ax->_queue->[-1]{linewidths}, 2.0, 'linewidths stored';
}

# ----------------------------------------------------------------
# 6. contour chains
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $x = sequence(5); my $y = sequence(5);
    my $z = $x->slice(':,*1') + $y->slice('*1,:');
    is $ax->contour($x, $y, $z), $ax, 'contour chains';
}

# ----------------------------------------------------------------
# 7. PNG smoke: basic contour
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>450);
    my $x = sequence(30) / 29 * 4 - 2;  # -2..2
    my $y = sequence(30) / 29 * 4 - 2;
    my $z = $x->slice(':,*1')**2 + $y->slice('*1,:')**2;  # bowl

    $ax->contour($x, $y, $z, levels=>8, colors=>'navy', linewidths=>1.0);
    $ax->xlabel('X'); $ax->ylabel('Y');
    $ax->title('Contour: x^2 + y^2');
    $ax->set_aspect('equal');
    $fig->tight_layout;
    my $tmp = "/tmp/contour_bowl_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "basic contour: no die ($@)";
    ok -f $tmp && -s $tmp > 500, 'PNG has content';
    unlink $tmp;
}

# ----------------------------------------------------------------
# 8. PNG smoke: contourf + contour overlay
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>450);
    my $x = sequence(40) / 39 * 6 - 3;
    my $y = sequence(40) / 39 * 6 - 3;
    my $z = sin($x->slice(':,*1')) * cos($y->slice('*1,:'));

    $ax->contourf($x, $y, $z, levels=>10, cmap=>'RdBu');
    $ax->contour( $x, $y, $z, levels=>10, colors=>'black', linewidths=>0.5);
    $ax->xlabel('X'); $ax->ylabel('Y');
    $ax->title('contourf + contour overlay: sin(x)*cos(y)');
    $fig->tight_layout;
    my $tmp = "/tmp/contour_overlay_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "contourf+contour overlay: no die ($@)";
    ok -f $tmp && -s $tmp > 1000, 'PNG has content';
    unlink $tmp;
}

# ----------------------------------------------------------------
# 9. PNG smoke: multi-color contour levels
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>450);
    my $x = sequence(25) / 24 * 4 - 2;
    my $y = sequence(25) / 24 * 4 - 2;
    my $z = ($x->slice(':,*1'))**2 - ($y->slice('*1,:')**2);  # saddle

    my @level_colors = ('blue','cyan','green','yellow','orange','red');
    $ax->contour($x, $y, $z,
        levels  => [map { -3 + $_ } 0..5],
        colors  => \@level_colors,
        linewidths => 1.5,
    );
    $ax->xlabel('X'); $ax->ylabel('Y');
    $ax->title('Saddle surface: x^2 - y^2 (multi-color)');
    $fig->tight_layout;
    my $tmp = "/tmp/contour_saddle_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "multi-color contour: no die ($@)";
    unlink $tmp;
}

# ----------------------------------------------------------------
# 10. PNG smoke: dashed contour lines
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>450);
    my $x = sequence(30) / 29 * 2 * $PI;
    my $y = sequence(30) / 29 * 2 * $PI;
    my $z = sin($x->slice(':,*1')) + sin($y->slice('*1,:'));

    # Positive levels solid, negative dashed
    $ax->contour($x, $y, $z,
        levels     => [map { -2 + $_ * 0.5 } 0..7],
        colors     => 'black',
        linestyles => [map { $_ < 0 ? 'dashed' : 'solid' }
                       map { -2 + $_ * 0.5 } 0..7],
        linewidths => 1.0,
    );
    $ax->xlabel('X'); $ax->ylabel('Y');
    $ax->title('sin(x)+sin(y): negative=dashed');
    $fig->tight_layout;
    my $tmp = "/tmp/contour_dashed_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "dashed contour: no die ($@)";
    unlink $tmp;
}

done_testing;
