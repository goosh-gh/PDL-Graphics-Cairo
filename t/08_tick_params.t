use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

# ----------------------------------------------------------------
# 1. tick_params() stores values in _tick_params hash
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);

    $ax->tick_params(labelsize => 12);
    my $tp = $ax->_tick_params;
    is $tp->{x_labelsize}, 12, 'labelsize stored for x';
    is $tp->{y_labelsize}, 12, 'labelsize stored for y';
}

# ----------------------------------------------------------------
# 2. axis=>'x' only affects x
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);

    $ax->tick_params(axis=>'x', labelsize=>14, direction=>'in');
    my $tp = $ax->_tick_params;
    is  $tp->{x_labelsize},  14,   'x_labelsize set';
    is  $tp->{x_direction},  'in', 'x_direction set';
    ok !defined($tp->{y_labelsize}),  'y_labelsize not set when axis=>x';
    ok !defined($tp->{y_direction}),  'y_direction not set when axis=>x';
}

# ----------------------------------------------------------------
# 3. axis=>'y' only affects y
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);

    $ax->tick_params(axis=>'y', labelsize=>6, length=>8, width=>2);
    my $tp = $ax->_tick_params;
    ok !defined($tp->{x_labelsize}), 'x_labelsize untouched when axis=>y';
    is $tp->{y_labelsize}, 6,  'y_labelsize set';
    is $tp->{y_length},    8,  'y_length set';
    is $tp->{y_width},     2,  'y_width set';
}

# ----------------------------------------------------------------
# 4. colors=> sets both color and labelcolor
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);

    $ax->tick_params(colors=>'red');
    my $tp = $ax->_tick_params;
    is $tp->{x_color},      'red', 'x_color set via colors';
    is $tp->{x_labelcolor}, 'red', 'x_labelcolor set via colors';
    is $tp->{y_color},      'red', 'y_color set via colors';
    is $tp->{y_labelcolor}, 'red', 'y_labelcolor set via colors';
}

# ----------------------------------------------------------------
# 5. color and labelcolor individually
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);

    $ax->tick_params(color=>'blue', labelcolor=>'gray');
    my $tp = $ax->_tick_params;
    is $tp->{x_color},      'blue', 'x_color';
    is $tp->{x_labelcolor}, 'gray', 'x_labelcolor';
}

# ----------------------------------------------------------------
# 6. direction values
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);

    for my $dir (qw(in out inout)) {
        $ax->tick_params(direction=>$dir);
        is $ax->_tick_params->{x_direction}, $dir, "direction=$dir stored";
    }
}

# ----------------------------------------------------------------
# 7. bottom/top/left/right visibility flags
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);

    $ax->tick_params(axis=>'x', bottom=>0, top=>1);
    my $tp = $ax->_tick_params;
    is $tp->{x_bottom}, 0, 'x_bottom=0';
    is $tp->{x_top},    1, 'x_top=1';

    $ax->tick_params(axis=>'y', left=>1, right=>1);
    is $tp->{y_left},  1, 'y_left=1';
    is $tp->{y_right}, 1, 'y_right=1';
}

# ----------------------------------------------------------------
# 8. labelbottom/labelleft hide flags
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);

    $ax->tick_params(labelbottom=>0, labelleft=>0);
    my $tp = $ax->_tick_params;
    is $tp->{x_labelbottom}, 0, 'labelbottom=0';
    is $tp->{y_labelleft},   0, 'labelleft=0';
}

# ----------------------------------------------------------------
# 9. labelrotation
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);

    $ax->tick_params(axis=>'x', labelrotation=>45);
    is $ax->_tick_params->{x_labelrotation}, 45, 'x_labelrotation=45';
}

# ----------------------------------------------------------------
# 10. pad
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);

    $ax->tick_params(pad=>8);
    is $ax->_tick_params->{x_pad}, 8, 'x_pad=8';
    is $ax->_tick_params->{y_pad}, 8, 'y_pad=8';
}

# ----------------------------------------------------------------
# 11. which=>'minor' stored (rendering deferred to minor tick impl)
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);

    $ax->tick_params(which=>'minor', length=>2, width=>0.5);
    my $tp = $ax->_tick_params;
    is $tp->{x_which},  'minor', 'which=minor stored for x';
    is $tp->{y_which},  'minor', 'which=minor stored for y';
    is $tp->{x_length}, 2,       'minor length stored';
}

# ----------------------------------------------------------------
# 12. chaining returns $self
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $ret = $ax->tick_params(labelsize=>10);
    is $ret, $ax, 'tick_params returns $self for chaining';
}

# ----------------------------------------------------------------
# 13. multiple calls accumulate (later call wins for same key)
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);

    $ax->tick_params(labelsize=>8);
    $ax->tick_params(axis=>'x', labelsize=>14);   # override x only
    my $tp = $ax->_tick_params;
    is $tp->{x_labelsize}, 14, 'second call overrides x_labelsize';
    is $tp->{y_labelsize},  8, 'y_labelsize unchanged by axis=>x call';
}

# ----------------------------------------------------------------
# 14. PNG render smoke test — tick_params changes don't crash draw()
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->line(pdl(1,2,3), pdl(1,4,9));
    $ax->tick_params(
        labelsize  => 11,
        direction  => 'in',
        length     => 6,
        width      => 1.5,
        colors     => 'blue',
        top        => 1,
        right      => 1,
    );
    $ax->xlabel('X axis');
    $ax->ylabel('Y axis');
    $fig->tight_layout;

    my $tmp = "/tmp/tick_params_smoke_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "save() with tick_params does not die: $@";
    ok -f $tmp && -s $tmp > 1000, 'PNG output has content';
    unlink $tmp;
}

# ----------------------------------------------------------------
# 15. direction=>'in' tick position smoke (no crash)
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>300, height=>300);
    $ax->scatter(pdl(1..5), pdl(2,4,1,5,3));
    $ax->tick_params(direction=>'in', length=>8);
    $fig->tight_layout;
    my $tmp = "/tmp/tick_in_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "direction=in: no crash";
    unlink $tmp;
}

# ----------------------------------------------------------------
# 16. labelbottom=>0 hides x labels (smoke only)
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>300, height=>300);
    $ax->line(pdl(1..4), pdl(1..4));
    $ax->tick_params(labelbottom=>0);
    $fig->tight_layout;
    my $tmp = "/tmp/tick_nolabel_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "labelbottom=>0: no crash";
    unlink $tmp;
}

done_testing;
