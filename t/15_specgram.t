use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

# ----------------------------------------------------------------
# 1. specgram queues a command
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>300);
    my $sig = sin(2 * 3.14159 * 10 * sequence(512) / 256);
    $ax->specgram($sig, Fs=>256, NFFT=>64, noverlap=>32);
    is $ax->_queue->[-1]{type}, 'specgram', 'specgram queued';
}

# ----------------------------------------------------------------
# 2. specgram spec matrix dimensions
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>300);
    my $sig = sin(2 * 3.14159 * 10 * sequence(512) / 256);
    $ax->specgram($sig, Fs=>256, NFFT=>64, noverlap=>32, sides=>'onesided');
    my $cmd = $ax->_queue->[-1];
    my $spec = $cmd->{spec};
    # onesided: nfreqs = NFFT/2 + 1 = 33
    is $spec->dim(0), 33, 'onesided nfreqs = NFFT/2+1';
    # nframes = (512-64)/32 + 1 = 15
    is $spec->dim(1), 15, 'nframes correct';
}

# ----------------------------------------------------------------
# 3. specgram times array length matches nframes
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>300);
    my $sig = ones(512);
    $ax->specgram($sig, Fs=>256, NFFT=>64, noverlap=>32);
    my $cmd = $ax->_queue->[-1];
    is scalar(@{ $cmd->{times} }), $cmd->{spec}->dim(1), 'times length matches nframes';
}

# ----------------------------------------------------------------
# 4. specgram freqs array length matches nfreqs
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>300);
    my $sig = ones(512);
    $ax->specgram($sig, Fs=>256, NFFT=>64, noverlap=>32);
    my $cmd = $ax->_queue->[-1];
    is scalar(@{ $cmd->{freqs} }), $cmd->{spec}->dim(0), 'freqs length matches nfreqs';
}

# ----------------------------------------------------------------
# 5. specgram Fs affects time axis
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>300);
    my $sig = ones(512);
    $ax->specgram($sig, Fs=>1000, NFFT=>64, noverlap=>32);
    my $cmd = $ax->_queue->[-1];
    my $last_t = $cmd->{times}[-1];
    ok $last_t < 1.0, "Fs=1000: last time < 1s (got $last_t)";
}

# ----------------------------------------------------------------
# 6. specgram sets colorbar
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>300);
    my $sig = sin(sequence(256));
    $ax->specgram($sig, Fs=>256, NFFT=>64);
    ok defined($ax->_colorbar), 'specgram sets colorbar';
}

# ----------------------------------------------------------------
# 7. specgram chains
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>300);
    my $sig = ones(256);
    is $ax->specgram($sig, Fs=>256, NFFT=>64), $ax, 'specgram chains';
}

# ----------------------------------------------------------------
# 8. twosided specgram has NFFT freqs
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>300);
    my $sig = ones(512);
    $ax->specgram($sig, Fs=>256, NFFT=>64, noverlap=>32, sides=>'twosided');
    my $cmd = $ax->_queue->[-1];
    is $cmd->{spec}->dim(0), 64, 'twosided: nfreqs = NFFT';
}

# ----------------------------------------------------------------
# 9. PNG smoke: sine wave spectrogram
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>600, height=>400);
    my $Fs  = 256;
    my $dur = 4;   # seconds
    my $t   = sequence($Fs * $dur) / $Fs;
    # Chirp: frequency sweeps 10..50 Hz
    my $sig = sin(2 * 3.14159265 * (10 + 10*$t) * $t);

    $ax->specgram($sig, Fs=>$Fs, NFFT=>64, noverlap=>48, cmap=>'viridis');
    $ax->xlabel('Time (s)');
    $ax->ylabel('Frequency (Hz)');
    $ax->title('Chirp Spectrogram');
    $fig->tight_layout;

    my $tmp = "/tmp/specgram_chirp_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "specgram chirp smoke: no die ($@)";
    ok -f $tmp && -s $tmp > 1000, 'PNG has content';
    unlink $tmp;
}

# ----------------------------------------------------------------
# 10. PNG smoke: multi-tone signal
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>600, height=>400);
    my $Fs  = 512;
    my $n   = $Fs * 3;
    my $t   = sequence($n) / $Fs;
    my $sig = sin(2 * 3.14159265 * 20 * $t)
            + 0.5 * sin(2 * 3.14159265 * 80 * $t)
            + 0.3 * grandom($n);

    $ax->specgram($sig, Fs=>$Fs, NFFT=>128, noverlap=>96,
                  window=>'hann', cmap=>'plasma', scale=>'dB');
    $ax->xlabel('Time (s)'); $ax->ylabel('Freq (Hz)');
    $fig->tight_layout;

    my $tmp = "/tmp/specgram_multitone_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "specgram multi-tone smoke: no die ($@)";
    unlink $tmp;
}

# ----------------------------------------------------------------
# 11. PNG smoke: EEG-like signal with alpha band (8-13 Hz)
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>700, height=>400);
    my $Fs = 256;
    my $n  = $Fs * 5;
    my $t  = sequence($n) / $Fs;
    # Alpha band burst (8-13 Hz) + noise
    my $sig = sin(2 * 3.14159265 * 10 * $t) * exp(-($t-2.5)**2 / 0.5)
            + 0.2 * grandom($n);

    $ax->specgram($sig, Fs=>$Fs, NFFT=>128, noverlap=>112,
                  window=>'hamming', cmap=>'hot',
                  vmin=>-40, vmax=>0);
    $ax->xlabel('Time (s)');
    $ax->ylabel('Frequency (Hz)');
    $ax->title('Alpha Band Burst');
    $ax->ylim(0, 30);   # show only 0-30 Hz
    $fig->tight_layout;

    my $tmp = "/tmp/specgram_eeg_$$.png";
    eval { $fig->save($tmp) };
    ok !$@, "specgram EEG-like smoke: no die ($@)";
    ok -f $tmp && -s $tmp > 1000, 'PNG has content';
    unlink $tmp;
}

done_testing;
