use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots ListedColormap Normalize LogNorm BoundaryNorm TwoSlopeNorm);
use PDL::Graphics::Cairo::ListedColormap;

# ================================================================
# ListedColormap
# ================================================================

# ----------------------------------------------------------------
# 1. Construction with named colors
# ----------------------------------------------------------------
{
    my $cmap = ListedColormap(['red','green','blue']);
    isa_ok $cmap, 'PDL::Graphics::Cairo::ListedColormap', 'ListedColormap from names';
}

# ----------------------------------------------------------------
# 2. Construction with rgb arrayrefs
# ----------------------------------------------------------------
{
    my $cmap = ListedColormap([[1,0,0],[0,1,0],[0,0,1]]);
    isa_ok $cmap, 'PDL::Graphics::Cairo::ListedColormap', 'ListedColormap from arrayrefs';
}

# ----------------------------------------------------------------
# 3. rgb_at returns correct colors
# ----------------------------------------------------------------
{
    my $cmap = ListedColormap([[1,0,0],[0,1,0],[0,0,1]]);
    my @c0 = $cmap->rgb_at(0.0);   # first color: red
    my @c1 = $cmap->rgb_at(1.0);   # last color: blue
    ok abs($c0[0] - 1) < 0.01, 'rgb_at(0) red channel = 1';
    ok abs($c0[1])     < 0.01, 'rgb_at(0) green channel = 0';
    ok abs($c1[2] - 1) < 0.01, 'rgb_at(1) blue channel = 1';
}

# ----------------------------------------------------------------
# 4. rgb_at t=0.5 → middle color
# ----------------------------------------------------------------
{
    my $cmap = ListedColormap([[1,0,0],[0,1,0],[0,0,1]]);
    my @c = $cmap->rgb_at(0.5);
    ok abs($c[1] - 1) < 0.01, 'rgb_at(0.5) → green (middle)';
}

# ----------------------------------------------------------------
# 5. rgb_norm
# ----------------------------------------------------------------
{
    my $cmap = ListedColormap([[1,0,0],[0,0,1]]);
    my @c = $cmap->rgb_norm(75, 0, 100);   # 75% → blue
#    ok abs($norm->call(10) - 1/3) < 0.01, 'LogNorm(10) = 1/3 (log10(10)/log10(1000))';
     ok abs($c[2] - 1) < 0.01, 'rgb_norm(75,0,100) → blue';
}

# ----------------------------------------------------------------
# 6. lut returns N entries
# ----------------------------------------------------------------
{
    my $cmap = ListedColormap([[1,0,0],[0,1,0],[0,0,1]]);
    my $lut = $cmap->lut(9);
    is scalar(@$lut), 9, 'lut returns 9 entries';
}

# ----------------------------------------------------------------
# 7. hex color parsing
# ----------------------------------------------------------------
{
    my $cmap = ListedColormap(['#ff0000','#00ff00','#0000ff']);
    my @c = $cmap->rgb_at(0.0);
    ok abs($c[0] - 1) < 0.01, 'hex color #ff0000 parsed';
}

# ================================================================
# Normalize
# ================================================================

# ----------------------------------------------------------------
# 8. Normalize basic
# ----------------------------------------------------------------
{
    my $norm = Normalize(vmin=>0, vmax=>100);
    isa_ok $norm, 'PDL::Graphics::Cairo::Normalize';
    ok abs($norm->call(50) - 0.5) < 1e-6, 'Normalize 50 → 0.5';
    ok abs($norm->call(0)  - 0.0) < 1e-6, 'Normalize 0 → 0';
    ok abs($norm->call(100)- 1.0) < 1e-6, 'Normalize 100 → 1';
}

# ----------------------------------------------------------------
# 9. Normalize extrapolates beyond range
# ----------------------------------------------------------------
{
    my $norm = Normalize(vmin=>0, vmax=>10);
    ok $norm->call(20) > 1, 'Normalize extrapolates above vmax';
    ok $norm->call(-5) < 0, 'Normalize extrapolates below vmin';
}

# ----------------------------------------------------------------
# 10. Normalize with clip
# ----------------------------------------------------------------
{
    my $norm = Normalize(vmin=>0, vmax=>10, clip=>1);
    ok abs($norm->call(20) - 1) < 1e-6, 'clip: above vmax → 1';
    ok abs($norm->call(-5) - 0) < 1e-6, 'clip: below vmin → 0';
}

# ----------------------------------------------------------------
# 11. LogNorm
# ----------------------------------------------------------------
{
    my $norm = LogNorm(vmin=>1, vmax=>1000);
    isa_ok $norm, 'PDL::Graphics::Cairo::LogNorm';
    ok abs($norm->call(1)    - 0.0) < 1e-6, 'LogNorm(1) → 0';
    ok abs($norm->call(1000) - 1.0) < 1e-6, 'LogNorm(1000) → 1';
#    ok abs($norm->call(10)   - 0.5) < 0.01, 'LogNorm(10) ≈ 0.5 (geometric midpoint of 1..1000 is ~31.6, log10 midpoint=1.5/3=0.5)';
    ok abs($norm->call(10) - 1/3) < 0.01, 'LogNorm(10) = 1/3 (log10(10)/log10(1000))';
}

# ----------------------------------------------------------------
# 12. BoundaryNorm
# ----------------------------------------------------------------
{
    my $norm = BoundaryNorm(boundaries=>[0,1,5,10,50]);
    isa_ok $norm, 'PDL::Graphics::Cairo::BoundaryNorm';
    my $t1 = $norm->call(0.5);   # in bucket 0
    my $t2 = $norm->call(7);     # in bucket 2
    ok $t1 < $t2, 'BoundaryNorm: lower val → lower t';
}

# ----------------------------------------------------------------
# 13. TwoSlopeNorm
# ----------------------------------------------------------------
{
    my $norm = TwoSlopeNorm(vmin=>-10, vcenter=>0, vmax=>20);
    isa_ok $norm, 'PDL::Graphics::Cairo::TwoSlopeNorm';
    ok abs($norm->call(-10) - 0.0) < 1e-6, 'TwoSlopeNorm vmin → 0';
    ok abs($norm->call(0)   - 0.5) < 1e-6, 'TwoSlopeNorm vcenter → 0.5';
    ok abs($norm->call(20)  - 1.0) < 1e-6, 'TwoSlopeNorm vmax → 1';
    ok $norm->call(-5) < 0.5, 'TwoSlopeNorm negative val → < 0.5';
    ok $norm->call(10) > 0.5, 'TwoSlopeNorm positive val → > 0.5';
}

# ================================================================
# Integration: ListedColormap with scatter/hexbin
# ================================================================

# ----------------------------------------------------------------
# 14. scatter with ListedColormap object
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $cmap = ListedColormap(['blue','red','yellow','green']);
    eval {
        $ax->scatter(pdl(1..10), pdl(1..10),
            c    => pdl(map { rand() } 1..10),
            cmap => $cmap);
        $fig->tight_layout;
        my $tmp = "/tmp/listed_scatter_$$.png";
        $fig->save($tmp);
        unlink $tmp;
    };
    ok !$@, "scatter with ListedColormap: no die ($@)";
}

# ----------------------------------------------------------------
# 15. hexbin with ListedColormap object
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $cmap = ListedColormap([[0,0,1],[0,1,0],[1,0,0],[1,1,0]]);
    eval {
        $ax->hexbin(pdl(map { rand()*10 } 1..100),
                    pdl(map { rand()*10 } 1..100),
                    cmap => $cmap, gridsize=>10);
        $fig->tight_layout;
        my $tmp = "/tmp/listed_hexbin_$$.png";
        $fig->save($tmp);
        unlink $tmp;
    };
    ok !$@, "hexbin with ListedColormap: no die ($@)";
}

# ----------------------------------------------------------------
# 16. imshow with ListedColormap
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $cmap = ListedColormap(['black','white']);
    eval {
        # checkerboard
        my $img = pdl([[0,1,0,1],[1,0,1,0],[0,1,0,1],[1,0,1,0]]);
        $ax->imshow($img, cmap=>$cmap);
        $fig->tight_layout;
        my $tmp = "/tmp/listed_imshow_$$.png";
        $fig->save($tmp);
        unlink $tmp;
    };
    ok !$@, "imshow with ListedColormap: no die ($@)";
}

# ----------------------------------------------------------------
# 17. contourf with ListedColormap
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $cmap = ListedColormap(['blue','cyan','green','yellow','red']);
    eval {
        my $x = pdl([0,1,2]);
        my $y = pdl([0,1,2]);
        my $z = pdl([[1,2,3],[4,5,6],[7,8,9]]);
        $ax->contourf($x, $y, $z, cmap=>$cmap);
        $fig->tight_layout;
        my $tmp = "/tmp/listed_contourf_$$.png";
        $fig->save($tmp);
        unlink $tmp;
    };
    ok !$@, "contourf with ListedColormap: no die ($@)";
}

# ----------------------------------------------------------------
# 18. PNG smoke: diverging colormap with TwoSlopeNorm
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>400);
    my $norm = TwoSlopeNorm(vmin=>-10, vcenter=>0, vmax=>20);
    my @vals = map { -10 + rand()*30 } 1..50;
    my @cols = map { $norm->call($_) } @vals;
    eval {
        $ax->scatter(pdl(map { rand()*10 } 1..50),
                     pdl(map { rand()*10 } 1..50),
                     c    => pdl(@cols),
                     cmap => 'RdBu');
        $fig->tight_layout;
        my $tmp = "/tmp/twoslope_$$.png";
        $fig->save($tmp);
        unlink $tmp;
    };
    ok !$@, "TwoSlopeNorm + scatter: no die ($@)";
}

done_testing;
