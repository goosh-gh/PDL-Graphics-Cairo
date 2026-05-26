#!/usr/bin/env perl
use strict; use warnings;
use GraphViz2;
use PDL;
use PDL::IO::Pic;
use PDL::Graphics::Cairo qw(figure);

# --- 1. GraphViz2でグラフ生成 ---
my $g = GraphViz2->new(
    global => { directed => 1 },
    graph  => { rankdir => 'LR', splines => 'true' },
    node   => { shape => 'circle', style => 'filled',
                fillcolor => 'lightblue', fontname => 'Helvetica' },
    edge   => { color => 'gray40' },
);

my @x = qw(x1 x2 x3);
my @h = qw(h1 h2 h3 h4);
my @y = qw(y1 y2);

$g->add_node(name => $_) for (@x, @h, @y);
for my $xi (@x) { for my $h (@h) { $g->add_edge(from => $xi, to => $h) } }
for my $h  (@h) { for my $y (@y) { $g->add_edge(from => $h,  to => $y) } }

my $tmpfile = "/tmp/backprop_network.png";
$g->run(format => 'png', output_file => $tmpfile);
print "GraphViz2: saved $tmpfile\n";

# --- 2. PDL::Graphics::Cairoで/osxに表示 ---
my $img  = rpic($tmpfile);      # [3, W, H] uint8
my $w_px = $img->dim(1);
my $h_px = $img->dim(2);

my $fig = figure(width => $w_px, height => $h_px);
my $ax  = $fig->axes();

my $rgb = $img->float / 255.0;  # [3, W, H] → float
my $hwc = $rgb->reorder(2,1,0); # [H, W, 3]
$ax->imshow($hwc, origin => 'lower');
$ax->axis('off');

$fig->tight_layout();
$fig->show(backend => 'osx');
