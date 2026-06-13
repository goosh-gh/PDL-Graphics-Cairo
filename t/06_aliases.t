use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);

# matplotlib Axes-method 名のエイリアスが、短縮形の正準実装と同一に振る舞うこと。
# すべて加法的な追加であり、既存の短縮形 API は不変。

my $fig = figure(width => 400, height => 300);
my $ax  = $fig->axes();

# --- メソッド存在チェック ------------------------------------------
for my $m (qw(set_xlim set_ylim set_xticks set_yticks plot)) {
    can_ok $ax, $m;
}

# plot は line のエイリアス（同一コードリファレンス）
is \&PDL::Graphics::Cairo::Axes::plot,
   \&PDL::Graphics::Cairo::Axes::line,
   'plot is an alias of line';

# --- set_xlim == xlim ----------------------------------------------
$ax->set_xlim(-5, 12);
is $ax->xmin, -5, 'set_xlim sets xmin';
is $ax->xmax, 12, 'set_xlim sets xmax';

# --- set_ylim は ylim の反転則(lo>hi)を継承 ------------------------
$ax->set_ylim(10, -10);            # negative up
is $ax->ymin, -10, 'set_ylim(lo>hi) sets ymin to the smaller value';
is $ax->ymax,  10, 'set_ylim(lo>hi) sets ymax to the larger value';
ok $ax->{_y_reversed}, 'set_ylim(lo>hi) triggers Y-axis reversal (negative up)';

$ax->set_ylim(0, 20);              # normal order
ok !$ax->{_y_reversed}, 'set_ylim(lo<hi) leaves axis un-reversed';

# --- set_xticks / set_yticks -> ticks ------------------------------
eval { $ax->set_xticks(pdl(0, 1, 2)); $ax->set_yticks(pdl(0, 5, 10)) };
is $@, '', 'set_xticks/set_yticks no error';

# --- 重複していた set_tight_layout が単一であること（no-op, 返り値=self） ----
do { local $SIG{__WARN__} = sub {};
     is $ax->set_tight_layout, $ax, 'set_tight_layout is a no-op returning self'; };

# --- PDL::Graphics::Cairo->new は figure() の別名 -------------------
can_ok 'PDL::Graphics::Cairo', 'new';
my $fig2 = PDL::Graphics::Cairo->new(width => 640, height => 480);
isa_ok $fig2, 'PDL::Graphics::Cairo::Figure', 'new() returns a Figure';
is $fig2->width,  640, 'new() honors width';
is $fig2->height, 480, 'new() honors height';

done_testing;
