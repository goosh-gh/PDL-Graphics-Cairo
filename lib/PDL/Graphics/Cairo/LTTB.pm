package PDL::Graphics::Cairo::LTTB;
# Largest-Triangle-Three-Buckets (LTTB) ダウンサンプリング
#
# 参考: Sveinn Steinarsson, "Downsampling Time Series for Visual Representation"
#       https://skemman.is/bitstream/1946/15343/3/SS_MSthesis.pdf
#
# lttb: バケット境界を事前計算し、各バケットの面積計算を PDL でまとめて行う。
#   Perl のループはバケット数(n_out-2)回。
# lttb_minmax: バケットごとに最小・最大の 2 点を選ぶ。Perl のループはバケット数回。
#   バケットは画素の列にそろっておらず、最初・最後の点を持たないので、
#   密な波形では線が細く・薄くなる(帯の中にすき間ができる)。
# m4 / m4_index_px: 画素の列ごとに 最初・最小・最大・最後 の 4 点を選ぶ(M4)。
#   参考: Jugel et al., "M4: A Visualization-Oriented Time Series Data
#         Aggregation", PVLDB 7(10), 2014.
#   太さ 1 px のアンチエイリアスなしの線なら、間引かない描画と同じ画素が塗られる。
#   Axes の line(..., decimate => 'm4') は描画のときに確定した座標変換で列を決める。

use strict;
use warnings;
use PDL;
use Exporter 'import';
our @EXPORT_OK = qw(lttb lttb_minmax lttb_step m4 m4_index_px);

# ── lttb($x, $y, $n_out) ────────────────────────────────────────────
# オリジナルLTTBアルゴリズム（Steinarsson 2013）
# バケット平均計算をPDLで高速化。Perlループはn_out-2回（バケット数）。
sub lttb {
    my ($x, $y, $n_out) = @_;
    my $n = $x->nelem;
    return ($x, $y) if $n <= $n_out || $n_out < 3;

    my $bucket_size = ($n - 2) / ($n_out - 2);

    # バケット境界を事前計算
    my @starts = map { int($_ * $bucket_size) + 1 } (0 .. $n_out-3);
    my @ends   = map { my $e = int(($_+1) * $bucket_size);
                       $e = $n-2 if $e > $n-2; $e } (0 .. $n_out-3);

    # 次バケット平均をまとめて計算（各バケットの平均x,y）
    # バケット i+1 の平均を三角形頂点Cとして使う
    # 最終バケットは点 n-1 のみ
    my @avg_x = map {
        my ($s,$e) = ($starts[$_] // $n-1, $ends[$_] // $n-1);
        $x->slice("$s:$e")->avg
    } (1 .. $n_out-3);
    push @avg_x, $x->at($n-1);

    my @avg_y = map {
        my ($s,$e) = ($starts[$_] // $n-1, $ends[$_] // $n-1);
        $y->slice("$s:$e")->avg
    } (1 .. $n_out-3);
    push @avg_y, $y->at($n-1);

    my @selected = (0);
    my $a = 0;

    for my $i (0 .. $n_out-3) {
        my ($cs, $ce) = ($starts[$i], $ends[$i]);
        my $nx = $avg_x[$i];
        my $ny = $avg_y[$i];
        my $ax = $x->at($a);
        my $ay = $y->at($a);

        my $cur_x = $x->slice("$cs:$ce");
        my $cur_y = $y->slice("$cs:$ce");

        my $area = (($cur_x - $ax) * ($ny - $ay)
                  - ($nx - $ax)    * ($cur_y - $ay))->abs;

        my $max_idx = $area->maximum_ind->sclr;
        $a = $cs + $max_idx;
        push @selected, $a;
    }
    push @selected, $n-1;

    my $idx = pdl(long, \@selected);
    return ($x->index($idx), $y->index($idx));
}

# ── lttb_minmax($x, $y, $n_out) ─────────────────────────────────────
# バケットごとに最小・最大の 2 点を選ぶ(バケット数 = (n_out-2)/2)。
# Perl のループはバケット数回。lttb より速い(10,000 点 → 1,000 点で 3 ms 対 40 ms)。
# スパイクは残るが、バケットが画素の列にそろっておらず最初・最後の点を持たないので、
# 1 列に多くの点が入る波形では、間引かない描画より線が細く・薄くなる。
sub lttb_minmax {
    my ($x, $y, $n_out) = @_;
    my $n = $x->nelem;
    return ($x, $y) if $n <= $n_out || $n_out < 3;

    # n_out を偶数に調整（min+maxの2点/バケット）
    my $n_buckets = int(($n_out - 2) / 2);
    return lttb($x, $y, $n_out) if $n_buckets < 1;

    my $bucket_size = ($n - 2) / $n_buckets;

    my @selected = (0);  # 先頭固定

    for my $i (0 .. $n_buckets-1) {
        my $s = int($i       * $bucket_size) + 1;
        my $e = int(($i + 1) * $bucket_size);
        $s = $n-2 if $s > $n-2;
        $e = $n-2 if $e > $n-2;
        $e = $s   if $e < $s;

        my $seg = $y->slice("$s:$e");
        my $min_i = $seg->minimum_ind->sclr;
        my $max_i = $seg->maximum_ind->sclr;

        # min/maxを時間順に追加（重複回避）
        my ($fi, $si2) = $min_i <= $max_i
            ? ($s+$min_i, $s+$max_i)
            : ($s+$max_i, $s+$min_i);
        push @selected, $fi;
        push @selected, $si2 if $fi != $si2;
    }

    push @selected, $n-1;  # 末尾固定

    my $idx = pdl(long, \@selected);
    return ($x->index($idx), $y->index($idx));
}

# ── lttb_step ───────────────────────────────────────────────────────
sub lttb_step {
    my ($n_data, $n_pixels) = @_;
    my $step = int($n_data / ($n_pixels * 2));
    return $step < 1 ? 1 : $step;
}

# ── m4_index_px($px, $y, $lo, $hi) ──────────────────────────────────
# $px: 各点の画素の x(昇順)。$lo, $hi: 描画領域の左端と右端の画素の x。
# 画素の列 floor($px) ごとに、最初・最小・最大・最後の点の添字を返す(long、昇順、重複なし)。
# 描画領域の外(px < lo、px >= hi)の点は、領域に入る直前の 1 点と、出た直後の 1 点だけ残す
# (外の線分は描画領域で切り取られて見えない)。
# 最小・最大が複数あるときは最初の点。$px が昇順でなければ全点を返す(間引かない)。
sub m4_index_px {
    my ($px, $y, $lo, $hi) = @_;
    my $n = $px->nelem;
    return sequence(long, $n) if $n < 5;
    return sequence(long, $n)
        if ($px->slice('1:-1') < $px->slice('0:-2'))->any;

    # 領域の内側の範囲 [i0, i1] と、その外の直前・直後の点
    my $nin_l = ($px < $lo)->sum->sclr;          # 昇順なので、左の外は先頭から nin_l 点
    my $nin_r = ($px >= $hi)->sum->sclr;         # 右の外は末尾から nin_r 点
    my ($i0, $i1) = ($nin_l, $n - 1 - $nin_r);
    my @edge;
    push @edge, $i0 - 1 if $nin_l > 0;
    push @edge, $i1 + 1 if $nin_r > 0;
    return pdl(long, \@edge) if $i0 > $i1;        # 内側に点が無い

    my $col = $px->slice("$i0:$i1")->floor->long;
    my $v   = $y->slice("$i0:$i1");
    my $sel = _m4_cols($col, $v) + $i0;
    # pdl(long, ()) は空ではなく [0] になるので、付けるときだけ 1 要素の pdl を作る
    $sel = append(pdl(long, [$i0 - 1]), $sel) if $nin_l > 0;
    $sel = append($sel, pdl(long, [$i1 + 1])) if $nin_r > 0;
    return $sel;
}

# 列(昇順の long)ごとに 最初・最小・最大・最後 の添字(0 起点)。
# (列内の最大点数, 列数) の添字の表を作り、列の終わりで頭打ちにして minimum_ind / maximum_ind。
# 表が点の数に比べて大きすぎる(x の間隔がひどく不均一な)ときは、列ごとのループにする。
sub _m4_cols {
    my ($col, $v) = @_;
    my $n   = $col->nelem;
    my $chg = which($col->slice('1:-1') != $col->slice('0:-2')) + 1;
    my $st  = append(pdl(long, 0), $chg);
    my $en  = append($chg - 1, pdl(long, $n - 1));
    my $nb  = $st->nelem;
    my $L   = ($en - $st + 1)->max->sclr;
    my ($imin, $imax);
    if ($L * $nb <= 4 * $n + 65536) {
        my $ix = sequence(long, $L)->dummy(1, $nb) + $st->dummy(0, $L);
        my $ee = $en->dummy(0, $L);
        $ix = ($ix < $ee) * $ix + ($ix >= $ee) * $ee;
        my $vv = $v->index($ix);
        my $r  = sequence(long, $nb);
        $imin = $ix->index2d($vv->minimum_ind, $r);
        $imax = $ix->index2d($vv->maximum_ind, $r);
    } else {
        my (@mn, @mx);
        for my $k (0 .. $nb - 1) {
            my ($s, $e) = ($st->at($k), $en->at($k));
            my $seg = $v->slice("$s:$e");
            push @mn, $s + $seg->minimum_ind->sclr;
            push @mx, $s + $seg->maximum_ind->sclr;
        }
        ($imin, $imax) = (pdl(long, \@mn), pdl(long, \@mx));
    }
    my $sel = cat($st, $imin, $imax, $en)->xchg(0, 1)->qsort->flat;   # 列ごとに昇順
    return $sel->where(append(pdl(long, 1), $sel->slice('1:-1') != $sel->slice('0:-2')));
}

# ── m4($x, $y, x0 => .., x1 => .., left => .., width => ..) ─────────
# データ座標の [x0, x1] が画素の [left, left + width] に描かれるとして M4 で間引き、
# ($x_d, $y_d) を返す。left・width は描画領域の左端と幅(px)。
# 描画のときに列を合わせたいなら、Axes の line(..., decimate => 'm4') を使う。
sub m4 {
    my ($x, $y, %o) = @_;
    for (qw(x0 x1 left width)) { die "m4: $_ is required\n" unless defined $o{$_} }
    die "m4: x1 must differ from x0\n" if $o{x1} == $o{x0};
    my $px  = $o{left} + ($x - $o{x0}) / ($o{x1} - $o{x0}) * $o{width};
    my $idx = m4_index_px($px, $y, $o{left}, $o{left} + $o{width});
    return ($x->index($idx), $y->index($idx));
}

1;
__END__

=encoding utf8

=head1 NAME

PDL::Graphics::Cairo::LTTB - 折れ線の間引き(LTTB・最小最大・M4)

=head1 SYNOPSIS

  use PDL::Graphics::Cairo::LTTB qw(lttb lttb_minmax lttb_step m4 m4_index_px);

  # M4: 描画のときに Axes の座標変換で画素の列を決める(ふつうはこれ)
  $ax->line($t, $eeg_ch, decimate => 'm4');

  # M4: 描画領域の位置を自分で渡す
  my ($x_d, $y_d) = m4($t, $eeg_ch, x0 => 0, x1 => 10, left => 68, width => 1002);

  # バケットごとの最小・最大
  my ($x_d, $y_d) = lttb_minmax($t, $eeg_ch, 1600);

  # LTTB
  my ($x_d, $y_d) = lttb($t, $eeg_ch, 1600);

=head1 DESCRIPTION

=head2 m4 / m4_index_px

画素の列ごとに、最初・最小・最大・最後の 4 点を選ぶ(M4。Jugel et al., PVLDB 2014)。
点の数は元の点数によらず、描画領域の列数の 4 倍以下になる。
太さ 1 px のアンチエイリアスなしの線なら、間引かない描画と同じ画素が塗られる。
アンチエイリアス付きの線では、1 列に多くの点が重なる所の縁が、間引かない描画よりわずかに薄い。

C<m4_index_px($px, $y, $lo, $hi)> は画素の x(昇順)から選んだ添字(long)を返す。
描画領域の外の点は、領域に入る直前と出た直後の 1 点ずつだけ残す。
C<$px> が昇順でなければ、全点の添字を返す(間引かない)。

C<m4($x, $y, x0 =E<gt> .., x1 =E<gt> .., left =E<gt> .., width =E<gt> ..)> は、
データ座標の [x0, x1] が画素の [left, left + width] に描かれるとして間引いた ($x, $y) を返す。

C<$ax-E<gt>line($x, $y, decimate =E<gt> 'm4')> は、描画のときに確定した座標変換で
列を決めるので、tight_layout や窓の大きさの変更の後も列がそろう。
マーカーは間引かない(全点に描く)。

=head2 lttb

Largest-Triangle-Three-Buckets(Steinarsson 2013)。点の数を n_out にする。
画面の画素とは関係なく、形が似るように点を選ぶ近似。Perl のループはバケット数回。

=head2 lttb_minmax

バケットごとに最小・最大の 2 点を選ぶ。Perl のループはバケット数回で、lttb より速い。
バケットが画素の列にそろっておらず最初・最後の点を持たないので、
1 列に多くの点が入る波形では、間引かない描画より線が細く・薄くなる。

=cut
