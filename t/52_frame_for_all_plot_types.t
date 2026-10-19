use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);

# The frame, ticks and labels are drawn when the axes has anything to plot.
# Before P:G:C30 draw() listed the plot types that count, and pcolormesh,
# contour, hexbin, heatmap and specgram were missing: an axes with only one
# of them had no frame, no tick numbers and no xlabel/ylabel frame.
# Text alone (text(), PGPLOT pgmtxt/pgtick) still draws no frame.

sub frames_drawn {
    my ($plot) = @_;
    my $f  = figure(width => 240, height => 180);
    my $ax = $f->axes;
    $plot->($ax);
    my $n = 0;
    no warnings 'redefine';
    my $orig = \&PDL::Graphics::Cairo::Axes::_draw_frame;
    local *PDL::Graphics::Cairo::Axes::_draw_frame = sub { $n++; $orig->(@_) };
    my $d = PDL::Graphics::Cairo::Driver::Cairo->new(
        width => 240, height => 180, file => ':memory:');
    $f->_render_to($d);
    return $n;
}

my @plots = (
    [ line       => sub { $_[0]->line(sequence(5), sequence(5)) } ],
    [ pcolormesh => sub { $_[0]->pcolormesh(sequence(5), sequence(4), sequence(3, 4)) } ],
    [ contour    => sub { $_[0]->contour(sequence(10, 10)->double) } ],
    [ contourf   => sub { $_[0]->contourf(sequence(10, 10)->double) } ],
    [ hexbin     => sub { $_[0]->hexbin(sequence(50)->double / 50, (sequence(50) % 7)->double / 7) } ],
    [ heatmap    => sub { $_[0]->heatmap(sequence(4, 3)) } ],
    [ specgram   => sub { $_[0]->specgram(sin(sequence(2048) / 5), Fs => 100) } ],
    [ imshow     => sub { $_[0]->imshow(sequence(3, 3)) } ],
);
for my $p (@plots) {
    my ($name, $code) = @$p;
    is(frames_drawn($code), 1, "$name alone: frame drawn");
}

is(frames_drawn(sub { $_[0]->text(0.5, 0.5, 'note') }), 0,
   'text alone: no frame (unchanged)');

# hexbin above puts each point in its own hexagon: every count is 1, so its
# colorbar has vmin == vmax. Drawing it divided by zero before P:G:C30.
{
    my $f  = figure(width => 240, height => 180);
    my $ax = $f->axes;
    $ax->hexbin(sequence(50)->double / 50, (sequence(50) % 7)->double / 7);
    my $d = PDL::Graphics::Cairo::Driver::Cairo->new(
        width => 240, height => 180, file => ':memory:');
    ok(eval { $f->_render_to($d); 1 },
       'hexbin with equal counts (colorbar vmin == vmax) draws without dying') or diag $@;
}

done_testing;
