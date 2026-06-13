package PDL::Graphics::Cairo::LTTB;
# Largest-Triangle-Three-Buckets (LTTB) ダウンサンプリング
#
# 参考: Sveinn Steinarsson, "Downsampling Time Series for Visual Representation"
#       https://skemman.is/bitstream/1946/15343/3/SS_MSthesis.pdf
#
# 用途: EEG/波形の間引き描画。単純な1/N間引きと違い、
#       局所的なmin/maxを保持するため、スパイク（EOGアーティファクト等）が
#       潰れない。
#
# 使い方:
#   use PDL::Graphics::Cairo::LTTB qw(lttb);
#   my ($xs, $ys) = lttb($x_pdl, $y_pdl, $n_out);
#   # $xs, $ys は PDL piddle（$n_out 点以下）

use strict;
use warnings;
use PDL;
use Exporter 'import';
our @EXPORT_OK = qw(lttb lttb_step);

# lttb($x, $y, $n_out) — LTTB アルゴリズムで $n_out 点にダウンサンプル
# $x, $y : 1D PDL piddle（同サイズ、単調増加 x を推奨）
# $n_out  : 出力点数（>= 3 を推奨）
# 返値    : ($x_down, $y_down) PDL piddle
sub lttb {
    my ($x, $y, $n_out) = @_;
    my $n = $x->nelem;

    # 点数が少ない、または十分少なければそのまま返す
    return ($x, $y) if $n <= $n_out || $n_out < 3;

    # LTTB の実装
    # 結果インデックスリスト（最初と最後は固定）
    my @selected = (0);

    my $bucket_size = ($n - 2) / ($n_out - 2);

    my $a = 0;   # 直前の選択点インデックス

    for my $i (0 .. $n_out - 3) {
        # 現在バケット: インデックス範囲 [cur_start, cur_end]
        my $cur_start = int($i       * $bucket_size) + 1;
        my $cur_end   = int(($i + 1) * $bucket_size);      # 次バケット開始の1つ前
        $cur_start = $n - 2 if $cur_start > $n - 2;
        $cur_end   = $n - 2 if $cur_end   > $n - 2;
        $cur_end   = $cur_start if $cur_end < $cur_start;

        # 次バケット: 平均を三角形頂点Cとして使う
        my $next_start = $cur_end + 1;
        my $next_end   = int(($i + 2) * $bucket_size);
        $next_start = $n - 1 if $next_start > $n - 1;
        $next_end   = $n - 1 if $next_end   > $n - 1;
        $next_end   = $next_start if $next_end < $next_start;

        # 次バケットの平均点（三角形の頂点C）
        my $nx = $x->slice("$next_start:$next_end")->avg;
        my $ny = $y->slice("$next_start:$next_end")->avg;

        # 現在バケット内で三角形面積が最大の点を選ぶ
        my $ax = $x->at($a);
        my $ay = $y->at($a);

        my $cur_x = $x->slice("$cur_start:$cur_end");
        my $cur_y = $y->slice("$cur_start:$cur_end");

        # 三角形面積 = |（B-A）×（C-A）| / 2
        # = |(bx-ax)(cy-ay) - (cx-ax)(by-ay)| / 2
        # 最大化には /2 不要
        my $area = (($cur_x - $ax) * ($ny - $ay) - ($nx - $ax) * ($cur_y - $ay))->abs;

        my $max_idx = $area->maximum_ind->sclr;
        push @selected, $cur_start + $max_idx;
        $a = $cur_start + $max_idx;
    }

    push @selected, $n - 1;   # 最後の点

    my $idx = pdl(long, \@selected);
    return ($x->index($idx), $y->index($idx));
}

# lttb_step($n_data, $n_pixels) — 表示ピクセル幅から適切な間引きステップを返す
# 単純間引き（LTTB 不要な場合）用のヘルパー。
# $n_data   : データ点数
# $n_pixels : 表示幅（ピクセル）
# 返値      : ステップ数 (>= 1)
# 考え方: 1ピクセルあたり最大2点（Nyquistの類似）で可視情報を保持。
sub lttb_step {
    my ($n_data, $n_pixels) = @_;
    my $step = int($n_data / ($n_pixels * 2));
    return $step < 1 ? 1 : $step;
}

1;
__END__

=head1 NAME

PDL::Graphics::Cairo::LTTB - Largest-Triangle-Three-Buckets ダウンサンプリング

=head1 SYNOPSIS

  use PDL::Graphics::Cairo::LTTB qw(lttb lttb_step);

  # EEG チャンネルを表示幅 800px に合わせて間引く
  my $step = lttb_step($n_samples, 800);   # 単純間引きステップ
  # または LTTB（スパイク保持）:
  my ($x_d, $y_d) = lttb($t, $eeg_ch, 1600);   # 800px × 2

  # render コールバック内で:
  if ($opts->{is_save}) {
      $ax->line($t, $eeg_ch, ...);          # 保存時はフル解像度
  } else {
      my ($td, $yd) = lttb($t, $eeg_ch, $w * 2);
      $ax->line($td, $yd, ...);             # 表示時は LTTB 間引き
  }

=head1 DESCRIPTION

単純な 1/N 間引きと違い、三角形面積が最大になる点を選ぶため、
EOG アーティファクトのような急峻なスパイクも視覚的に保持される。

アルゴリズム: Sveinn Steinarsson (2013)。計算量 O(n_out)。

=head1 FUNCTIONS

=head2 lttb($x, $y, $n_out)

LTTBで $n_out 点に間引く。$x, $y は 1D PDL。
返値は ($x_downsampled, $y_downsampled)。

=head2 lttb_step($n_data, $n_pixels)

表示幅から単純間引きステップを返す（LTTB を使わない場合のヘルパー）。

=cut
