use strict;
use warnings;
use Test::More;
use PDL;
use lib 'lib';
use PDL::Graphics::Cairo::PGPLOT qw(:cpg);

# PGPLOT の NXSUB 符号でパネルの格納/送り順が決まることを検証する。
#   NXSUB > 0 → 行優先(左→右, 上→下)  [PGPLOT 既定]
#   NXSUB < 0 → 列優先(上→下, 左→右)
# また cpgpanl(ix,iy) はどちらの順序でも「物理パネル(列 ix, 行 iy)」を選ぶ。
# 描画は不要(Axes の fig_x/fig_y と current_ax だけを見る)ので Cairo 非依存。

my $S = PDL::Graphics::Cairo::PGPLOT::_state();
sub setup { my ($nx,$ny)=@_; $S->{width}=600; $S->{height}=400;
            PDL::Graphics::Cairo::PGPLOT::_new_figure(); cpgsubp($nx,$ny); }
sub axpos { my ($ax)=@_; ($ax->fig_x, $ax->fig_y) }   # 3x2 → cw=200, ch=200

# ---- ROW-major (positive NXSUB): PGPLOT default --------------------
setup(3,2);
is($S->{col_major}, 0, 'cpgsubp(3,2): row-major (col_major=0)');
is_deeply([axpos($S->{axes}[1])], [200,0],   'row-major: axes[1] is right of axes[0]');
is_deeply([axpos($S->{axes}[3])], [0,200],   'row-major: axes[3] starts the next row');
PDL::Graphics::Cairo::PGPLOT::cpgpanl(3,1);
is_deeply([axpos($S->{current_ax})], [400,0],   'row-major: cpgpanl(3,1) -> physical col3,row1');
PDL::Graphics::Cairo::PGPLOT::cpgpanl(1,2);
is_deeply([axpos($S->{current_ax})], [0,200],   'row-major: cpgpanl(1,2) -> physical col1,row2');

# ---- COLUMN-major (negative NXSUB) --------------------------------
setup(-3,2);
is($S->{col_major}, 1, 'cpgsubp(-3,2): column-major (col_major=1)');
is_deeply([axpos($S->{axes}[1])], [0,200],   'col-major: axes[1] is below axes[0]');
is_deeply([axpos($S->{axes}[2])], [200,0],   'col-major: axes[2] starts the next column');
# cpgpanl addresses the physical cell, so it lands on the SAME place as row-major
PDL::Graphics::Cairo::PGPLOT::cpgpanl(3,1);
is_deeply([axpos($S->{current_ax})], [400,0],   'col-major: cpgpanl(3,1) -> same physical col3,row1');
PDL::Graphics::Cairo::PGPLOT::cpgpanl(1,2);
is_deeply([axpos($S->{current_ax})], [0,200],   'col-major: cpgpanl(1,2) -> same physical col1,row2');

# ---- cpgpage advances in storage order ----------------------------
setup(3,2);
PDL::Graphics::Cairo::PGPLOT::cpgpage();
is_deeply([axpos($S->{current_ax})], [200,0], 'row-major: cpgpage advances left->right');
setup(-3,2);
PDL::Graphics::Cairo::PGPLOT::cpgpage();
is_deeply([axpos($S->{current_ax})], [0,200], 'col-major: cpgpage advances top->bottom');

done_testing();
