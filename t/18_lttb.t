#!/usr/bin/env perl
# t/18_lttb.t — PDL::Graphics::Cairo::LTTB 単体テスト
# giza-server 不要。pure PDL で実行できる。
#
# 使い方:
#   perl -Ilib t/18_lttb.t
#   prove -Ilib t/18_lttb.t

use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo::LTTB qw(lttb lttb_step);

# ── 1. パススルー: データ点数 ≤ n_out ──────────────────────────────
{
    my $x = sequence(10);
    my $y = $x ** 2;
    my ($xd, $yd) = lttb($x, $y, 20);   # n_out > n_data
    is($xd->nelem, 10, 'passthrough: nelem unchanged');
    ok(all($xd == $x),  'passthrough: x values unchanged');
}

# ── 2. 出力点数が n_out 以下 ────────────────────────────────────────
{
    my $x = sequence(1000);
    my $y = sin($x / 50);
    my ($xd, $yd) = lttb($x, $y, 100);
    is($xd->nelem, 100, 'output nelem == n_out (1000->100)');
    ok($xd->nelem == $yd->nelem, 'x and y have same nelem');
}

# ── 3. 端点が保持される ─────────────────────────────────────────────
{
    my $x = sequence(500);
    my $y = grandom(500);
    my ($xd, $yd) = lttb($x, $y, 50);
    is($xd->at(0),  $x->at(0),    'first point x preserved');
    is($xd->at(-1), $x->at(-1),   'last point x preserved');
    ok(abs($yd->at(0)  - $y->at(0))  < 1e-6, 'first point y preserved');
    ok(abs($yd->at(-1) - $y->at(-1)) < 1e-6, 'last point y preserved');
}

# ── 4. スパイク保持 ─────────────────────────────────────────────────
# フラットなデータの中央にスパイクを入れ、LTTBがそれを保持するか確認
{
    my $n  = 2000;
    my $x  = sequence($n);
    my $y  = zeroes($n);
    my $si = int($n / 2);   # スパイク位置
    $y->set($si, 200.0);    # 高さ200のスパイク

    my $n_out = 200;
    my ($xd, $yd) = lttb($x, $y, $n_out);

    # スパイク時刻が選択点に含まれているか
    my $spike_t = $x->at($si);
    my $found = any($xd == $spike_t)->sclr;
    ok($found, "spike at t=$spike_t preserved by LTTB");

    # スパイク値が保持されているか
    if ($found) {
        my $idx = which($xd == $spike_t)->at(0);
        ok(abs($yd->at($idx) - 200.0) < 1e-3, 'spike amplitude preserved');
    } else {
        fail('spike amplitude: spike not found');
    }
}

# ── 5. lttb_step ────────────────────────────────────────────────────
{
    is(lttb_step(10000, 1000), 5,  'lttb_step(10000, 1000) = 5');
    is(lttb_step(100,   1000), 1,  'lttb_step(100, 1000) = 1 (min)');
    is(lttb_step(0,     1000), 1,  'lttb_step(0, 1000) = 1 (min)');
}

# ── 6. EEG典型サイズのベンチマーク ──────────────────────────────────
# 2000samples × 20ch を 400点にLTTBする時間を計測（タイムアウト目安）
{
    require Time::HiRes;
    my $n_ch = 20; my $ns = 2000; my $n_out = 400;
    my $x    = sequence($ns);

    my $t0 = Time::HiRes::time();
    for my $i (0 .. $n_ch - 1) {
        my $y = grandom($ns) * 50 + sin($x / 30) * 20;
        my ($xd, $yd) = lttb($x, $y, $n_out);
    }
    my $elapsed = Time::HiRes::time() - $t0;

    ok($elapsed < 1.0,
        sprintf("20ch LTTB %d->%d took %.3fs (< 1.0s)", $ns, $n_out, $elapsed));
    diag(sprintf("  LTTB timing: %.1f ms / channel, %.1f ms total",
        $elapsed/$n_ch*1000, $elapsed*1000));
}

done_testing();
