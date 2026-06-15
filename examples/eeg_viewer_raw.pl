#!/usr/bin/env perl
# examples/eeg_viewer_raw.pl — MNE raw.plot() スタイル多チャンネルEEGビューア
#
# レイアウト:
#   上部: 波形 N_ROWS_VIS 行（固定行数、スクロールで全チャンネルを閲覧）
#   下部: ボタン行（固定高さ BTN_H_FRAC）
#
# スライダ（giza-server物理スライダ）:
#   スライダ0（水平）: 廃止（無視）
#   スライダ1（垂直）: チャンネルオフセット（どの行から表示するか）
#
# ボタン行カスタムUI（xlim/ylim=0..1）:
#   [◀] [▶]         : 1ページ時間送り
#   [−][窓幅s][+]   : 表示時間幅±1s
#   位置スライダ     : 時間位置（クリック/ドラッグ）
#   情報行下段       : Gain / LTTB / PICK結果（スライダと重ならず固定位置）

use strict;
use warnings;
use PDL;
use open qw(:std :utf8);   # Wide character warning 抑制
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::Driver::GS;
use PDL::Graphics::Cairo::LTTB qw(lttb lttb_minmax);

# ═══════════════════════════════════════════════════════════════════════
# ★ ユーザー設定
# ═══════════════════════════════════════════════════════════════════════
my $N_ROWS_VIS    = 8;      # ← 一度に表示する波形行数（画面に収まる数）
my $PAGE_SEC_INIT = 10.0;   # ← 初期表示時間幅（秒）

# ═══════════════════════════════════════════════════════════════════════
# ★ 描画解像度スケール（速度と品質のトレードオフ）
#   1.0 = フル解像度（65ms/frame）
#   0.75 = 高速（35ms/frame、推奨）
#   0.5  = 最速（20ms/frame、若干ぼけ）
# ═══════════════════════════════════════════════════════════════════════
$ENV{PDLCAIRO_RENDER_SCALE} //= 0.75;   # ← ここを変更
use constant BTN_PX => 70;  # ボタン行の絶対ピクセル高さ（チャンネル数に依存しない）

# ═══════════════════════════════════════════════════════════════════════
# 1. データ生成 / 読み込み
# ═══════════════════════════════════════════════════════════════════════

my ($eeg, $srate, $n_samples, @CH_NAMES);

if (@ARGV && -f $ARGV[0] && $ARGV[0] =~ /\.eeg$/i) {
    eval { require PDL::EEG };
    die "PDL::EEG が必要です: $@\n" if $@;
    my $reader = PDL::EEG->new(file => $ARGV[0]);
    my $data   = $reader->read(all_blocks => 1);
    $eeg       = $data->{waveform};
    $srate     = $data->{sample_rate};
    $n_samples = $eeg->dim(1);
    @CH_NAMES  = @{ $data->{ch_names} };
    warn sprintf("Loaded: %dch x %d samples @ %d Hz\n",
        scalar(@CH_NAMES), $n_samples, $srate);
} else {
    $srate     = 1000;
    $n_samples = 30 * $srate;
    @CH_NAMES  = qw(
        Fp1 Fp2 F7  F3  Fz  F4  F8
        T3  C3  Cz  C4  T4
        T5  P3  Pz  P4  T6
        O1  O2
        A1  A2
        F9  F10 T9  T10 P9  P10
        Fpz FCz CPz POz Oz
        EKG EMG
    );
    my $N = scalar @CH_NAMES;
    my @channels;
    srand(42);
    for my $i (0 .. $N-1) {
        my $noise = grandom($n_samples) * 15;
        my $alpha = sin(sequence($n_samples) * (2*3.14159*10/$srate) + $i*0.5) * 20;
        my $theta = sin(sequence($n_samples) * (2*3.14159*6 /$srate) + $i*0.3) * 8;
        my $erp   = zeros($n_samples);
        for my $rep (0..5) {
            my $t0r = ($rep * 5 + 1) * $srate;
            my $dt  = (sequence($n_samples) - $t0r) * (1000.0/$srate);
            $erp   += (-25 * exp(-($dt**2)/(2*30**2))
                      + 35  * exp(-(($dt-100)**2)/(2*50**2)))
                      * (($i >= 12 && $i <= 18) ? 1.0 : 0.25);
        }
        my $art = zeros($n_samples);
        if ($i <= 1) {
            for my $t (map { int($_ * $srate) } (3, 8, 15, 22, 27)) {
                my $dt2 = sequence($n_samples) - $t;
                $art += 180 * exp(-($dt2**2)/(2*200**2));
            }
        }
        if ($CH_NAMES[$i] eq 'EKG') {
            my $rr = int($srate * 60.0 / 72);
            for (my $t = 0; $t < $n_samples; $t += $rr) {
                my $dt2 = sequence($n_samples) - $t;
                $art += 300 * exp(-($dt2**2)/(2*5**2));
            }
            $noise *= 0.3;
        }
        push @channels, $noise + $alpha + $theta + $erp + $art;
    }
    $eeg = pdl(\@channels)->xchg(0,1);
    warn sprintf("Demo: %dch x %.0fs @ %dHz\n", $N, $n_samples/$srate, $srate);
}

my $N_CH_ALL = scalar @CH_NAMES;
$N_ROWS_VIS  = $N_CH_ALL if $N_ROWS_VIS > $N_CH_ALL;
my $t_full   = sequence($n_samples) * (1000.0 / $srate);   # ms
my $DATA_MS  = $n_samples * 1000.0 / $srate;

# ═══════════════════════════════════════════════════════════════════════
# 2. 状態管理
# ═══════════════════════════════════════════════════════════════════════
# %state キー:
#   0        : スライダ0（廃止、無視）
#   1        : スライダ1 → チャンネルオフセット (0..1)
#   _pos     : 時間位置 (0..1)
#   _page_ms : 表示時間幅 (ms)
#   _gain    : 振幅ゲイン (μV)

my %state = (
    0        => 0.0,
    1        => 0.0,          # チャンネルオフセット先頭
    _pos     => 0.0,
    _page_ms => $PAGE_SEC_INIT * 1000.0,
    _gain    => 100.0,        # ±100 μV
);

# チャンネルオフセット: スライダ1(0..1) → 先頭チャンネルインデックス
sub ch_offset_from_state {
    my $max = $N_CH_ALL - $N_ROWS_VIS;
    return 0 if $max <= 0;
    my $v = $_[0]{1} // 0.0;
    my $idx = int($v * $max + 0.5);
    $idx = 0    if $idx < 0;
    $idx = $max if $idx > $max;
    return $idx;
}
sub page_ms       { $_[0]{_page_ms} // ($PAGE_SEC_INIT * 1000.0) }
sub gain_from_state { $_[0]{_gain} // 100.0 }
sub tstart_from_state {
    my $max = $DATA_MS - page_ms($_[0]); $max = 0 if $max < 0;
    ($_[0]{_pos} // 0.0) * $max;
}
sub pos_from_tstart {
    my ($t_ms, $page) = @_;
    my $max = $DATA_MS - $page; return 0.0 if $max <= 0;
    my $v = $t_ms / $max;
    $v < 0.0 ? 0.0 : $v > 1.0 ? 1.0 : $v;
}
sub n_out_for_width { int($_[0] * 1) || 400 }  # 1px=1点（2倍は過剰）

# ═══════════════════════════════════════════════════════════════════════
# 3. ボタン行 UI 定数（ボタン行 Axes の xlim=0..1 座標）
# ═══════════════════════════════════════════════════════════════════════

# ページボタン
use constant { PREV_X0=>0.01, PREV_X1=>0.07, NEXT_X0=>0.08, NEXT_X1=>0.14,
               BTN_Y0 =>0.55, BTN_Y1 =>0.95 };

# 窓幅ボックス [−][値][+]
use constant { WND_M_X0=>0.15, WND_M_X1=>0.19,
               WND_V_X0=>0.19, WND_V_X1=>0.28,
               WND_P_X0=>0.28, WND_P_X1=>0.32,
               WND_Y0  =>0.55, WND_Y1  =>0.95 };

# 位置スライダ（時間）
use constant { SLD_X0=>0.33, SLD_X1=>0.99,
               SLD_CY=>0.78, SLD_TH=>0.09, SLD_NW=>0.007 };

# 情報行（スライダ下）
use constant INFO_Y1 => 0.52;   # 情報行1（ch情報・Gain）
use constant INFO_Y2 => 0.12;   # 情報行2（PICK/Cursor）

# ── 描画ヘルパー ──────────────────────────────────────────────────────

sub _draw_button {
    my ($ax, $x0,$x1,$y0,$y1, $label, $active) = @_;
    my $col    = $active ? '#2c3e50' : '#aaaaaa';
    my $border = $active ? '#555577' : '#cccccc';
    $ax->line(pdl($x0,$x1,$x1,$x0,$x0), pdl($y0,$y0,$y1,$y1,$y0),
        color=>$border, lw=>1.2);
    $ax->text(($x0+$x1)/2, ($y0+$y1)/2, $label,
        ha=>'center', va=>'center', fontsize=>10, color=>$col);
}

sub _draw_hslider {
    my ($ax, $pos, $t_start_ms, $page_ms, $data_ms) = @_;
    $ax->fill(pdl(SLD_X0,SLD_X1,SLD_X1,SLD_X0),
              pdl(SLD_CY-SLD_TH, SLD_CY-SLD_TH,
                  SLD_CY+SLD_TH, SLD_CY+SLD_TH),
              color=>'#dddddd');
    $ax->line(pdl(SLD_X0,SLD_X1), pdl(SLD_CY,SLD_CY),
              color=>'#999999', lw=>1.2);
    my $nx = SLD_X0 + $pos * (SLD_X1 - SLD_X0);
    $ax->fill(
        pdl($nx-SLD_NW,$nx+SLD_NW,$nx+SLD_NW,$nx-SLD_NW),
        pdl(SLD_CY-SLD_TH*2.8, SLD_CY-SLD_TH*2.8,
            SLD_CY+SLD_TH*2.8, SLD_CY+SLD_TH*2.8),
        color=>'#2c3e50');
    my $t_end_ms = $t_start_ms + $page_ms;
    my $lbl = sprintf("%.1f\x{2013}%.1fs", $t_start_ms/1000.0, $t_end_ms/1000.0);
    my $lx  = $nx < (SLD_X0+SLD_X1)/2 ? $nx + SLD_NW*4 : $nx - SLD_NW*4;
    my $ha  = $nx < (SLD_X0+SLD_X1)/2 ? 'left' : 'right';
    $ax->text($lx, SLD_CY + SLD_TH*3.0, $lbl,
        ha=>\$ha, va=>'bottom', fontsize=>9, color=>'#2c3e50');
    $ax->text(SLD_X0, SLD_CY - SLD_TH*3.2, "0",
        ha=>'center', va=>'top', fontsize=>8, color=>'#888888');
    \$ax->text(SLD_X1, SLD_CY - SLD_TH*3.2,
        sprintf("%.0fs", $data_ms/1000.0),
        ha=>'center', va=>'top', fontsize=>8, color=>'#888888');
}

sub _sld_x_to_pos {
    my $v = ($_[0] - SLD_X0) / (SLD_X1 - SLD_X0);
    $v < 0.0 ? 0.0 : $v > 1.0 ? 1.0 : $v;
}

# ═══════════════════════════════════════════════════════════════════════
# 4. render — 2 GridSpec 方式でボタン行高さを固定
# ═══════════════════════════════════════════════════════════════════════

my $render = sub {
    my ($state, $w, $h, $opts) = @_;
    $opts //= {};
    my $is_save = $opts->{is_save} // 0;

    my $gain     = gain_from_state($state);
    my $page_ms  = page_ms($state);
    my $t_start  = tstart_from_state($state);
    my $t_end    = $t_start + $page_ms;
    $t_end       = $DATA_MS if $t_end > $DATA_MS;
    my $ch_off   = ch_offset_from_state($state);

    my $idx0 = int($t_start / 1000.0 * $srate);
    my $idx1 = int($t_end   / 1000.0 * $srate) - 1;
    $idx0 = 0              if $idx0 < 0;
    $idx0 = $n_samples - 1 if $idx0 >= $n_samples;
    $idx1 = $n_samples - 1 if $idx1 >= $n_samples;
    $idx1 = $idx0          if $idx1 < $idx0;

    my $t_view  = $t_full->slice("$idx0:$idx1");
    my $ns_view = $t_view->nelem;
    my $n_lttb  = $is_save ? $ns_view : n_out_for_width($w);
    $n_lttb     = $ns_view if $n_lttb >= $ns_view;

    my $fig = figure(width => $w, height => $h);

    # ボタン行を絶対ピクセル高さ BTN_PX で確保
    # height_ratios: 波形行は等分、ボタン行だけ小さい比率に換算
    # 波形エリア高さ = h（全高）、ボタン行比率 = BTN_PX / ((h - BTN_PX) / N_ROWS_VIS)
    my $wave_unit = ($h - BTN_PX) / $N_ROWS_VIS;   # 波形1行の高さ(px)
    my $btn_ratio = BTN_PX / $wave_unit;             # 波形1行=1に対するボタン行比率
    my @ratios = ((1) x $N_ROWS_VIS, $btn_ratio);
    my $gs = $fig->add_gridspec($N_ROWS_VIS + 1, 1,
        height_ratios => \@ratios,
        hspace => 0.0);

    my @axes;
    for my $r (0 .. $N_ROWS_VIS - 1) {
        push @axes, $fig->add_subplot($gs->at($r, 0));
    }
    my $ax_btn = $fig->add_subplot($gs->at($N_ROWS_VIS, 0));

    # ── 波形チャンネル ────────────────────────────────────────────
    for my $row (0 .. $N_ROWS_VIS-1) {
        my $ch_idx = $ch_off + $row;
        last if $ch_idx >= $N_CH_ALL;
        my $ax     = $axes[$row];
        my $y_full = $eeg->slice("($ch_idx),$idx0:$idx1");
        my ($t_plot, $y_plot);
        if ($n_lttb < $ns_view) {
            ($t_plot, $y_plot) = lttb_minmax($t_view, $y_full, $n_lttb);
        } else {
            ($t_plot, $y_plot) = ($t_view, $y_full);
        }
        $ax->line($t_plot, $y_plot, color=>'#1a5276', lw=>0.8);
        $ax->xlim($t_start, $t_end);
        $ax->ylim($gain, -$gain);
        # ytick: 0ライン非表示、±gain目盛りのみ
        $ax->tick_params(axis=>'x', labelbottom=>0, length=>0);
        $ax->tick_params(axis=>'y', labelleft=>0, length=>0);
        # チャンネル名: ylabel位置（枠外左）
        $ax->ylabel($CH_NAMES[$ch_idx]);
    }

    # ── cursor_overlay ───────────────────────────────────────────
    my $pick_info = undef;
    if (defined $state->{_cursor_x}) {
        my $cx     = $state->{_cursor_x};
        my $type   = $state->{_cursor_type} // 'cursor';
        my $color  = ($type eq 'pick') ? '#c0392b' : '#16a085';
        my $ax_idx = $state->{_cursor_ax_idx} // -1;

        if ($ax_idx >= 0 && $ax_idx < $N_ROWS_VIS) {
            my $ch_idx = $ch_off + $ax_idx;
            if ($ch_idx < $N_CH_ALL) {
                my $t_idx  = ($t_view - $cx)->abs->minimum_ind->sclr;
                my $t_snap = $t_view->at($t_idx);
                $axes[$_]->axvline($t_snap, color=>$color, lw=>0.7, ls=>'--')
                    for (0 .. $N_ROWS_VIS-1);
                my $data_v  = $eeg->slice("($ch_idx),$idx0:$idx1")->at($t_idx);
                my $ch_name = $CH_NAMES[$ch_idx];
                if ($type eq 'pick') {
                    $axes[$ax_idx]->scatter(pdl($t_snap), pdl($data_v),
                        color=>'#c0392b', s=>35);
                }
                my $tag = ($type eq 'pick') ? 'PICK' : 'Cursor';
                $pick_info = { tag=>$tag, t=>$t_snap, v=>$data_v,
                               ch=>$ch_name, color=>$color };
            }
        }
    }

    # ── ボタン行 ──────────────────────────────────────────────────
    {
        $ax_btn->xlim(0,1); $ax_btn->ylim(0,1);
        $ax_btn->axis('off');

        # ◀ ▶
        _draw_button($ax_btn, PREV_X0, PREV_X1, BTN_Y0, BTN_Y1,
            "\x{25C0}", $t_start > 0);
        _draw_button($ax_btn, NEXT_X0, NEXT_X1, BTN_Y0, BTN_Y1,
            "\x{25B6}", $t_end < $DATA_MS - 1);

        # 窓幅 [−][値][+]
        _draw_button($ax_btn, WND_M_X0, WND_M_X1, WND_Y0, WND_Y1, "\x{2212}", 1);
        $ax_btn->line(
            pdl(WND_V_X0,WND_V_X1,WND_V_X1,WND_V_X0,WND_V_X0),
            pdl(WND_Y0,WND_Y0,WND_Y1,WND_Y1,WND_Y0),
            color=>'#888888', lw=>1.0);
        $ax_btn->text((WND_V_X0+WND_V_X1)/2, (WND_Y0+WND_Y1)/2,
            sprintf("%.0fs", $page_ms/1000.0),
            ha=>'center', va=>'center', fontsize=>10, color=>'#2c3e50');
        _draw_button($ax_btn, WND_P_X0, WND_P_X1, WND_Y0, WND_Y1, "+", 1);

        # 位置スライダ
        _draw_hslider($ax_btn, $state->{_pos} // 0.0,
                      $t_start, $page_ms, $DATA_MS);

        # 情報行1: ch範囲 | Gain/LTTB （スライダ下段・左右）
        my $ch_max = $N_CH_ALL - $N_ROWS_VIS;
        my $ch_str = $ch_max > 0
            ? sprintf("ch %d\x{2013}%d / %d  |",
                $ch_off+1, $ch_off+$N_ROWS_VIS, $N_CH_ALL)
            : sprintf("%d ch  |", $N_CH_ALL);
        my $lttb_str = ($n_lttb < $ns_view)
            ? sprintf("Gain:\xB1%.0f\xB5V  LTTB:%d\x{2192}%d/ch",
                $gain, $ns_view, $n_lttb)
            : sprintf("Gain:\xB1%.0f\xB5V  Full:%d pts/ch", $gain, $ns_view);
        $ax_btn->text(SLD_X0, INFO_Y1, $ch_str . "  " . $lttb_str,
            ha=>'left', va=>'top', fontsize=>8,
            color=>($n_lttb < $ns_view ? '#27ae60' : '#555555'));

        # 情報行2: PICK/Cursor情報（重ならない下段）
        if (defined $pick_info) {
            $ax_btn->text(SLD_X0, INFO_Y2,
                sprintf("%s  t=%.3f s  v=%.1f \xB5V  ch: %s",
                    $pick_info->{tag}, $pick_info->{t}/1000.0,
                    $pick_info->{v},   $pick_info->{ch}),
                ha=>'left', va=>'top', fontsize=>8,
                color=>$pick_info->{color});
        }
    }

    # マージン手動設定（tight_layoutの自動計算を使わない）
    # ylabel(チャンネル名)あり・xtick非表示に最適化
    my $ml_wave = 52;
    my $mr_wave = 8;
    my $mt_wave = 3;
    my $mb_wave = 3;
    for my $ax (@axes) {
        $ax->margin_left($ml_wave);
        $ax->margin_right($mr_wave);
        $ax->margin_top($mt_wave);
        $ax->margin_bottom($mb_wave);
    }
    # ボタン行: axis('off')なので全マージン最小にしてplot矩形を最大化
    # → image_frac_to_data がボタン行全体でヒットするようになる
    $ax_btn->margin_left(2);
    $ax_btn->margin_right(2);
    $ax_btn->margin_top(2);
    $ax_btn->margin_bottom(2);

    # tight_layoutの自動呼び出しを抑制（_render_to内で再度呼ばれてマージンが上書きされるのを防ぐ）
    $fig->{_tight_done} = 1;

    printf "render %.0fms  (n_lttb=%d ns_view=%d ch=%d w=%d)\n",
        unless $is_save;

    return $fig;
};

# ═══════════════════════════════════════════════════════════════════════
# 5. giza-server 起動
# ═══════════════════════════════════════════════════════════════════════

my $drv = PDL::Graphics::Cairo::Driver::GS->new(
    width  => 1100,
    height => 900,
    title  => 'EEG Raw Viewer',
);

printf "EEG Raw Viewer\n";
printf "  %d ch total, %d ch visible @ %.0fs window\n",
    $N_CH_ALL, $N_ROWS_VIS, $PAGE_SEC_INIT;
printf "  スライダ1(垂直): チャンネルスクロール\n";
printf "  (横スライダは現在未使用: giza-server側でCMD_NEWWIN拡張時に廃止予定)\n";
printf "  [◀][▶]: 時間ページ送り  [−][+]: 窓幅変更\n\n";

$drv->show_interactive(
    init           => \%state,
    render         => $render,
    cursor_overlay => 1,

    on_cursor => sub {
        my ($fx, $fy, $btn) = @_;
        return unless $btn == 1;
        my $ax_idx = $state{_cursor_ax_idx} // -1;
        # ボタン行 = axes インデックス $N_ROWS_VIS
        return unless $ax_idx == $N_ROWS_VIS;
        my $bx = $state{_cursor_x} // -1;
        my $by = $state{_cursor_y} // -1;
        if ($bx >= SLD_X0 - SLD_NW*3 && $bx <= SLD_X1 + SLD_NW*3
            && $by >= SLD_CY - SLD_TH*3.5 && $by <= SLD_CY + SLD_TH*3.5) {
            $state{_pos} = _sld_x_to_pos($bx);
        }
    },

    on_pick => sub {
        my ($fx, $fy, $btn) = @_;
        my $ax_idx = $state{_cursor_ax_idx} // -1;

        if ($ax_idx == $N_ROWS_VIS) {
            # ボタン行
            my $bx = $state{_cursor_x} // -1;
            my $by = $state{_cursor_y} // 0.5;

            # 位置スライダ クリック
            if ($bx >= SLD_X0 && $bx <= SLD_X1
                && $by >= SLD_CY - SLD_TH*3.5
                && $by <= SLD_CY + SLD_TH*3.5) {
                $state{_pos} = _sld_x_to_pos($bx);

            # ◀ Prev
            } elsif ($bx >= PREV_X0 && $bx <= PREV_X1
                     && $by >= BTN_Y0 && $by <= BTN_Y1) {
                my $pg = page_ms(\%state);
                my $t  = tstart_from_state(\%state) - $pg;
                $t = 0.0 if $t < 0.0;
                $state{_pos} = pos_from_tstart($t, $pg);
                printf "  \x{25C0} t=%.1fs\n", $t/1000.0;

            # ▶ Next
            } elsif ($bx >= NEXT_X0 && $bx <= NEXT_X1
                     && $by >= BTN_Y0 && $by <= BTN_Y1) {
                my $pg  = page_ms(\%state);
                my $max = $DATA_MS - $pg; $max = 0 if $max < 0;
                my $t   = tstart_from_state(\%state) + $pg;
                $t = $max if $t > $max;
                $state{_pos} = pos_from_tstart($t, $pg);
                printf "  \x{25B6} t=%.1fs\n", $t/1000.0;

            # − 窓幅縮小
            } elsif ($bx >= WND_M_X0 && $bx <= WND_M_X1
                     && $by >= WND_Y0 && $by <= WND_Y1) {
                my $t0   = tstart_from_state(\%state);
                my $new  = $state{_page_ms} - 1000.0;
                $new     = 1000.0 if $new < 1000.0;
                $state{_page_ms} = $new;
                $state{_pos}     = pos_from_tstart($t0, $new);
                printf "  窓幅: %.0fs\n", $new/1000.0;

            # + 窓幅拡大
            } elsif ($bx >= WND_P_X0 && $bx <= WND_P_X1
                     && $by >= WND_Y0 && $by <= WND_Y1) {
                my $t0   = tstart_from_state(\%state);
                my $new  = $state{_page_ms} + 1000.0;
                $new     = $DATA_MS if $new > $DATA_MS;
                $state{_page_ms} = $new;
                $state{_pos}     = pos_from_tstart($t0, $new);
                printf "  窓幅: %.0fs\n", $new/1000.0;
            }

        } else {
            # 波形行 PICK
            my $ch_idx = ch_offset_from_state(\%state) + $ax_idx;
            my $ch = ($ch_idx >= 0 && $ch_idx < $N_CH_ALL)
                ? $CH_NAMES[$ch_idx] : '?';
            printf "PICK btn=%d ch=%s\n", $btn, $ch;
        }
    },
);
