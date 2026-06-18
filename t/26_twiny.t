use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

# ------------------------------------------------------------------
# twiny(): 新しいAxesオブジェクトが返り、_is_twin/_twin_of/_twin_type
# が正しく設定されること
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    my $ax2 = $ax->twiny;

    ok defined($ax2), 'twiny() returns a new Axes object';
    isnt $ax2, $ax, 'twiny() returns a different object from parent';
    ok $ax2->{_is_twin}, 'twiny() result has _is_twin flag set';
    is $ax2->{_twin_of}, $ax, 'twiny() result _twin_of points to parent';
    is $ax2->{_twin_type}, 'y', "twiny() result _twin_type is 'y'";
}

# ------------------------------------------------------------------
# twiny(): draw()後にY軸(ymin/ymax)が親と一致し、X軸(xmin/xmax)は
# 独立していること(matplotlibのtwiny定義: Y軸共有、X軸独立)
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    $ax->line(pdl(0,10), pdl(0,100));      # 親: x=ms(0-10), y=amplitude(0-100)
    my $ax2 = $ax->twiny;
    $ax2->line(pdl(0,10000), pdl(0,100));  # 子: x=Hz(0-10000)相当, y=同じ範囲

    $fig->tight_layout;
    $fig->to_png;  # draw()をトリガー

    is $ax2->ymin, $ax->ymin, 'twiny: child ymin matches parent ymin after draw';
    is $ax2->ymax, $ax->ymax, 'twiny: child ymax matches parent ymax after draw';
    isnt $ax2->xmin, $ax->xmin, 'twiny: child xmin is independent from parent';
}

# ------------------------------------------------------------------
# twiny(): マージンが親と揃うこと(上下に2軸分のスペースが必要なため、
# margin_left/right/bottomは共通、margin_topのみ親基準で揃う)
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    $ax->line(pdl(0,10), pdl(0,100));
    $ax->xlabel('time (ms)'); $ax->ylabel('amplitude');
    my $ax2 = $ax->twiny;
    $ax2->line(pdl(0,10000), pdl(0,100));
    $ax2->xlabel('frequency (Hz)');

    $fig->tight_layout;
    $fig->to_png;

    is $ax2->margin_left,   $ax->margin_left,   'twiny: margin_left matches parent';
    is $ax2->margin_right,  $ax->margin_right,  'twiny: margin_right matches parent';
    is $ax2->margin_bottom, $ax->margin_bottom, 'twiny: margin_bottom matches parent';
    is $ax2->margin_top,    $ax->margin_top,    'twiny: margin_top matches parent';
}

# ------------------------------------------------------------------
# twiny(): PNG描画がクラッシュしないこと(基本ケース)
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    $ax->line(pdl(0,1,2,3,4,5), pdl(0,1,4,9,16,25), color=>'steelblue', label=>'ms axis');
    $ax->xlabel('time (ms)'); $ax->ylabel('amplitude');
    $ax->set_title('twiny basic test');

    my $ax2 = $ax->twiny;
    $ax2->xlabel('frequency (Hz)');
    # 上軸は周波数スケール(例: 0-500Hzにスケールした見た目上のライン)。
    # twinyはY軸共有なので、y値は親と同じスケール感のデータを渡す。
    $ax2->line(pdl(0,100,200,300,400,500), pdl(0,1,4,9,16,25), color=>'tomato', label=>'Hz axis');

    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'twiny basic case renders without crashing' or diag "error: $@";
}

# ------------------------------------------------------------------
# twiny() + twinx() の併用(matplotlib流: axes.twinx().twiny()に相当する
# ような4軸構成)でもクラッシュしないこと
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    $ax->line(pdl(0,10), pdl(0,100), color=>'steelblue');
    $ax->xlabel('time (ms)'); $ax->ylabel('left Y');

    my $ax_x = $ax->twinx;  # 右Y軸(X軸共有)
    $ax_x->line(pdl(0,10), pdl(0,1), color=>'tomato');
    $ax_x->ylabel('right Y');

    my $ax_y = $ax->twiny;  # 上X軸(Y軸共有)
    $ax_y->line(pdl(0,1000), pdl(0,100), color=>'forestgreen');
    $ax_y->xlabel('frequency (Hz)');

    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'twinx + twiny combined renders without crashing' or diag "error: $@";
}

done_testing;
