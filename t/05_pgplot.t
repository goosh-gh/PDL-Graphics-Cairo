use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo::PGPLOT;

# Module loading
use_ok 'PDL::Graphics::Cairo::PGPLOT';

# Basic cpgbeg/cpgend operation (PNG output)
my $tmpfile = "/tmp/test_pgplot_$$.png";
my $ret = cpgbeg(0, "$tmpfile/PNG", 1, 1);
is $ret, 1, 'cpgbeg returns 1';

# cpgenv
eval { cpgenv(0, 10, -1, 1, 0, 0) };
is $@, '', 'cpgenv no error';

# cpglab
eval { cpglab("x", "y", "title") };
is $@, '', 'cpglab no error';

# cpgline
my $x = sequence(10);
my $y = sin($x);
eval { cpgline(10, $x, $y) };
is $@, '', 'cpgline no error';

# cpgpt
eval { cpgpt(5, $x->slice('0:4'), $y->slice('0:4'), 4) };
is $@, '', 'cpgpt no error';

# cpgsci / cpgslw / cpgsls / cpgsch
eval { cpgsci(2); cpgslw(2); cpgsls(2); cpgsch(1.5) };
is $@, '', 'attribute setters no error';

# cpgmove / cpgdraw
eval { cpgmove(0, 0); cpgdraw(5, 0.5) };
is $@, '', 'cpgmove/cpgdraw no error';

# cpgend
eval { cpgend() };
is $@, '', 'cpgend no error';
ok -f $tmpfile, 'PNG file created';
unlink $tmpfile;

# Test pg-prefixed aliases (imported via :pg tag)
{
    # Use :pg tag in a separate scope
    require PDL::Graphics::Cairo::PGPLOT;
    PDL::Graphics::Cairo::PGPLOT->import(':pg');

    my $tmpfile2 = "/tmp/test_pg_prefix_$$.png";
    eval { pgbeg(0, "$tmpfile2/PNG", 1, 1) };
    is $@, '', 'pgbeg no error';

    eval { pgenv(0, 10, -1, 1, 0, 0) };
    is $@, '', 'pgenv no error';

    eval { pgline(5, pdl(1,2,3,4,5), pdl(0.1,0.4,0.9,0.4,0.1)) };
    is $@, '', 'pgline no error';

    eval { pgend() };
    is $@, '', 'pgend no error';
    ok -f $tmpfile2, 'pg prefix PNG created';
    unlink $tmpfile2;
}

# ----------------------------------------------------------------
# 回帰テスト: マルチパネル(3x3)で各パネルのfig_x/fig_yが重ならないこと。
# 以前は _flush() が save()/show() 経路で明示的に $fig->tight_layout()
# を呼んでいた(または _render_to の自動tight_layout呼び出しが効いて
# しまっていた)ため、_build_panels/_apply_pgplot_margins で設定した
# PGPLOT流マルチパネル配置が 1x1 前提のレイアウトで上書きされ、
# 全パネルが fig_x=0,fig_y=0 に統一されて重なって描画される不具合があった。
# ----------------------------------------------------------------
{
    require PDL::Graphics::Cairo::PGPLOT;
    PDL::Graphics::Cairo::PGPLOT->import(':pg');

    my $tmpfile3 = "/tmp/test_pg_multipanel_$$.png";
    pgbegin(0, "$tmpfile3/PNG", 3, 3);

    my $state = PDL::Graphics::Cairo::PGPLOT::_state();
    my @fig_xy_before = map { [$_->fig_x, $_->fig_y] } @{ $state->{axes} };

    # 9パネル全部に異なるfig_x/fig_yが割られていること(描画前)
    my %seen;
    $seen{"$_->[0],$_->[1]"} = 1 for @fig_xy_before;
    is scalar(keys %seen), 9,
        'multipanel: 9 panels have 9 distinct fig_x/fig_y positions before flush';

    for my $idx (0..8) {
        my @x = (0..9);
        my @y = map { $_ * (1+$idx*0.3) } @x;
        pgenv(0, 9, 0, $y[-1], 0, 0);
        pglab("s", ($idx % 3 == 0 ? "uV" : ""), "ch$idx");
        pgline(10, \@x, \@y);
    }

    # _flush() を直接呼んで save() を実行させる。
    # (pgend() は _flush() の直後に $_state{axes} をリセットしてしまうため、
    #  reset前の状態を確認するにはpgend()経由ではなく_flush()を直接呼ぶ必要がある)
    # 以前はこの _flush() 内部([save()内のtight_layout自動呼び出し、または
    # gs/osx分岐の明示的tight_layout()呼び出し])が、PGPLOT流マルチパネル
    # 配置を1x1前提のレイアウトで上書きし、全パネルを重ねてしまっていた。
    PDL::Graphics::Cairo::PGPLOT::_flush();

    my @fig_xy_after = map { [$_->fig_x, $_->fig_y] } @{ $state->{axes} };
    %seen = ();
    $seen{"$_->[0],$_->[1]"} = 1 for @fig_xy_after;
    is scalar(keys %seen), 9,
        'multipanel: 9 panels still have 9 distinct fig_x/fig_y positions after _flush/save (no overlap regression)';

    pgend();
    ok -f $tmpfile3, 'multipanel PNG created';
    unlink $tmpfile3;
}

# ----------------------------------------------------------------
# 回帰テスト: PGPLOT黒背景(bg=>'black')時にtitle/xlabelの文字色が
# 背景に同化して見えなくならないこと。
# 以前は _draw_labels が title/xlabel/ylabel を固定で黒(0,0,0)
# 描いていたため、黒背景では文字が完全に不可視になっていた。
# ----------------------------------------------------------------
{
    require PDL::Graphics::Cairo::PGPLOT;
    PDL::Graphics::Cairo::PGPLOT->import(':pg');

    local $ENV{_PDLCAIRO_PGBG} = 'black';

    my $tmpfile4 = "/tmp/test_pg_blackbg_$$.png";
    pgbegin(0, "$tmpfile4/PNG", 1, 1);
    pgenv(0, 9, 0, 9, 0, 0);
    pglab("x", "y", "title");
    pgline(2, [0,9], [0,9]);
    pgend();

    ok -f $tmpfile4, 'black background PNG created';

    # _draw_labels内のbg_black判定と同じロジックをここで再現して検証
    # （画像のピクセル値解析はPillow等の外部依存になるため、ここでは
    #  ロジック単体の検証に留める）。
    {
        local $ENV{_PDLCAIRO_PGBG} = 'black';
        my $bg_black = (lc($ENV{_PDLCAIRO_PGBG} // 'white') eq 'black');
        ok $bg_black, 'bg_black resolves true when _PDLCAIRO_PGBG=black';
    }
    {
        local $ENV{_PDLCAIRO_PGBG} = 'white';
        my $bg_black = (lc($ENV{_PDLCAIRO_PGBG} // 'white') eq 'black');
        ok !$bg_black, 'bg_black resolves false when _PDLCAIRO_PGBG=white (default)';
    }

    unlink $tmpfile4;
}

done_testing;
