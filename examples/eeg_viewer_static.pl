#!/usr/bin/env perl
# examples/eeg_viewer_static.pl — EEGビューアの静的PNG出力テスト
#
# giza-server 不要。eeg_viewer.pl の render を直接呼んで PNG を保存する。
#
# 使い方:
#   perl -Ilib examples/eeg_viewer_static.pl
#   open /tmp/eeg_viewer_test_*.png

use strict;
use warnings;
use Time::HiRes qw(time);

# eeg_viewer.pl の render/$n_samples/$srate 等を読み込む
# do FILE でグローバル変数・サブルーチンを取り込む
# ただし show_interactive ブロックを実行させないため、
# __END__ より前で止める工夫が必要 → 別アプローチ:
# render コールバックを直接 eeg_viewer.pl からコピーせず、
# 共有ライブラリ化するまでの暫定として inline で同じデータ生成をする。

use PDL;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::LTTB qw(lttb);

# ── @LAYOUT（eeg_viewer.pl と完全一致を保つこと）──────────────────
my @LAYOUT = (
    { r=>0, c=>1, name=>'Fp1' },
    { r=>0, c=>3, name=>'Fp2' },
    { r=>1, c=>0, name=>'F7'  },
    { r=>1, c=>1, name=>'F3'  },
    { r=>1, c=>2, name=>'Fz'  },
    { r=>1, c=>3, name=>'F4'  },
    { r=>1, c=>4, name=>'F8'  },
    { r=>2, c=>0, name=>'T3'  },
    { r=>2, c=>1, name=>'C3'  },
    { r=>2, c=>2, name=>'Cz'  },
    { r=>2, c=>3, name=>'C4'  },
    { r=>2, c=>4, name=>'T4'  },
    { r=>3, c=>0, name=>'T5'  },
    { r=>3, c=>1, name=>'P3'  },
    { r=>3, c=>2, name=>'Pz'  },
    { r=>3, c=>3, name=>'P4'  },
    { r=>3, c=>4, name=>'T6'  },
    { r=>4, c=>1, name=>'O1'  },
    { r=>4, c=>3, name=>'O2'  },
);
my $N_CH      = scalar @LAYOUT;
my $srate     = 1000;
my $n_samples = 2000;

# ── 合成データ（eeg_viewer.pl と同一 srand/アルゴリズム）──────────
my @channels;
srand(42);
for my $i (0 .. $N_CH - 1) {
    my $noise  = grandom($n_samples) * 15;
    my $alpha  = sin(sequence($n_samples) * (2*3.14159*10/$srate)) * 20;
    my $theta  = sin(sequence($n_samples) * (2*3.14159*6/$srate) + $i*0.3) * 8;
    my $t_ms   = sequence($n_samples) * (1000/$srate);
    my $n200   = -30 * exp(-(($t_ms - 200)**2) / (2 * 30**2));
    my $p300   = 40  * exp(-(($t_ms - 300)**2) / (2 * 50**2));
    my $erp_weight = ($i >= 12 && $i <= 16) ? 1.0 : 0.3;
    my $spike  = zeros($n_samples);
    if ($i <= 1) {
        my $sp       = int($n_samples * 0.6);
        my $sp_range = sequence(60) - 30;
        $spike->slice("${sp}:" . ($sp+29))
            .= 150 * exp(-($sp_range->slice("0:29")**2) / 50);
    }
    push @channels, $noise + $alpha + $theta
                    + ($n200 + $p300) * $erp_weight + $spike;
}
my $eeg    = pdl(\@channels)->xchg(0,1);   # [N_CH, n_samples]
my $t_full = sequence($n_samples) * (1000.0 / $srate);

# ── パラメータ変換（eeg_viewer.pl と同一）─────────────────────────
# スライダ0=水平(時間窓)、スライダ1=垂直(gain)
sub gain_from_state { my $v = $_[0]{1} // 0.5; 50 + $v * 450 }
sub tmax_from_state { my $v = $_[0]{0} // 0.2;
    100 + $v * ($n_samples * 1000.0/$srate - 100) }
sub n_out_for_width { int($_[0] / 5 * 2) || 200 }

# ── render（eeg_viewer.pl の render と完全一致）────────────────────
my $render = sub {
    my ($state, $w, $h, $opts) = @_;
    $opts //= {};
    my $is_save = $opts->{is_save} // 0;

    my $gain    = gain_from_state($state);
    my $tmax_ms = tmax_from_state($state);
    my $t0 = 0.0;
    my $t1 = $tmax_ms;
    my $idx0 = 0;
    my $idx1 = int($tmax_ms / 1000.0 * $srate);
    $idx1 = $n_samples - 1 if $idx1 >= $n_samples;

    my $t_view  = $t_full->slice("$idx0:$idx1");
    my $ns_view = $t_view->nelem;
    my $n_lttb  = $is_save ? $ns_view : n_out_for_width($w);
    $n_lttb = $ns_view if $n_lttb >= $ns_view;

    my $fig  = figure(width => $w, height => $h);
    my @rows = $fig->subplots(5, 5);

    # 全パネル初期化
    for my $r (0..4) {
        for my $c (0..4) {
            $rows[$r][$c]->xlim(0, 1);
            $rows[$r][$c]->ylim(0, 1);
        }
    }

    # ── チャンネル描画 ──
    my $y_half = $gain;
    for my $ch_idx (0 .. $#LAYOUT) {
        my $ch = $LAYOUT[$ch_idx];
        my ($r, $c, $name) = @{$ch}{qw(r c name)};
        my $ax = $rows[$r][$c];

        my $y_full = $eeg->slice("($ch_idx),$idx0:$idx1");
        my ($t_plot, $y_plot);
        if ($n_lttb < $ns_view) {
            ($t_plot, $y_plot) = lttb($t_view, $y_full, $n_lttb);
        } else {
            ($t_plot, $y_plot) = ($t_view, $y_full);
        }

        $ax->line($t_plot, $y_plot, color => '#1a5276', lw => 1.0);
        $ax->xlim($t0, $t1);
        $ax->ylim($y_half, -$y_half);          # 負上
        $ax->axhline(0.0, color => '#aaa', lw => 0.5);

        # チャンネル名: 時刻左端付近、負上の「上端」= -y_half 側（画面上）
        my $label_x = $t0 + ($t1 - $t0) * 0.02;
        my $label_y = -$y_half * 0.72;   # 負値=画面上端、枠から内側
        $ax->text($label_x, $label_y, $name,
            ha => 'left', va => 'bottom', fontsize => 7, color => '#1a3a5c');

        $ax->xlabel('ms') if $r == 4;
    }

    # ── 情報パネル (r=4, c=0) ──
    {
        my $ax = $rows[4][0];
        $ax->xlim(0, 1); $ax->ylim(0, 1);
        $ax->text(0.5, 0.88, "EEG Viewer",
            ha => 'center', va => 'top', fontsize => 9, color => '#1a5276');
        $ax->text(0.05, 0.62, sprintf("Gain: +/-%.0f uV", $gain),
            ha => 'left', va => 'top', fontsize => 8, color => '#2c3e50');
        $ax->text(0.05, 0.44, sprintf("Window: %.0f ms", $tmax_ms),
            ha => 'left', va => 'top', fontsize => 8, color => '#2c3e50');
        my $pts_str = ($n_lttb < $ns_view)
            ? sprintf("LTTB: %d->%d", $ns_view, $n_lttb)
            : sprintf("Full: %d pts", $ns_view);
        $ax->text(0.05, 0.26, $pts_str,
            ha => 'left', va => 'top', fontsize => 7,
            color => ($n_lttb < $ns_view ? '#27ae60' : '#7f8c8d'));
    }

    # ── スケールバー (r=4, c=2): EEGと同じ座標系 ──
    {
        my $ax = $rows[4][4];
        $ax->xlim($t0, $t1);
        $ax->ylim($y_half, -$y_half);   # 負上（他のパネルと同一）

        # 水平バー: 100ms
        my $bx0 = $t0 + ($t1 - $t0) * 0.05;
        my $bx1 = $bx0 + 100.0;
        my $by  = $y_half * 0.50;
        my $bty = $y_half * 0.08;       # ティック高さ
        $ax->line(pdl($bx0, $bx1), pdl($by, $by),
            color => '#2c3e50', lw => 2.0);
        $ax->line(pdl($bx0,$bx0), pdl($by-$bty,$by+$bty),
            color => '#2c3e50', lw => 1.5);
        $ax->line(pdl($bx1,$bx1), pdl($by-$bty,$by+$bty),
            color => '#2c3e50', lw => 1.5);
        $ax->text(($bx0+$bx1)/2, $by - $y_half*0.18,
            "100 ms", ha => 'center', va => 'bottom',
            fontsize => 7, color => '#2c3e50');

        # 垂直バー: gain/2 uV
        my $sv  = $y_half * 0.5;
        my $svx = $t0 + ($t1-$t0) * 0.75;
        my $stx = ($t1-$t0) * 0.05;    # ティック幅
        $ax->line(pdl($svx,$svx), pdl($sv/2, -$sv/2),
            color => '#2c3e50', lw => 2.0);
        $ax->line(pdl($svx-$stx,$svx+$stx), pdl($sv/2,$sv/2),
            color => '#2c3e50', lw => 1.5);
        $ax->line(pdl($svx-$stx,$svx+$stx), pdl(-$sv/2,-$sv/2),
            color => '#2c3e50', lw => 1.5);
        $ax->text($svx + $stx*1.5, 0.0,
            sprintf("%.0f uV", $sv),
            ha => 'left', va => 'center',
            fontsize => 7, color => '#2c3e50');

        # タイトルは枠内の下部（正値=負上で画面下、枠から離す）
        $ax->text($t0 + ($t1-$t0)*0.5, $y_half * 0.75,
            "Scale", ha => 'center', va => 'bottom',
            fontsize => 7, color => '#7f8c8d');
    }

    $fig->tight_layout(pad => 1.01, h_pad => 8, w_pad => 8);
    return $fig;
};

# ── テスト実行 ────────────────────────────────────────────────────────
my @cases = (
    { label => 'default',
      state => { 0 => 0.2, 1 => 0.5 },   # 水平=時間窓, 垂直=gain
      opts  => {}, file => '/tmp/eeg_viewer_test_default.png' },
    { label => 'wide window',
      state => { 0 => 1.0, 1 => 0.0 },
      opts  => {}, file => '/tmp/eeg_viewer_test_wide.png' },
    { label => 'narrow window',
      state => { 0 => 0.0, 1 => 1.0 },
      opts  => {}, file => '/tmp/eeg_viewer_test_narrow.png' },
    { label => 'is_save (full res)',
      state => { 0 => 0.5, 1 => 0.5 },
      opts  => { is_save => 1 }, file => '/tmp/eeg_viewer_test_save.png' },
);

my $W = 1000; my $H = 700;
my $all_ok = 1;
for my $case (@cases) {
    printf "%-25s ... ", $case->{label};
    my $t0  = time();
    my $fig = $render->($case->{state}, $W, $H, $case->{opts});
    my $t1  = time();
    eval { $fig->save($case->{file}) };
    if ($@) { print "FAILED ($@)\n"; $all_ok = 0; next }
    my $sz = -s $case->{file};
    $sz && $sz > 1000
        ? printf "OK  %.2fs  %d KB  -> %s\n", $t1-$t0, int($sz/1024), $case->{file}
        : do { print "FAILED (small file)\n"; $all_ok = 0 };
}
print "\n";
print $all_ok ? "All renders OK.\n" : "Some FAILED.\n";
print "  open /tmp/eeg_viewer_test_*.png\n" if $all_ok;
