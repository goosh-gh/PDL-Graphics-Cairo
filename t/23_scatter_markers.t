use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

# matplotlib風の14種類のマーカー記法。それぞれ単独でscatter()がクラッシュ
# せずに描画できることを確認する回帰テスト。
my @all_markers = qw(o s ^ v < > d + x p h * P X);

# ------------------------------------------------------------------
# 各マーカーがscatter()経由でクラッシュせず描画できること
# ------------------------------------------------------------------
for my $m (@all_markers) {
    my ($fig, $ax) = subplots(1,1, width=>300, height=>300);
    $ax->scatter(sequence(10), sequence(10), marker=>$m);
    eval { $fig->to_png };
    ok !$@, "scatter(marker=>'$m') renders without crashing" or diag "error: $@";
}

# ------------------------------------------------------------------
# 全14種類を1つの図に重ねて描画してもクラッシュしないこと
# (実際のEEGトポマップ/散布図行列での複数マーカー使い分けを想定)
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>500);
    for my $i (0 .. $#all_markers) {
        $ax->scatter(pdl($i), pdl($i), marker=>$all_markers[$i],
            label=>$all_markers[$i]);
    }
    eval { $fig->to_png };
    ok !$@, 'all 14 marker styles together render without crashing'
        or diag "error: $@";
}

# ------------------------------------------------------------------
# 凡例(legend)経由でも新しいマーカー種類が描画できること
# (legend描画は scatter() と同じ Driver::Cairo::marker() を共有するため)
# ------------------------------------------------------------------
for my $m (qw(p h * P X)) {
    my ($fig, $ax) = subplots(1,1, width=>300, height=>300);
    $ax->scatter(sequence(5), sequence(5), marker=>$m, label=>"style $m");
    $ax->legend;
    eval { $fig->to_png };
    ok !$@, "legend with marker=>'$m' renders without crashing" or diag "error: $@";
}

# ------------------------------------------------------------------
# fill=>0(線のみ)の場合もクラッシュしないこと
# 新規追加した塗りつぶし系マーカー(p,h,*,P,X)は内部でfill_preserveを
# 呼ぶ前にfill引数の真偽値チェックをしているため、fill=>0でも
# close_path+strokeのみで完結することを確認する。
# ------------------------------------------------------------------
# ------------------------------------------------------------------
# fill=>0(線のみ)の場合もクラッシュしないこと。新規追加した塗りつぶし系
# マーカー(p,h,*,P,X)は内部でfill_preserveを呼ぶ前にfill引数の真偽値
# チェックをしているため、fill=>0でもclose_path+strokeのみで完結する
# ことを確認する。Driver::Cairoを直接生成して確認する。
# ------------------------------------------------------------------
{
    require PDL::Graphics::Cairo::Driver::Cairo;
    for my $m (qw(p h * P X)) {
        my $driver = PDL::Graphics::Cairo::Driver::Cairo->new(
            width => 200, height => 200, file => '/tmp/_pgc_marker_fill0_test.png',
        );
        eval { $driver->marker(50, 50, 6, $m, 0) };
        ok !$@, "Driver::Cairo::marker('$m', fill=>0) does not crash" or diag "error: $@";
    }
    unlink '/tmp/_pgc_marker_fill0_test.png';
}

done_testing;
