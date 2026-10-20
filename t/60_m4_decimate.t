#!/usr/bin/env perl
# t/60_m4_decimate.t — M4 による折れ線の間引き(PDL::Graphics::Cairo::LTTB の m4_index_px・m4、
# Axes の line(..., decimate => 'm4'))のテスト。
#
# 比べる相手は、M4 の定義(Jugel et al., PVLDB 2014)をそのまま Perl の配列で書いた ref_m4:
#   画素の列 floor(px) ごとに、最初・最小(同値なら最初)・最大(同値なら最初)・最後の点。
#   描画領域 [lo, hi) の外の点は、領域に入る直前の 1 点と、出た直後の 1 点だけ。
# 本体のコード(添字の表・列ごとのループ)は写していない。全要素を比べる。
use strict;
use warnings;
use Test::More;
use POSIX ();
use PDL;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::LTTB qw(m4 m4_index_px);

sub ref_m4 {
    my ($px, $y, $lo, $hi) = @_;       # Perl の配列リファレンス
    my $n = @$px;
    return [0 .. $n - 1] if $n < 5;
    for my $i (1 .. $n - 1) { return [0 .. $n - 1] if $px->[$i] < $px->[$i - 1] }
    my (@inside, $before, $after);
    for my $i (0 .. $n - 1) {
        if    ($px->[$i] < $lo)  { $before = $i }
        elsif ($px->[$i] >= $hi) { $after //= $i }
        else                     { push @inside, $i }
    }
    my @sel;
    push @sel, $before if defined $before;
    my %col;
    my @order;
    for my $i (@inside) {
        my $c = POSIX::floor($px->[$i]);
        push @order, $c unless exists $col{$c};
        push @{ $col{$c} }, $i;
    }
    for my $c (@order) {
        my @g = @{ $col{$c} };
        my ($mn, $mx) = ($g[0], $g[0]);
        for my $i (@g) {
            $mn = $i if $y->[$i] < $y->[$mn];
            $mx = $i if $y->[$i] > $y->[$mx];
        }
        my %k = map { $_ => 1 } ($g[0], $mn, $mx, $g[-1]);
        push @sel, sort { $a <=> $b } keys %k;
    }
    push @sel, $after if defined $after;
    return \@sel;
}

sub same_list {
    my ($got, $want, $name) = @_;
    my @g = $got->list;
    is_deeply(\@g, $want, $name) or diag(sprintf "got %d, want %d", scalar @g, scalar @$want);
}

CORE::srand(60);

# 合成データ: x は昇順(間隔はばらつく)、y はゆらぎ + スパイク
sub make_case {
    my ($n, %o) = @_;
    my (@x, @y);
    my $t = 0;
    for my $i (0 .. $n - 1) {
        $t += $o{dense} && $i > $n / 3 && $i < $n / 2 ? 0.001 : 0.5 + CORE::rand();
        push @x, $t;
        my $v = $o{ties} ? int(CORE::rand(5)) : sin($i / 7) * 30 + (CORE::rand() - 0.5) * 20;
        $v += 200 if $o{spikes} && $i % 997 == 500;
        push @y, $v;
    }
    return (\@x, \@y);
}

# px = left + (x - x0) * sx の写像
sub to_px { my ($x, $left, $x0, $sx) = @_; [ map { $left + ($_ - $x0) * $sx } @$x ] }

# ── 1. 定義との一致(領域の内側だけ、外にはみ出す、ほぼ全部外、同値が多い、x が密な区間) ──
for my $c (
    [ 'inside only',        5000, {spikes => 1}, 0.00, 1.00 ],
    [ 'both sides outside', 5000, {spikes => 1}, 0.30, 0.70 ],
    [ 'left side outside',  3000, {},            0.50, 1.20 ],
    [ 'narrow window',      3000, {},            0.40, 0.41 ],
    [ 'ties',               4000, {ties => 1},   0.00, 1.00 ],
    [ 'dense burst',        6000, {dense => 1},  0.00, 1.00 ],
) {
    my ($name, $n, $o, $f0, $f1) = @$c;
    my ($x, $y) = make_case($n, %$o);
    my ($xmin, $xmax) = ($x->[0], $x->[-1]);
    my ($x0, $x1) = ($xmin + $f0 * ($xmax - $xmin), $xmin + $f1 * ($xmax - $xmin));
    my ($left, $width) = (68.4, 402);
    my $sx = $width / ($x1 - $x0);
    my $px = to_px($x, $left, $x0, $sx);
    my $want = ref_m4($px, $y, $left, $left + $width);
    my $got = m4_index_px(pdl($px), pdl($y), $left, $left + $width);
    same_list($got, $want, "m4_index_px = definition: $name");
    cmp_ok($got->nelem, '<=', 4 * ($width + 2) + 2, "$name: at most 4 per column + 2");

    my ($xd, $yd) = m4(pdl($x), pdl($y), x0 => $x0, x1 => $x1, left => $left, width => $width);
    my $want_x = [ map { $x->[$_] } @$want ];
    ok(($xd->nelem == @$want) && (($xd - pdl($want_x))->abs->max->sclr == 0), "m4() returns the selected points: $name");
}

# ── 2. 否定対照: 列を半画素ずらすと、選ぶ点が定義と一致しない ──
{
    my ($x, $y) = make_case(5000, spikes => 1);
    my $sx = 402 / ($x->[-1] - $x->[0]);
    my $px = to_px($x, 68, $x->[0], $sx);
    my $want = ref_m4($px, $y, 68, 470);
    my $shift = m4_index_px(pdl($px) + 0.5, pdl($y), 68.5, 470.5);
    my @g = $shift->list;
    ok(!(@g == @$want && join(',', @g) eq join(',', @$want)), 'negative control: columns shifted by half a pixel differ');
}

# ── 3. 間引かない場合 ──
{
    my $px = pdl(0, 0.2, 0.1, 0.3, 0.5, 0.9, 1.5);
    same_list(m4_index_px($px, sequence(7), 0, 10), [0 .. 6], 'x not ascending: all points');
    same_list(m4_index_px(pdl(0, 0.5, 1, 1.5), pdl(1, 2, 3, 4), 0, 10), [0 .. 3], 'fewer than 5 points: all points');
    my $empty_in = m4_index_px(sequence(10) + 100, sequence(10), 0, 50);
    same_list($empty_in, [0], 'all points right of the area: only the first one after it');
}

# ── 4. Axes: line(..., decimate => 'm4') は描画のときの座標変換で列を決める ──
{
    my ($x, $y) = make_case(20000, spikes => 1);
    my ($px_x, $py) = (pdl($x), pdl($y));
    my @seen;
    no warnings 'redefine';
    my $orig = \&PDL::Graphics::Cairo::Driver::Cairo::polyline;
    local *PDL::Graphics::Cairo::Driver::Cairo::polyline = sub {
        my ($self, $xs, $ys) = @_;
        push @seen, [$xs->copy, $ys->copy];
        $orig->(@_);
    };
    for my $mode ('none', 'm4') {
        @seen = ();
        my $f = figure(width => 600, height => 300);
        my $ax = $f->axes;
        $ax->line($px_x, $py, lw => 1, color => 'black', ($mode eq 'm4' ? (decimate => 'm4') : ()));
        $ax->xlim($x->[2000], $x->[15000]);
        $ax->ylabel('uV');
        $f->tight_layout;
        my $d = PDL::Graphics::Cairo::Driver::Cairo->new(width => 600, height => 300, file => ':memory:');
        $f->_render_to($d);
        my ($line) = grep { $_->[0]->nelem > 100 } @seen;
        ok($line, "$mode: the line was drawn");
        if ($mode eq 'none') {
            is($line->[0]->nelem, 20000, 'none: all points drawn');
        } else {
            my ($l) = $ax->data_to_pixel(pdl($x->[2000]), pdl(0));
            my ($r) = $ax->data_to_pixel(pdl($x->[15000]), pdl(0));
            ($l, $r) = ($l->sclr, $r->sclr);
            my $pxs = [ ($ax->data_to_pixel($px_x, $py))[0]->list ];
            my $want = ref_m4($pxs, $y, $l, $r);
            my $want_px = pdl([ map { $pxs->[$_] } @$want ]);
            ok($line->[0]->nelem == @$want && ($line->[0] - $want_px)->abs->max->sclr < 1e-9,
               'm4: the drawn points are the definition applied to the final pixel x');
            cmp_ok($line->[0]->nelem, '<', 20000 / 4, 'm4: far fewer points than the data');
        }
    }
}

# ── 5. decimate の値 ──
{
    my $ax = figure(width => 100, height => 100)->axes;
    eval { $ax->line(sequence(5), sequence(5), decimate => 'lttb') };
    like($@, qr/decimate must be 'm4' or 'none'/, "decimate => 'lttb' is refused");
    ok(eval { $ax->line(sequence(5), sequence(5), decimate => 'none'); 1 }, "decimate => 'none' is accepted");
}

done_testing;
