use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);
use PDL::Graphics::Cairo::Tick qw(nice_date_ticks fmt_date_tick);

# ------------------------------------------------------------------
# nice_date_ticks(): 秒単位の範囲(数十秒)で秒刻みの目盛りが返ること
# ------------------------------------------------------------------
{
    my @ticks = nice_date_ticks(0, 60, 6);
    ok scalar(@ticks) >= 2, 'nice_date_ticks: short range returns multiple ticks';
    ok $ticks[0] >= 0 && $ticks[-1] <= 60, 'nice_date_ticks: ticks within range';
}

# ------------------------------------------------------------------
# nice_date_ticks(): 日単位の範囲で日刻みの目盛りが返ること
# ------------------------------------------------------------------
{
    my $one_day = 86400;
    my @ticks = nice_date_ticks(0, $one_day * 10, 5);
    ok scalar(@ticks) >= 2, 'nice_date_ticks: 10-day range returns multiple ticks';
    # 目盛り間隔が1日の倍数になっているはず
    if (@ticks >= 2) {
        my $step = $ticks[1] - $ticks[0];
        ok $step % 86400 == 0 || $step >= 86400, 'nice_date_ticks: step is day-scale';
    }
}

# ------------------------------------------------------------------
# nice_date_ticks(): 年単位の範囲で年刻みの目盛りが返ること
# (カレンダー境界スナップの確認: 各目盛りが月初0時UTCになっているか)
# ------------------------------------------------------------------
{
    my $ten_years = 86400 * 365 * 10;
    my @ticks = nice_date_ticks(0, $ten_years, 5);
    ok scalar(@ticks) >= 2, 'nice_date_ticks: 10-year range returns multiple ticks';
    for my $t (@ticks) {
        my @gt = gmtime($t);
        is $gt[3], 1, "nice_date_ticks: tick at epoch=$t is day-of-month 1 (calendar snap)";
        is $gt[2], 0, "nice_date_ticks: tick at epoch=$t is hour 0 (calendar snap)";
    }
}

# ------------------------------------------------------------------
# fmt_date_tick(): スケールに応じて適切なフォーマットが選ばれること
# ------------------------------------------------------------------
{
    # 2024-01-15 12:30:45 UTC のエポック秒
    my $epoch = timegm_simple(2024, 1, 15, 12, 30, 45);

    like fmt_date_tick($epoch, 86400*365), qr/^2024$/, 'fmt_date_tick: year-scale shows only year';
    like fmt_date_tick($epoch, 86400*30),  qr/^Jan 2024$/, 'fmt_date_tick: month-scale shows month+year';
    like fmt_date_tick($epoch, 86400),     qr/^Jan 15$/, 'fmt_date_tick: day-scale shows month+day';
    like fmt_date_tick($epoch, 3600),      qr/^12:30$/, 'fmt_date_tick: hour-scale shows HH:MM';
    like fmt_date_tick($epoch, 1),         qr/^12:30:45$/, 'fmt_date_tick: second-scale shows HH:MM:SS';
}

# 簡易timegm(うるう年・月日対応、外部モジュール非依存)
sub timegm_simple {
    my ($y, $mon, $mday, $h, $min, $s) = @_;
    my $days = 0;
    for my $yy (1970 .. $y-1) {
        $days += (($yy % 4 == 0 && ($yy % 100 != 0 || $yy % 400 == 0)) ? 366 : 365);
    }
    my @mdays = (31,28,31,30,31,30,31,31,30,31,30,31);
    $mdays[1] = 29 if ($y % 4 == 0 && ($y % 100 != 0 || $y % 400 == 0));
    for my $mm (0 .. $mon-2) {
        $days += $mdays[$mm];
    }
    $days += $mday - 1;
    return $days*86400 + $h*3600 + $min*60 + $s;
}

# ------------------------------------------------------------------
# plot_date(): UNIX time数値配列を渡した場合、_xaxis_is_dateフラグが
# 立ち、line()と同じキュー形式でデータが積まれること
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my @epochs = (1700000000, 1700003600, 1700007200, 1700010800);
    my @vals   = (1, 2, 1.5, 3);
    $ax->plot_date(\@epochs, \@vals);

    ok $ax->_xaxis_is_date, 'plot_date: _xaxis_is_date flag is set';
    my $cmd = $ax->_queue->[-1];
    is $cmd->{type}, 'line', 'plot_date: queues as line type (reuses line() machinery)';
    is $cmd->{x}->at(0), 1700000000, 'plot_date: first x value preserved as epoch';
    is $cmd->{x}->at(3), 1700010800, 'plot_date: last x value preserved as epoch';
}

# ------------------------------------------------------------------
# plot_date(): PNG描画がクラッシュしないこと
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    my @epochs = map { 1700000000 + $_ * 86400 } 0..9;  # 10日分
    my @vals   = map { sin($_) + 2 } 0..9;
    $ax->plot_date(\@epochs, \@vals, color=>'steelblue');
    $ax->xlabel('Date'); $ax->ylabel('Value');
    $ax->set_title('plot_date: 10-day series');
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'plot_date renders without crashing' or diag "error: $@";
}

# ------------------------------------------------------------------
# plot_date(): DateTimeオブジェクトの配列を渡した場合(DateTimeが
# インストールされていればテスト、なければskip)
# ------------------------------------------------------------------
SKIP: {
    eval { require DateTime };
    skip 'DateTime module not installed', 2 if $@;

    my @dts = map { DateTime->from_epoch(epoch => 1700000000 + $_ * 3600) } 0..5;
    my @vals = (1,2,3,2,1,2);

    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->plot_date(\@dts, \@vals);
    my $cmd = $ax->_queue->[-1];
    is $cmd->{x}->at(0), 1700000000, 'plot_date: DateTime object converted to epoch correctly';

    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'plot_date with DateTime objects renders without crashing' or diag "error: $@";
}

# ------------------------------------------------------------------
# plot_date(): 通常のline()でX軸が数値軸のままであること(後方互換性、
# _xaxis_is_dateフラグが立っていないAxesでは従来通りnice_ticksが使われる)
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->line(pdl(1,2,3), pdl(1,2,3));
    ok !$ax->_xaxis_is_date, 'plain line(): _xaxis_is_date flag is NOT set';
}

done_testing;
