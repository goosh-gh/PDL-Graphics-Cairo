package PDL::Graphics::Cairo::Tick;

# =============================================================
# matplotlib  AutoLocator 
#   nice_ticks($min, $max, $n_target) → @tick_values
# =============================================================

use strict;
use warnings;
use POSIX qw(floor ceil log10 fmod);
use Exporter 'import';
our @EXPORT_OK = qw(nice_ticks nice_range minor_ticks);

sub nice_ticks {
    my ($min, $max, $n) = @_;
    $n //= 6;
    return ($min) if $min == $max;

    my $range  = $max - $min;
    my $rough  = $range / $n;
    my $mag    = 10 ** floor(log10(abs($rough) || 1));
    my $frac   = $rough / $mag;

    # nice 
    my $step;
    if    ($frac <= 1.0) { $step = 1.0  * $mag }
    elsif ($frac <= 2.0) { $step = 2.0  * $mag }
    elsif ($frac <= 2.5) { $step = 2.5  * $mag }
    elsif ($frac <= 5.0) { $step = 5.0  * $mag }
    else                 { $step = 10.0 * $mag }

    # step 
    my $decimals = ($step >= 1) ? 0 : ceil(-log10($step));

    my $start = $step * ceil($min / $step - 1e-10);
    my @ticks;
    my $v = $start;
    while ($v <= $max + $step * 1e-6) {
        #

        my $rounded = ($decimals > 0)
            ? sprintf("%.${decimals}f", $v) + 0
            : int($v + 0.5 * ($v <=> 0));
        push @ticks, $rounded if $rounded >= $min - $step*1e-6
                              && $rounded <= $max + $step*1e-6;
        $v += $step;
        last if @ticks > 20;
    }
    return @ticks;
}

#  nice 
sub nice_range {
    my ($min, $max, $margin_ratio) = @_;
    $margin_ratio //= 0.05;
    my $span = $max - $min || 1;
    return ($min - $span * $margin_ratio,
            $max + $span * $margin_ratio);
}

sub minor_ticks {
    my ($min, $max, $n_minor, @major) = @_;
    $n_minor //= 5;
    return () if @major < 2;
    my $step = $major[1] - $major[0];
    return () if $step <= 0;
    my $minor_step = $step / $n_minor;
    my $first      = $major[0] - $step;
    my @minors;
    my $v   = $first;
    my $eps = $minor_step * 1e-6;
    while ($v <= $max + $eps) {
        if ($v > $min - $eps && $v < $max + $eps) {
            my $is_major = 0;
            for my $m (@major) {
                if (abs($v - $m) < $minor_step * 0.1) { $is_major = 1; last }
            }
            push @minors, $v unless $is_major;
        }
        $v += $minor_step;
        last if @minors > 200;
    }
    return @minors;
}

# =============================================================
# plot_date() 用: 日付軸の目盛り計算とラベルフォーマット
# matplotlib の AutoDateLocator/AutoDateFormatter、gnuplotの
# set xdata time / set format x 相当の軽量版。
# 入力・出力ともUNIX time(エポック秒、UTC)で統一する。
# =============================================================
push @EXPORT_OK, qw(nice_date_ticks fmt_date_tick);

# 1メジャー目盛りあたりの「秒数」から、人間にとって自然な目盛り間隔
# (秒)を選ぶ。gnuplotのtimefmt系・matplotlibのAutoDateLocatorの
# intervald(YEARLY/MONTHLY/DAILY/HOURLY/...)に相当する単純化版。
my @_DATE_STEPS = (
    1, 5, 10, 15, 30,                       # 秒
    60, 300, 600, 900, 1800,                # 分(1,5,10,15,30分)
    3600, 7200, 10800, 21600, 43200,        # 時(1,2,3,6,12時間)
    86400, 86400*2, 86400*7,                # 日(1,2,7日)
    86400*30, 86400*30*3, 86400*30*6,       # 月(1,3,6ヶ月、近似30日)
    86400*365, 86400*365*2, 86400*365*5,    # 年(1,2,5年、近似365日)
    86400*365*10,
);

# nice_date_ticks($min_epoch, $max_epoch, $n) → @tick_epochs
# UNIX time(秒)の範囲[$min_epoch,$max_epoch]を、目標本数$n本程度の
# 目盛りに分割する。月/年単位はカレンダー境界(1日/1月1日)に
# スナップするため、$step以上が「月」相当(86400*28以上)になったら
# localtime/timelocalで月初日に合わせる。
sub nice_date_ticks {
    my ($min_epoch, $max_epoch, $n) = @_;
    $n //= 6;
    return ($min_epoch) if $min_epoch == $max_epoch;

    my $range = $max_epoch - $min_epoch;
    my $rough = $range / $n;

    # @_DATE_STEPS から rough 以上の最小値を選ぶ(なければ最大値)
    my $step = $_DATE_STEPS[-1];
    for my $s (@_DATE_STEPS) {
        if ($s >= $rough) { $step = $s; last; }
    }

    my @ticks;
    if ($step >= 86400*28) {
        # 月単位以上: カレンダー境界(月初日0時UTC)にスナップする。
        # 年月だけ取り出し、月初日のepochに変換してから$stepの月数
        # ぶん進める単純な実装。
        my $months_per_step = int($step/86400/30+0.5);
        $months_per_step ||= 1;
        my @t = gmtime($min_epoch);
        my ($sec,$min,$hour,$mday,$mon,$year) = @t;
        # 月初に正規化
        my $cur_year = $year; my $cur_mon = $mon;
        my $cur = _timegm_month($cur_year, $cur_mon);
        while ($cur <= $max_epoch + 1) {
            push @ticks, $cur if $cur >= $min_epoch - 1;
            $cur_mon += $months_per_step;
            while ($cur_mon >= 12) { $cur_mon -= 12; $cur_year++; }
            $cur = _timegm_month($cur_year, $cur_mon);
            last if @ticks > 50;
        }
    }
    else {
        # 秒/分/時/日単位: 単純な等間隔(原点0からのstep刻み)。
        # gnuplotのtimefmt境界同様、0(1970-01-01 00:00:00 UTC)基準で
        # スナップすることで、毎時0分・毎日0時などに目盛りが揃う。
        my $start = $step * ceil($min_epoch / $step);
        my $v = $start;
        while ($v <= $max_epoch + $step*1e-6) {
            push @ticks, $v if $v >= $min_epoch - $step*1e-6;
            $v += $step;
            last if @ticks > 50;
        }
    }
    return @ticks;
}

# 年month(0-11起算)からUTC月初0時のepoch秒を計算する内部ヘルパー。
# POSIX::timegmはシステム依存の場合があるため、簡単な手計算で求める
# (1970-01-01からの経過日数をグレゴリオ暦で計算)。
sub _timegm_month {
    my ($year, $mon) = @_;  # $year は1900起点(gmtimeの慣習)、$monは0-11
    my $y = $year + 1900;
    my $m = $mon;  # 0-11
    # ツェラー風の日数計算: 1970-01-01からの経過日数
    # 簡易実装: Date::Calcに依存せず、うるう年規則を手計算する。
    my $days = 0;
    if ($y >= 1970) {
        for my $yy (1970 .. $y-1) {
            $days += _is_leap($yy) ? 366 : 365;
        }
    } else {
        for my $yy ($y .. 1969) {
            $days -= _is_leap($yy) ? 366 : 365;
        }
    }
    my @mdays = (31,28,31,30,31,30,31,31,30,31,30,31);
    $mdays[1] = 29 if _is_leap($y);
    for my $mm (0 .. $m-1) {
        $days += $mdays[$mm];
    }
    return $days * 86400;
}

sub _is_leap {
    my ($y) = @_;
    return ($y % 4 == 0 && ($y % 100 != 0 || $y % 400 == 0)) ? 1 : 0;
}

# fmt_date_tick($epoch, $step_seconds) → "formatted string"
# AutoDateFormatterと同じ考え方で、目盛り間隔(秒)に応じて
# 表示するフォーマットを自動選択する(strftime相当、UTC固定)。
sub fmt_date_tick {
    my ($epoch, $step_seconds) = @_;
    my @t = gmtime($epoch);
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) = @t;
    $year += 1900; $mon += 1;

    my @mon_names = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

    if ($step_seconds >= 86400*365) {
        return sprintf("%04d", $year);
    }
    elsif ($step_seconds >= 86400*28) {
        return sprintf("%s %04d", $mon_names[$mon-1], $year);
    }
    elsif ($step_seconds >= 86400) {
        return sprintf("%s %02d", $mon_names[$mon-1], $mday);
    }
    elsif ($step_seconds >= 3600) {
        return sprintf("%02d:%02d", $hour, $min);
    }
    elsif ($step_seconds >= 60) {
        return sprintf("%02d:%02d", $hour, $min);
    }
    else {
        return sprintf("%02d:%02d:%02d", $hour, $min, $sec);
    }
}

1;
