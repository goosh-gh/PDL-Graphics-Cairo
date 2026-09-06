#!/usr/bin/env perl
# =============================================================
# demo_grid_scrub_pgplot.pl
#
# PGPLOT 互換レイヤで描いた 5x5 サブプロットを show_grid_scrub に渡し、
#   ・サブプロットをダブルクリック → そのセルを拡大した子窓を新規に開く
#   ・子窓でマウス移動 → 直近データ点の (x,y) を右上に表示
#   ・子窓でドラッグ    → その点にマーカ + 同じ潜時の縦線を親窓の全セルに
# を動かすデモ。giza_server(Cocoa)常駐が前提の実機デモ。
#
#   要ビルド: viewer/gridscrub_cocoa_2d.patch を当てた giza_server
#   実行:     perl -Ilib tools/demo_grid_scrub_pgplot.pl
#
# 仕組みの肝は「PGPLOT で図を描いて、その Figure を返す」ブリッジ。
# PGPLOT レイヤは現在の Figure を内部状態 _state->{fig} に保持しているので、
# 毎フレーム _new_figure() で真っさらにしてから描き直し、それを返す。
# show_grid_scrub は返ってきた Figure に縦線/マーカ/読み取りを後付けする。
# =============================================================
use strict;
use warnings;
use lib 'lib';
use PDL;
use PDL::Graphics::Cairo::PGPLOT qw(:cpg);
use PDL::Graphics::Cairo::Driver::GS;

my $NX = 5;                         # 列
my $NY = 5;                         # 行  → 25 チャンネル
my $W  = 1000;
my $H  = 800;
my $t  = sequence(101);             # 潜時 0..100 ms

# チャンネル idx(0..24) の波形。PGPLOT パネルは列優先(_build_panels 準拠)なので
# axes_list のインデックス = ここの idx と一致する。
sub trace {
    my ($idx) = @_;
    return 30 * sin($t / (2 + $idx + 1)) * exp(-$t/120);
}

my $S = PDL::Graphics::Cairo::PGPLOT::_state();

# --- grid_render: PGPLOT で 5x5 を描いて Figure を返す --------------
# 重要: ダブルクリックのヒット判定は Figure->axes_list のインデックス(=
# PGPLOT の _state->{axes} の格納順 = 列優先)を cell_render に渡す。したがって
# 「チャンネル idx を axes_list[idx] に描く」ことを厳守しないと、親のパネルと
# 拡大窓で別チャンネルが表示されてしまう。
# (注: cpgpanl(ix,iy) は行優先 (iy-1)*nx+(ix-1) で数える一方、_build_panels は
#  列優先で axes を格納するため両者は一致しない。混同を避けるため、ここでは
#  cpgpanl を介さず current_ax を格納順インデックスで直接選ぶ。)
my $grid_render = sub {
    my ($state, $w, $h) = @_;
    $S->{width} = $w; $S->{height} = $h;
    PDL::Graphics::Cairo::PGPLOT::_new_figure();     # 真っさらな Figure
    cpgsubp($NX, $NY);
    for my $idx (0 .. $NX*$NY - 1) {
        $S->{current_ax} = $S->{axes}[$idx];         # axes_list[idx] を選択
        cpgswin(0, 100, -40, 40);
        cpgsci(1);
        cpgline(101, $t, trace($idx));
    }
    # PGPLOT レイヤは fig_x/fig_y でパネル配置を自前計算済み。_render_to の
    # 自動 tight_layout はこれを 1x1 前提で上書きし、全パネルを (0,0) に潰して
    # 重ねてしまう（PGPLOT::_flush が同じ理由で立てているフラグ）。ここで
    # 抑制する。
    $S->{fig}{_tight_done} = 1;
    return $S->{fig};
};

# --- cell_render: ダブルクリックされた idx を単独パネルで拡大 --------
my $cell_render = sub {
    my ($idx, $state, $w, $h) = @_;
    $S->{width} = $w; $S->{height} = $h;
    PDL::Graphics::Cairo::PGPLOT::_new_figure();
    cpgsubp(1, 1);
    cpgswin(0, 100, -40, 40);
    cpgsci(1);
    cpgline(101, $t, trace($idx));
    cpglab("latency (ms)", "amplitude", "ch $idx");
    $S->{fig}{_tight_done} = 1;
    return $S->{fig};
};

# --- 起動 -----------------------------------------------------------
# 親窓サイズを Driver::GS に渡し、show_grid_scrub でマルチ窓セッションへ。
my $drv = PDL::Graphics::Cairo::Driver::GS->new(
    width => $W, height => $H, title => 'grid-scrub (5x5)',
);

$drv->show_grid_scrub(
    grid_render => $grid_render,
    cell_render => $cell_render,
    zoom_size   => [720, 560],
    vline       => { color => [0.85, 0.1, 0.1], lw => 1.2 },
    marker      => { color => [0.85, 0.1, 0.1], ms => 8, marker => 'o' },
    readout     => sub { my ($x,$y)=@_; sprintf("t=%.1f ms\nA=%.2f", $x, $y) },
    cell_title  => sub { "ch $_[0] (zoom)" },
);

print "grid-scrub session ended.\n";
