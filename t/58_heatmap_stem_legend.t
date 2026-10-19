use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);

# heatmap() draws its cells (row 0 at the top, as seaborn's heatmap; cells
# whose value is not finite stay empty; annot => 1 writes the values), and
# stem(label => ...) puts an entry in the legend. Up to 0.42 heatmap() queued
# a command that nothing drew (only ticks and colorbar appeared), and stem
# ignored label for the legend.

# RGB (0..255) of the figure pixel at data point ($x, $y) of $ax
sub pixel_at {
    my ($f, $ax, $x, $y) = @_;
    my $d = PDL::Graphics::Cairo::Driver::Cairo->new(
        width => $f->width, height => $f->height, file => ':memory:');
    $f->_render_to($d);
    my $s = $d->{surface};
    $s->flush;
    my ($px, $py) = map { int } $ax->data_to_pixel($x, $y);
    my ($bl, $g, $r) = unpack 'C3', substr($s->get_data, $py * $s->get_stride + $px * 4, 4);
    return [$r, $g, $bl];                 # ARGB32 little-endian: B, G, R, A
}

my $data = sequence(4, 3)->double;      # 4 rows, 3 columns: at(r, c) = r + 4c
$data->set(1, 2, 'nan' + 0);            # row 1, column 2 empty
my $f  = figure(width => 300, height => 300);
my $ax = $f->axes;
$ax->heatmap($data, cmap => 'viridis');
my $cmap = $ax->_resolve_cmap('viridis');

my $bad = 0;
for my $r (0 .. 3) {
    for my $c (0 .. 2) {
        next if $r == 1 && $c == 2;
        # cell centre a little off the exact centre, away from any text
        my $got  = pixel_at($f, $ax, $c + 0.3, 3 - $r + 0.3);
        my @want = map { int($_ * 255 + 0.5) } $cmap->rgb_norm($data->at($r, $c), 0, 11);
        my $d = 0; $d += abs($got->[$_] - $want[$_]) for 0 .. 2;
        $bad++ if $d > 6;
    }
}
is($bad, 0, 'each cell has its colour, row 0 at the top');
is_deeply(pixel_at($f, $ax, 2.3, 2.3), [255, 255, 255], 'NaN cell stays empty (white background)');
is_deeply([ @{ $ax->_yticks } ], [3, 2, 1, 0], 'y tick of row r at rows-1-r');

# annot: some dark pixels inside a light cell (the text), none without annot
{
    my $count_dark = sub {
        my ($annot) = @_;
        my $f2 = figure(width => 300, height => 300);
        my $a2 = $f2->axes;
        $a2->heatmap(pdl([[0, 1], [1, 0]])->double, cmap => 'gray', annot => $annot);
        my $d = PDL::Graphics::Cairo::Driver::Cairo->new(width => 300, height => 300, file => ':memory:');
        $f2->_render_to($d);
        my $s = $d->{surface}; $s->flush;
        # row 1, column 0 has value 1 (white in gray): the cell around (0, 0)
        my ($x0, $y0) = map { int } $a2->data_to_pixel(-0.35, 0.35);
        my ($x1, $y1) = map { int } $a2->data_to_pixel(0.35, -0.35);
        my $n = 0;
        for my $y ($y0 .. $y1) { for my $x ($x0 .. $x1) {
            my @c = unpack 'C3', substr($s->get_data, $y * $s->get_stride + $x * 4, 4);
            $n++ if $c[0] < 100 && $c[1] < 100 && $c[2] < 100;
        } }
        return $n;
    };
    my ($with, $without) = ($count_dark->(1), $count_dark->(0));
    cmp_ok($with, '>', 10, "annot writes the value ($with dark pixels)");
    is($without, 0, 'no text without annot');
}

# stem label in the legend
{
    my $a3 = figure(width => 100, height => 100)->axes;
    $a3->stem(sequence(3), sequence(3), label => 's');
    my $lg = $a3->_legends->[-1];
    ok($lg && ($lg->{label} // '') eq 's', 'stem label in the legend');
    is($lg && $lg->{type}, 'marker', '... shown as a marker');
}

done_testing;
