#!/usr/bin/env perl
# specgram_demo.pl — PDL::Graphics::Cairo specgram デモ
# 実行: perl -I./lib specgram_demo.pl
# 出力: /tmp/specgram_demo_*.png

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots subplot_mosaic);

my $PI = 3.14159265358979;

# ============================================================
# Demo 1: チャープ信号（周波数が時間とともに上昇）
# ============================================================
{
    my $Fs  = 512;
    my $dur = 5;
    my $t   = sequence($Fs * $dur) / $Fs;

    # 線形チャープ: 5Hz → 80Hz
    my $sig = sin(2 * $PI * (5 + 15*$t) * $t);

    my ($fig, $ax) = subplots(1,1, width=>700, height=>400);
    $ax->specgram($sig,
        Fs       => $Fs,
        NFFT     => 128,
        noverlap => 112,
        window   => 'hann',
        cmap     => 'viridis',
        vmin     => -40,
        vmax     => 0,
    );
    $ax->xlabel('Time (s)');
    $ax->ylabel('Frequency (Hz)');
    $ax->title('Chirp: 5 → 80 Hz over 5 seconds');
    $fig->suptitle('Spectrogram Demo', fontsize=>14);
    $fig->tight_layout;
    $fig->save('/tmp/specgram_demo_chirp.png');
    print "Saved: /tmp/specgram_demo_chirp.png\n";
}

# ============================================================
# Demo 2: EEGライク信号（デルタ/アルファ/ベータ帯域バースト）
# ============================================================
{
    my $Fs = 256;
    my $n  = $Fs * 8;
    my $t  = sequence($n) / $Fs;

    # デルタ帯域 (2Hz): 常時
    my $sig = 0.5 * sin(2 * $PI * 2 * $t);

    # アルファ帯域 (10Hz): 2-5秒にバースト
    $sig += sin(2 * $PI * 10 * $t) * exp(-($t - 3.5)**2 / 0.8);

    # ベータ帯域 (20Hz): 5-7秒にバースト
    $sig += 0.6 * sin(2 * $PI * 20 * $t) * exp(-($t - 6)**2 / 0.5);

    # ホワイトノイズ
    $sig += 0.15 * grandom($n);

    my ($fig, @ax) = subplots(2, 1, width=>800, height=>550);
    my ($ax_wave, $ax_spec) = @ax;

    # 波形
    my $t_disp = sequence(int($Fs * 2)) / $Fs;  # 最初の2秒
    $ax_wave->line($t_disp, $sig->slice("0:" . ($t_disp->nelem-1)));
    $ax_wave->xlabel('Time (s)');
    $ax_wave->ylabel('Amplitude');
    $ax_wave->title('EEG-like Signal (first 2s)');

    # スペクトログラム
    $ax_spec->specgram($sig,
        Fs       => $Fs,
        NFFT     => 128,
        noverlap => 120,
        window   => 'hann',
        cmap     => 'hot',
        vmin     => -35,
        vmax     => 5,
    );
    $ax_spec->ylim(0, 35);
    $ax_spec->xlabel('Time (s)');
    $ax_spec->ylabel('Frequency (Hz)');
    $ax_spec->title('Spectrogram (delta/alpha/beta bursts)');

    $fig->suptitle('EEG-like Signal Analysis', fontsize=>14);
    $fig->tight_layout;
    $fig->save('/tmp/specgram_demo_eeg.png');
    print "Saved: /tmp/specgram_demo_eeg.png\n";
}

# ============================================================
# Demo 3: マルチトーン + ListedColormap
# ============================================================
{
    use PDL::Graphics::Cairo qw(ListedColormap);

    my $Fs = 1000;
    my $n  = $Fs * 3;
    my $t  = sequence($n) / $Fs;

    # 3つのトーン + ノイズ
    my $sig = sin(2 * $PI * 50  * $t)
            + sin(2 * $PI * 150 * $t) * ($t > 1 & $t < 2)
            + sin(2 * $PI * 300 * $t) * ($t > 2)
            + 0.2 * grandom($n);

    # カスタムカラーマップ（黒→青→シアン→白）
    my $cmap = ListedColormap([
        '#000000', '#001133', '#002266', '#003399',
        '#0044cc', '#0066ff', '#00aaff', '#00ddff',
        '#aaffff', '#ffffff',
    ]);

    my ($fig, $ax) = subplots(1,1, width=>750, height=>420);
    $ax->specgram($sig,
        Fs       => $Fs,
        NFFT     => 256,
        noverlap => 224,
        window   => 'blackman',
        cmap     => $cmap,
        vmin     => -50,
        vmax     => 0,
    );
    $ax->ylim(0, 400);
    $ax->xlabel('Time (s)');
    $ax->ylabel('Frequency (Hz)');
    $ax->title('Multi-tone: 50Hz → +150Hz (1-2s) → +300Hz (2-3s)');
    $ax->xaxis_formatter(sub { sprintf "%.1fs", $_[0] });
    $ax->yaxis_formatter(sub { sprintf "%dHz", int($_[0]) });
    $fig->tight_layout;
    $fig->save('/tmp/specgram_demo_multitone.png');
    print "Saved: /tmp/specgram_demo_multitone.png\n";
}

print "\nDone. Open with: open /tmp/specgram_demo_*.png\n";
