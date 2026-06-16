#!/usr/bin/env perl
# examples/eeg_viewer_raw.pl — MNE raw.plot()-style multi-channel EEG viewer
#
# Layout:
#   Top:    N_ROWS_VIS waveform rows (fixed count; scroll to browse all channels)
#   Bottom: button bar (fixed height BTN_PX), 2-row layout:
#             row 1: [◀][▶] page | [−][window s][+] | [−][±gain µV][+] | [▲][▼] ch | [neg↑] polarity | time label
#             row 2: time-position slider (full width)
#
# giza-server physical sliders: not used (all controls in custom button bar)
#
# Usage:
#   perl eeg_viewer_raw.pl [file.EEG] [--block=N] [--blocks=N,M,...]
#   PDLCAIRO_DEBUG=1   — enable debug output
#   PDLCAIRO_RENDER_SCALE=0.75  — render resolution (default 0.75)

use strict;
use warnings;
use PDL;
use utf8;
use open qw(:std :utf8);
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::Driver::GS;
use PDL::Graphics::Cairo::LTTB qw(lttb lttb_minmax);

my $DEBUG = $ENV{PDLCAIRO_DEBUG} ? 1 : 0;

# ═══════════════════════════════════════════════════════════════════════
# User settings
# ═══════════════════════════════════════════════════════════════════════
my $N_ROWS_VIS    = 8;      # number of waveform rows visible at once
my $PAGE_SEC_INIT = 10.0;   # initial time window (seconds)

# Render resolution (speed vs. quality trade-off):
#   1.0  = full resolution (~65 ms/frame)
#   0.75 = fast (~35 ms/frame, recommended)
#   0.5  = fastest (~20 ms/frame, slightly blurry)
$ENV{PDLCAIRO_RENDER_SCALE} //= 0.75;
use constant BTN_PX => 90;  # button bar height in pixels (2-row layout)

# ═══════════════════════════════════════════════════════════════════════
# 1. Data loading / generation
# ═══════════════════════════════════════════════════════════════════════

my ($eeg, $srate, $n_samples, @CH_NAMES);

if (@ARGV && -f $ARGV[0] && $ARGV[0] =~ /\.eeg$/i) {
    eval { require PDL::EEG::IO::NihonKohden };
    die "PDL::EEG::IO::NihonKohden is required: $@\n" if $@;
    PDL::EEG::IO::NihonKohden->import('read_nk');

    # Parse optional arguments: --block=N or --blocks=N,M,...
    my $eeg_file = shift @ARGV;
    my @block_list;
    for my $arg (@ARGV) {
        if ($arg =~ /^--block=(\d+)$/) {
            @block_list = (int($1));
        } elsif ($arg =~ /^--blocks=([\d,]+)$/) {
            @block_list = map { int($_) } split /,/, $1;
        }
    }

    # Read block 0 first to get n_blocks
    my $rec0     = read_nk($eeg_file, block => 0);
    my $n_blocks = $rec0->{n_blocks} // 1;

    # Determine which blocks to load
    @block_list = (0 .. $n_blocks - 1) unless @block_list;  # default: all blocks
    @block_list = grep { $_ < $n_blocks } @block_list;      # range check
    die "Specified block(s) out of range (n_blocks=$n_blocks)\n" unless @block_list;

    warn sprintf("  block%s: [%s] / %d total\n",
        @block_list == 1 ? '' : 's',
        join(', ', @block_list), $n_blocks);

    # Load and concatenate blocks
    my @blocks;
    for my $b (@block_list) {
        my $rec = ($b == 0) ? $rec0 : read_nk($eeg_file, block => $b);
        push @blocks, $rec->{data};
    }
    $eeg      = @blocks == 1 ? $blocks[0] : PDL::glue(1, @blocks);
    $srate    = $rec0->{fs};
    @CH_NAMES = @{ $rec0->{labels} };

    # Remove PAD channels
    @CH_NAMES = grep { $_ ne 'PAD' } @CH_NAMES;
    my $n_ch_valid = scalar @CH_NAMES;
    $eeg = $eeg->slice("0:@{[$n_ch_valid-1]},:");

    $n_samples = $eeg->dim(1);
    warn sprintf("Loaded: %dch x %d samples @ %d Hz (%.1f s)\n",
        $n_ch_valid, $n_samples, $srate, $n_samples/$srate);
} else {
    # Demo mode: synthetic 34-channel x 30 s data
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
my $t_full   = sequence($n_samples) * (1000.0 / $srate);  # time axis in ms
my $DATA_MS  = $n_samples * 1000.0 / $srate;

# ═══════════════════════════════════════════════════════════════════════
# 2. State management
# ═══════════════════════════════════════════════════════════════════════
# %state keys:
#   _pos     : time position (0..1, fraction of scrollable range)
#   _page_ms : visible time window width (ms)
#   _gain    : amplitude scale (µV half-range)
#   _ch_off  : first visible channel index
#   _neg_up  : 1 = negative-up (EEG convention), 0 = positive-up

my %state = (
    _pos     => 0.0,
    _page_ms => $PAGE_SEC_INIT * 1000.0,
    _gain    => 100.0,   # ±100 µV
    _ch_off  => 0,
    _neg_up  => 1,       # EEG convention: negative-up by default
);

# Gain steps (quasi-logarithmic)
my @GAIN_STEPS = (10, 20, 50, 100, 150, 200, 300, 500);

sub gain_step_down {
    my $g = $_[0];
    for my $s (reverse @GAIN_STEPS) { return $s if $s < $g }
    return $GAIN_STEPS[0];   # clamp to minimum
}
sub gain_step_up {
    my $g = $_[0];
    for my $s (@GAIN_STEPS) { return $s if $s > $g }
    return $GAIN_STEPS[-1];  # clamp to maximum
}

sub page_ms         { $_[0]{_page_ms} // ($PAGE_SEC_INIT * 1000.0) }
sub gain_from_state { $_[0]{_gain}    // 100.0 }
sub ch_off_from_state {
    my $idx = $_[0]{_ch_off} // 0;
    my $max = $N_CH_ALL - $N_ROWS_VIS;
    $max = 0 if $max < 0;
    $idx = 0    if $idx < 0;
    $idx = $max if $idx > $max;
    return $idx;
}
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
sub n_out_for_width { int($_[0] * 1) || 400 }

# ═══════════════════════════════════════════════════════════════════════
# 3. Button bar UI constants (button-bar Axes coordinates: xlim=0..1)
# ═══════════════════════════════════════════════════════════════════════
#
# 2-row layout (ylim = -0.1 .. 1.0):
#   top row (buttons): y = 0.54 .. 0.95
#   bottom row (slider): y = 0.05 .. 0.48
#
# Top row:
#   [◀][▶] | [−][window s][+] | [−][±gain µV][+] | [▲][▼] | [neg↑] | time label
#   0.01    0.15               0.33               0.52     0.64     0.75..0.99
#
# Bottom row:
#   ──────────────── time-position slider (full width) ────────────────
#   0.01                                                            0.99

# Top row shared Y
use constant { TOP_Y0 => 0.54, TOP_Y1 => 0.95 };

# Page buttons [◀] [▶]
use constant { PREV_X0=>0.01, PREV_X1=>0.07, NEXT_X0=>0.08, NEXT_X1=>0.14,
               BTN_Y0 => TOP_Y0, BTN_Y1 => TOP_Y1 };

# Time-window box [−][value s][+]
use constant { WND_M_X0=>0.15, WND_M_X1=>0.19,
               WND_V_X0=>0.19, WND_V_X1=>0.28,
               WND_P_X0=>0.28, WND_P_X1=>0.32,
               WND_Y0  => TOP_Y0, WND_Y1 => TOP_Y1 };

# Gain box [−][±value µV][+]
use constant { GAN_M_X0=>0.33, GAN_M_X1=>0.37,
               GAN_V_X0=>0.37, GAN_V_X1=>0.47,
               GAN_P_X0=>0.47, GAN_P_X1=>0.51,
               GAN_Y0  => TOP_Y0, GAN_Y1 => TOP_Y1 };

# Channel scroll buttons [▲] [▼]
use constant { CHU_X0=>0.52, CHU_X1=>0.57,
               CHD_X0=>0.58, CHD_X1=>0.63,
               CHB_Y0 => TOP_Y0, CHB_Y1 => TOP_Y1 };

# Polarity toggle button [neg↑] / [pos↑]
use constant { POL_X0=>0.64, POL_X1=>0.74,
               POL_Y0 => TOP_Y0, POL_Y1 => TOP_Y1 };

# Time-position slider (bottom row, full width)
use constant { SLD_X0=>0.01, SLD_X1=>0.99,
               SLD_CY=>0.25, SLD_TH=>0.10, SLD_NW=>0.005 };

# Info rows (DEBUG only)
use constant INFO_Y1 => 0.50;   # between top and bottom rows
use constant INFO_Y2 => 0.05;   # bottom of bar

# ── Drawing helpers ───────────────────────────────────────────────────

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
    # End labels (ha=right on right end prevents overflow)
    $ax->text(SLD_X0, SLD_CY - SLD_TH*3.2, "0",
        ha=>'left',  va=>'top', fontsize=>8, color=>'#888888');
    $ax->text(SLD_X1, SLD_CY - SLD_TH*3.2,
        sprintf("%.0fs", $data_ms/1000.0),
        ha=>'right', va=>'top', fontsize=>8, color=>'#888888');
}

sub _sld_x_to_pos {
    my $v = ($_[0] - SLD_X0) / (SLD_X1 - SLD_X0);
    $v < 0.0 ? 0.0 : $v > 1.0 ? 1.0 : $v;
}

# ═══════════════════════════════════════════════════════════════════════
# 4. render callback
# ═══════════════════════════════════════════════════════════════════════

my $render = sub {
    my ($state, $w, $h, $opts) = @_;
    $opts //= {};
    my $is_save = $opts->{is_save} // 0;

    my $gain    = gain_from_state($state);
    my $page_ms = page_ms($state);
    my $t_start = tstart_from_state($state);
    my $t_end   = $t_start + $page_ms;
    $t_end      = $DATA_MS if $t_end > $DATA_MS;
    my $ch_off  = ch_off_from_state($state);

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

    # Reserve button bar at fixed pixel height BTN_PX
    my $wave_unit = ($h - BTN_PX) / $N_ROWS_VIS;
    my $btn_ratio = BTN_PX / $wave_unit;
    my @ratios = ((1) x $N_ROWS_VIS, $btn_ratio);
    my $gs = $fig->add_gridspec($N_ROWS_VIS + 1, 1,
        height_ratios => \@ratios,
        hspace => 0.0);

    my @axes;
    for my $r (0 .. $N_ROWS_VIS - 1) {
        push @axes, $fig->add_subplot($gs->at($r, 0));
    }
    my $ax_btn = $fig->add_subplot($gs->at($N_ROWS_VIS, 0));

    # ── Waveform channels ─────────────────────────────────────────────
    # Channel labels: horizontal ylabel (ylabel_rotation=0) outside left edge
    my $ml_wave = 48;
    my $mr_wave = 8;

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
        # _neg_up=1: ylim(+gain, -gain) → negative-up (EEG convention)
        # _neg_up=0: ylim(-gain, +gain) → positive-up
        my $neg_up = $state->{_neg_up} // 1;
        $ax->ylim($neg_up ? ($gain, -$gain) : (-$gain, $gain));
        $ax->tick_params(axis=>'x', labelbottom=>0, length=>0);
        $ax->tick_params(axis=>'y', labelleft=>0,   length=>0);
        $ax->ylabel($CH_NAMES[$ch_idx]);
        $ax->ylabel_rotation(0);
    }

    # ── Cursor / pick overlay ─────────────────────────────────────────
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

    # ── Button bar ───────────────────────────────────────────────────
    {
        $ax_btn->xlim(0,1); $ax_btn->ylim(-0.1, 1.0);
        $ax_btn->axis('off');

        # Page buttons [◀] [▶]
        _draw_button($ax_btn, PREV_X0, PREV_X1, BTN_Y0, BTN_Y1,
            "\x{25C0}", $t_start > 0);
        _draw_button($ax_btn, NEXT_X0, NEXT_X1, BTN_Y0, BTN_Y1,
            "\x{25B6}", $t_end < $DATA_MS - 1);

        # Time-window [−][value s][+]
        _draw_button($ax_btn, WND_M_X0, WND_M_X1, WND_Y0, WND_Y1, "\x{2212}", 1);
        $ax_btn->line(
            pdl(WND_V_X0,WND_V_X1,WND_V_X1,WND_V_X0,WND_V_X0),
            pdl(WND_Y0,WND_Y0,WND_Y1,WND_Y1,WND_Y0),
            color=>'#888888', lw=>1.0);
        $ax_btn->text((WND_V_X0+WND_V_X1)/2, (WND_Y0+WND_Y1)/2,
            sprintf("%.0fs", $page_ms/1000.0),
            ha=>'center', va=>'center', fontsize=>10, color=>'#2c3e50');
        _draw_button($ax_btn, WND_P_X0, WND_P_X1, WND_Y0, WND_Y1, "+", 1);

        # Gain [−][±value µV][+]
        _draw_button($ax_btn, GAN_M_X0, GAN_M_X1, GAN_Y0, GAN_Y1, "\x{2212}", 1);
        $ax_btn->line(
            pdl(GAN_V_X0,GAN_V_X1,GAN_V_X1,GAN_V_X0,GAN_V_X0),
            pdl(GAN_Y0,GAN_Y0,GAN_Y1,GAN_Y1,GAN_Y0),
            color=>'#888888', lw=>1.0);
        $ax_btn->text((GAN_V_X0+GAN_V_X1)/2, (GAN_Y0+GAN_Y1)/2,
            sprintf("\xB1%d\xB5V", $gain),
            ha=>'center', va=>'center', fontsize=>10, color=>'#8e44ad');
        _draw_button($ax_btn, GAN_P_X0, GAN_P_X1, GAN_Y0, GAN_Y1, "+", 1);

        # Channel scroll [▲] [▼]
        my $ch_max = $N_CH_ALL - $N_ROWS_VIS;
        _draw_button($ax_btn, CHU_X0, CHU_X1, CHB_Y0, CHB_Y1,
            "\x{25B2}", $ch_max > 0 && $ch_off > 0);
        _draw_button($ax_btn, CHD_X0, CHD_X1, CHB_Y0, CHB_Y1,
            "\x{25BC}", $ch_max > 0 && $ch_off < $ch_max);

        # Polarity toggle: label shows current state
        {
            my $neg_up  = $state->{_neg_up} // 1;
            my $pol_lbl = $neg_up ? "neg\x{2191}" : "pos\x{2191}";
            my $pol_col = $neg_up ? '#1a5276' : '#7b241c';  # blue=neg↑, red=pos↑
            $ax_btn->line(
                pdl(POL_X0, POL_X1, POL_X1, POL_X0, POL_X0),
                pdl(POL_Y0, POL_Y0, POL_Y1, POL_Y1, POL_Y0),
                color => $pol_col, lw => 1.5);
            $ax_btn->text((POL_X0+POL_X1)/2, (POL_Y0+POL_Y1)/2, $pol_lbl,
                ha=>'center', va=>'center', fontsize=>9, color=>$pol_col);
        }

        # Current time range: fixed at top-right (independent of slider position)
        {
            my $t_end_ms = $t_start + $page_ms;
            my $time_lbl = sprintf("%.1f\x{2013}%.1fs",
                $t_start/1000.0, $t_end_ms/1000.0);
            $ax_btn->text(0.99, (TOP_Y0+TOP_Y1)/2, $time_lbl,
                ha=>'right', va=>'center', fontsize=>10, color=>'#2c3e50');
        }

        # Time-position slider (bottom row, full width)
        _draw_hslider($ax_btn, $state->{_pos} // 0.0,
                      $t_start, $page_ms, $DATA_MS);

        # Debug info: ch range | LTTB (shown only when PDLCAIRO_DEBUG=1)
        if ($DEBUG) {
            my $ch_str = $ch_max > 0
                ? sprintf("ch %d\x{2013}%d / %d  |",
                    $ch_off+1, $ch_off+$N_ROWS_VIS, $N_CH_ALL)
                : sprintf("%d ch  |", $N_CH_ALL);
            my $lttb_str = ($n_lttb < $ns_view)
                ? sprintf("  LTTB:%d\x{2192}%d/ch", $ns_view, $n_lttb)
                : sprintf("  Full:%d pts/ch", $ns_view);
            $ax_btn->text(0.75, INFO_Y1, $ch_str . $lttb_str,
                ha=>'left', va=>'bottom', fontsize=>8,
                color=>($n_lttb < $ns_view ? '#27ae60' : '#555555'));
        }

        # PICK/Cursor info: always shown at bottom-right of slider row
        if (defined $pick_info) {
            $ax_btn->text(SLD_X1, INFO_Y2,
                sprintf("%s  t=%.3f s  v=%.1f \xB5V  ch: %s",
                    $pick_info->{tag}, $pick_info->{t}/1000.0,
                    $pick_info->{v},   $pick_info->{ch}),
                ha=>'right', va=>'top', fontsize=>8,
                color=>$pick_info->{color});
        }
    }

    # Margins: horizontal ylabel (rotation=0) fits in 48 px left margin
    my $mt_wave = 2;
    my $mb_wave = 2;
    for my $ax (@axes) {
        $ax->margin_left($ml_wave);
        $ax->margin_right($mr_wave);
        $ax->margin_top($mt_wave);
        $ax->margin_bottom($mb_wave);
    }
    $ax_btn->margin_left(2);
    $ax_btn->margin_right(2);
    $ax_btn->margin_top(2);
    $ax_btn->margin_bottom(2);

    $fig->{_tight_done} = 1;

    return $fig;
};

# ═══════════════════════════════════════════════════════════════════════
# 5. Launch giza-server
# ═══════════════════════════════════════════════════════════════════════

my $drv = PDL::Graphics::Cairo::Driver::GS->new(
    width  => 1100,
    height => 900,
    title  => 'EEG Raw Viewer',
);

printf "EEG Raw Viewer\n";
printf "  %d ch total, %d ch visible @ %.0fs window\n",
    $N_CH_ALL, $N_ROWS_VIS, $PAGE_SEC_INIT;
printf "  [\x{25C0}][\x{25B6}]: page back/forward\n";
printf "  [\x{2212}][window][+]: change time window\n";
printf "  [\x{2212}][\xB1gain][+]: change amplitude gain\n";
printf "  [\x{25B2}][\x{25BC}]: scroll channels\n";
printf "  [neg\x{2191}]: toggle polarity (neg-up / pos-up)\n\n";

$drv->show_interactive(
    init           => \%state,
    render         => $render,
    cursor_overlay => 1,

    on_cursor => sub {
        my ($fx, $fy, $btn) = @_;
        return unless $btn == 1;
        my $ax_idx = $state{_cursor_ax_idx} // -1;
        return unless $ax_idx == $N_ROWS_VIS;
        my $bx = $state{_cursor_x} // -1;
        my $by = $state{_cursor_y} // -1;
        # Drag on time-position slider
        if ($bx >= SLD_X0 - SLD_NW*3 && $bx <= SLD_X1 + SLD_NW*3
            && $by >= SLD_CY - SLD_TH*3.5 && $by <= SLD_CY + SLD_TH*3.5) {
            $state{_pos} = _sld_x_to_pos($bx);
        }
    },

    on_pick => sub {
        my ($fx, $fy, $btn) = @_;
        my $ax_idx = $state{_cursor_ax_idx} // -1;

        if ($ax_idx == $N_ROWS_VIS) {
            # Click in button bar
            my $bx = $state{_cursor_x} // -1;
            my $by = $state{_cursor_y} // 0.5;

            # Time-position slider click
            if ($bx >= SLD_X0 && $bx <= SLD_X1
                && $by >= SLD_CY - SLD_TH*3.5
                && $by <= SLD_CY + SLD_TH*3.5) {
                $state{_pos} = _sld_x_to_pos($bx);

            # [◀] Previous page
            } elsif ($bx >= PREV_X0 && $bx <= PREV_X1
                     && $by >= BTN_Y0 && $by <= BTN_Y1) {
                my $pg = page_ms(\%state);
                my $t  = tstart_from_state(\%state) - $pg;
                $t = 0.0 if $t < 0.0;
                $state{_pos} = pos_from_tstart($t, $pg);
                printf "  \x{25C0} t=%.1fs\n", $t/1000.0 if $DEBUG;

            # [▶] Next page
            } elsif ($bx >= NEXT_X0 && $bx <= NEXT_X1
                     && $by >= BTN_Y0 && $by <= BTN_Y1) {
                my $pg  = page_ms(\%state);
                my $max = $DATA_MS - $pg; $max = 0 if $max < 0;
                my $t   = tstart_from_state(\%state) + $pg;
                $t = $max if $t > $max;
                $state{_pos} = pos_from_tstart($t, $pg);
                printf "  \x{25B6} t=%.1fs\n", $t/1000.0 if $DEBUG;

            # [−] Narrow time window
            } elsif ($bx >= WND_M_X0 && $bx <= WND_M_X1
                     && $by >= WND_Y0 && $by <= WND_Y1) {
                my $t0  = tstart_from_state(\%state);
                my $new = $state{_page_ms} - 1000.0;
                $new    = 1000.0 if $new < 1000.0;
                $state{_page_ms} = $new;
                $state{_pos}     = pos_from_tstart($t0, $new);
                printf "  window: %.0fs\n", $new/1000.0 if $DEBUG;

            # [+] Widen time window
            } elsif ($bx >= WND_P_X0 && $bx <= WND_P_X1
                     && $by >= WND_Y0 && $by <= WND_Y1) {
                my $t0  = tstart_from_state(\%state);
                my $new = $state{_page_ms} + 1000.0;
                $new    = $DATA_MS if $new > $DATA_MS;
                $state{_page_ms} = $new;
                $state{_pos}     = pos_from_tstart($t0, $new);
                printf "  window: %.0fs\n", $new/1000.0 if $DEBUG;

            # [−] Decrease gain (zoom in)
            } elsif ($bx >= GAN_M_X0 && $bx <= GAN_M_X1
                     && $by >= GAN_Y0 && $by <= GAN_Y1) {
                my $new = gain_step_down($state{_gain});
                $state{_gain} = $new;
                printf "  gain: \xB1%d\xB5V\n", $new if $DEBUG;

            # [+] Increase gain (zoom out)
            } elsif ($bx >= GAN_P_X0 && $bx <= GAN_P_X1
                     && $by >= GAN_Y0 && $by <= GAN_Y1) {
                my $new = gain_step_up($state{_gain});
                $state{_gain} = $new;
                printf "  gain: \xB1%d\xB5V\n", $new if $DEBUG;

            # [▲] Scroll channels up
            } elsif ($bx >= CHU_X0 && $bx <= CHU_X1
                     && $by >= CHB_Y0 && $by <= CHB_Y1) {
                my $new = ($state{_ch_off} // 0) - 1;
                $new = 0 if $new < 0;
                $state{_ch_off} = $new;
                printf "  ch offset: %d\n", $new if $DEBUG;

            # [▼] Scroll channels down
            } elsif ($bx >= CHD_X0 && $bx <= CHD_X1
                     && $by >= CHB_Y0 && $by <= CHB_Y1) {
                my $max = $N_CH_ALL - $N_ROWS_VIS;
                $max    = 0 if $max < 0;
                my $new = ($state{_ch_off} // 0) + 1;
                $new    = $max if $new > $max;
                $state{_ch_off} = $new;
                printf "  ch offset: %d\n", $new if $DEBUG;

            # Polarity toggle
            } elsif ($bx >= POL_X0 && $bx <= POL_X1
                     && $by >= POL_Y0 && $by <= POL_Y1) {
                $state{_neg_up} = ($state{_neg_up} // 1) ? 0 : 1;
                printf "  polarity: %s\n",
                    $state{_neg_up} ? 'neg-up' : 'pos-up' if $DEBUG;
            }

        } else {
            # Click on waveform row: PICK
            my $ch_idx = ch_off_from_state(\%state) + $ax_idx;
            my $ch = ($ch_idx >= 0 && $ch_idx < $N_CH_ALL)
                ? $CH_NAMES[$ch_idx] : '?';
            printf "PICK btn=%d ch=%s\n", $btn, $ch if $DEBUG;
        }
    },
);
