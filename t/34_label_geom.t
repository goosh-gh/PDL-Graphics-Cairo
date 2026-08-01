use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/../lib";
use PDL::Graphics::Cairo::LabelGeom qw(tessellate tessellate_text billboard_tris label_to_world_tris signed_area);

sub tri_area2d { my ($t)=@_; my ($a,$b,$c)=@$t;
    return abs(($b->[0]-$a->[0])*($c->[1]-$a->[1]) - ($c->[0]-$a->[0])*($b->[1]-$a->[1]))/2; }
sub sum_area { my ($ts)=@_; my $s=0; $s+=tri_area2d($_) for @$ts; return $s; }
sub covers { my ($ts,$px,$py)=@_;
    for my $t (@$ts) { my ($a,$b,$c)=@$t;
        my $d=($b->[1]-$c->[1])*($a->[0]-$c->[0])+($c->[0]-$b->[0])*($a->[1]-$c->[1]);
        next if abs($d)<1e-12;
        my $wa=(($b->[1]-$c->[1])*($px-$c->[0])+($c->[0]-$b->[0])*($py-$c->[1]))/$d;
        my $wb=(($c->[1]-$a->[1])*($px-$c->[0])+($a->[0]-$c->[0])*($py-$c->[1]))/$d;
        my $wc=1-$wa-$wb;
        return 1 if $wa>=-1e-9 && $wb>=-1e-9 && $wc>=-1e-9;
    }
    return 0;
}

my $sq = [ [0,0],[10,0],[10,10],[0,10] ];
my $t1 = tessellate([$sq]);
is(scalar @$t1, 2, "square -> 2 triangles");
ok(abs(sum_area($t1) - 100) < 1e-9, "square area preserved (100)");

my $outer = [ [0,0],[20,0],[20,20],[0,20] ];
my $hole  = [ [6,6],[6,14],[14,14],[14,6] ];
my $tO = tessellate([$outer, $hole]);
ok(abs(sum_area($tO) - (400-64)) < 1e-6, "O filled area == outer-hole (336)");
ok(!covers($tO,10,10), "O hole center not covered");

my $L = [ [0,0],[10,0],[10,4],[4,4],[4,10],[0,10] ];
my $tL = tessellate([$L]);
ok(abs(sum_area($tL) - 64) < 1e-6, "L-shape area preserved (64)");
ok( (grep { tri_area2d($_) < 1e-9 } @$tL) == 0, "no degenerate triangles in L");

my $right=[1,0,0]; my $up=[0,0,1]; my $origin=[5,5,50];
my $w = billboard_tris([ [ [0,0],[2,0],[0,3] ] ], $origin, $right, $up);
is_deeply($w->[0][0], [5,5,50], "vertex (0,0) -> origin");
is_deeply($w->[0][1], [7,5,50], "vertex (2,0) -> +2*right(X)");
is_deeply($w->[0][2], [5,5,53], "vertex (0,3) -> +3*up(Z)");
my ($A,$B,$C)=@{$w->[0]};
my @u=map{$B->[$_]-$A->[$_]}0..2; my @v=map{$C->[$_]-$A->[$_]}0..2;
my @n=($u[1]*$v[2]-$u[2]*$v[1],$u[2]*$v[0]-$u[0]*$v[2],$u[0]*$v[1]-$u[1]*$v[0]);
ok(abs($n[0])<1e-9 && abs($n[2])<1e-9 && abs($n[1])>0, "billboard normal parallel to view axis (Y)");

my $wO = billboard_tris($tO, $origin, $right, $up);
sub tri_area3d { my($t)=@_; my($a,$b,$c)=@$t;
    my @u=map{$b->[$_]-$a->[$_]}0..2; my @v=map{$c->[$_]-$a->[$_]}0..2;
    my @n=($u[1]*$v[2]-$u[2]*$v[1],$u[2]*$v[0]-$u[0]*$v[2],$u[0]*$v[1]-$u[1]*$v[0]);
    return 0.5*sqrt($n[0]**2+$n[1]**2+$n[2]**2); }
my $a3=0; $a3+=tri_area3d($_) for @$wO;
ok(abs($a3-336)<1e-6, "world-space label area preserved (336)");

my $g1o=[[0,0],[6,0],[6,6],[0,6]];     my $g1h=[[2,2],[2,4],[4,4],[4,2]];
my $g2o=[[10,0],[16,0],[16,6],[10,6]]; my $g2h=[[12,2],[12,4],[14,4],[14,2]];
my $tt = tessellate_text([$g1o,$g1h,$g2o,$g2h]);
ok(abs(sum_area($tt) - 64) < 1e-6, "two-glyph text area == 2*(36-4)=64");
ok(!covers($tt,3,3),  "glyph#1 hole center not covered");
ok(!covers($tt,13,3), "glyph#2 hole center not covered");

done_testing();
