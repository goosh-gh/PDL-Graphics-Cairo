#!/usr/bin/env perl
# =============================================================
# example_show.ja.pl  --  PDL::Graphics::Cairo インタラクティブ表示デモ
#
# PDL-Graphics-Cairo/ ルートから実行:
#   perl -I./lib examples/example_show.pl              # 自動検出
#   perl -I./lib examples/example_show.pl aqua         # macOS Aquaterm
#   perl -I./lib examples/example_show.pl x11          # X11 / XQuartz
#   perl -I./lib examples/example_show.pl wxt          # wxWidgets
#
# PGPLOT 互換レイヤーの /xw デモ:
#   perl -I./lib examples/example_show.pl pgplot_xw
#
# 必要なもの:
#   gnuplot  (OS のパッケージマネージャで別途インストール)
#
#   macOS (MacPorts):
#     sudo port install gnuplot +aquaterm
#     sudo port install aquaterm        # https://aquaterm.sourceforge.net
#
#   Ubuntu/Debian:
#     sudo apt install gnuplot-x11
#
# 動作の仕組み:
#   $fig->show() は一時 PNG を /tmp/pdlcairo_XXXXXX.png に書き出し、
#   gnuplot に渡して表示します。
#   一時ファイルは Perl プロセス終了時に削除されます。
#   show(keep=>1) でデバッグ用に一時ファイルを保持できます。
#
# PGPLOT レイヤーのデバイス文字列:
#   "/xw"   -> gnuplot x11   (X11 / XQuartz)
#   "/AQT"  -> gnuplot aqua  (macOS Aquaterm)
#   "/wxt"  -> gnuplot wxt
#   "/PNG"  -> Cairo PNG ファイル出力（gnuplot 不要）
# =============================================================

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);
use PDL::Graphics::Cairo::PGPLOT qw(:all);

my $PI = 3.14159265358979;

# このサンプルは PGPLOT_BACKGROUND の設定に関係なく白背景を使います。
# 黒背景にしたい場合はこの行を削除してください:
#   PGPLOT_BACKGROUND=black perl -I./lib examples/example_show.pl
$ENV{PGPLOT_BACKGROUND} //= 'white';

# ターミナル選択
# argv[0]: 'aqua' | 'x11' | 'wxt' | 'pgplot_xw' | (空 = 自動検出)
my $term_arg = $ARGV[0] // '';

# =============================================================
# Helper: show() wrapper that passes terminal if specified
# =============================================================
sub show_fig {
    my ($fig) = @_;
    if ($term_arg ne '') {
        # 指定ターミナルを無条件で渡す。
        # フォールバックが発生した場合は Driver::Gnuplot が警告を出す。
        $fig->show(terminal => lc($term_arg));
    } else {
        $fig->show();   # 自動検出
    }
}

# =============================================================
# PGPLOT /xw demo (run with: perl example_show.pl pgplot_xw)
# =============================================================
if ($term_arg eq 'pgplot_xw') {
    print "PGPLOT 互換レイヤー -- /xw (X11) 経由のインタラクティブ表示\n";
    print "gnuplot の x11 ターミナルが必要です。\n\n";

    # Device strings:
    #   "/xw"  or "/XW"   -> gnuplot x11
    #   "/AQT"            -> gnuplot aqua (macOS)
    #   "/wxt"            -> gnuplot wxt
    my $dev = "/xw";   # change to "/AQT" on macOS with Aquaterm

    # --- Demo A: basic line + pgbox ---
    {
        print "デモ A: line + pgbox  デバイス=$dev\n";
        pgbegin(0, $dev, 1, 1);
        pgpap(8, 0.75);

        my $n = 200;
        my @t = map { $_ / 10 } 0..$n-1;
        my @y = map { sin($t[$_]) * exp(-$t[$_]/8) } 0..$n-1;

        pgenv(0, 20, -1.1, 1.1, 0, -2);
        pgsci(3); pgslw(2);
        pgline($n, \@t, \@y);
        pgsci(1); pgslw(1);
        pgbox("ANST", 0.0, 1, "ANTV", 0.5, 2);
        pgmtxt("TR", -1, 0.1, 1.0, "damped sin");
        pgend();
        print "  → ウィンドウが開きました（閉じて続行）\n";
        sleep 1;
    }

    # --- Demo B: 2x3 subpanels ---
    {
        print "デモ B: 2x3 サブパネル デバイス=$dev\n";
        pgbegin(0, $dev, -2, 3);
        pgpap(10, 0.75);

        my $n = 200;
        my @t = map { $_ / 10 } 0..$n-1;
        my @titles = ("sin", "cos", "sin+cos", "damped", "square", "noise");
        my @funcs  = (
            sub { sin($_[0]) },
            sub { cos($_[0]) },
            sub { sin($_[0]) + cos($_[0]) },
            sub { sin($_[0]*3) * exp(-$_[0]/5) },
            sub { sin($_[0]) > 0 ? 1 : -1 },
            sub { sin($_[0]) + (rand()-0.5)*0.3 },
        );

        for my $i (0..$#titles) {
            my @y = map { $funcs[$i]->($t[$_]) } 0..$n-1;
            my $ymax = 2.0;
            pgenv(-100, 899, $ymax, -$ymax, 0, -2);
            pgsci(3); pgslw(1);
            pgline($n, \@t, \@y);
            pgsci(1);
            pgbox("ANST", 0.0, 1, "ANTV", 1.0, 2);
            pgmtxt("TR", -1, 0.1, 1.0, $titles[$i]);
            pgpage();
        }
        pgend();
        print "  → ウィンドウが開きました\n";
    }

    print "\nPGPLOT /xw デモ完了\n";
    exit 0;
}

# =============================================================
# Cairo API interactive demos
# =============================================================

print "PDL::Graphics::Cairo -- インタラクティブ表示デモ\n";
if ($term_arg) {
    print "ターミナル: $term_arg\n\n";
} else {
    print "ターミナル: 自動検出 (aqua -> wxt -> x11 -> qt の順)\n\n";
}

# =============================================================
# Demo 1: Basic line plot (sin / cos)
# =============================================================
{
    print "デモ 1/4: 折れ線グラフ (sin/cos) ...\n";

    my $x = sequence(300) / 15;

    my $fig = figure(width => 800, height => 500);
    my $ax  = $fig->axes();

    $ax->title("sin(x) と cos(x)");
    $ax->xlabel("x");
    $ax->ylabel("y");
    $ax->set_grid(1);
    $ax->line($x, sin($x), color=>'blue',   lw=>2, label=>'sin(x)');
    $ax->line($x, cos($x), color=>'orange', lw=>2, label=>'cos(x)', ls=>'dashed');
    $ax->axhline(0, color=>'gray', lw=>0.8, ls=>'dotted');
    $ax->legend(loc=>'upper right');

    show_fig($fig);
    print "  → ウィンドウが開きました\n";
    sleep 1;
}

# =============================================================
# Demo 2: Scatter plot with colormap
# =============================================================
{
    print "デモ 2/4: 散布図 (カラーマップ: plasma) ...\n";

    my $n  = 400;
    my $sx = grandom($n);
    my $sy = grandom($n);
    my $sc = sqrt($sx*$sx + $sy*$sy);

    my $fig = figure(width => 700, height => 600);
    my $ax  = $fig->axes();
    $ax->margin_right(70);

    $ax->title("散布図（カラーマップ）");
    $ax->scatter($sx, $sy, c=>$sc, cmap=>'plasma', s=>5, alpha=>0.8);
    $ax->axhline(0, color=>'gray', lw=>0.5, ls=>'dotted');
    $ax->axvline(0, color=>'gray', lw=>0.5, ls=>'dotted');
    $ax->set_grid(1);
    $ax->xlabel("x"); $ax->ylabel("y");

    show_fig($fig);
    print "  → ウィンドウが開きました\n";
    sleep 1;
}

# =============================================================
# Demo 3: Dual Y axis (twinx)
# =============================================================
{
    print "デモ 3/4: 二軸グラフ (twinx) ...\n";

    my $h    = sequence(24);
    my $temp = 15 + 10 * sin(($h - 6) * $PI / 12);
    my $hum  = 70 - 20 * sin(($h - 6) * $PI / 12);

    my $fig = figure(width => 860, height => 500);
    my $ax1 = $fig->axes();
    my $ax2 = $ax1->twinx();
    $fig->add_axes($ax2);

    $ax1->title("気温と湿度（twinx）");
    $ax1->xlabel("Hour");
    $ax1->ylabel("Temperature (\x{00B0}C)");
    $ax1->line($h, $temp, color=>'red',  lw=>2.5, label=>"Temp (\x{00B0}C)");
    $ax1->legend(loc=>'upper left');
    $ax1->set_grid(1);
    $ax1->ylim(0, 35);

    $ax2->line($h, $hum, color=>'blue', lw=>2.0, ls=>'dashed',
               label=>"Humidity (%)");
    $ax2->set_right_ylabel("Humidity (%)");
    $ax2->legend(loc=>'upper right');
    $ax2->ylim(40, 100);

    show_fig($fig);
    print "  → ウィンドウが開きました\n";
    sleep 1;
}

# =============================================================
# Demo 4: 2x2 subplot
# =============================================================
{
    print "デモ 4/4: 2×2 サブプロット ...\n";

    my ($fig, @axes) = subplots(2, 2, width=>1000, height=>800);
    my ($ax1, $ax2) = @{ $axes[0] };
    my ($ax3, $ax4) = @{ $axes[1] };
    $fig->set_suptitle("PDL::Graphics::Cairo -- 2×2 サブプロット");

    # [1,1] Damped oscillation
    my $t = sequence(200) / 10;
    my $y = sin($t * 3) * exp(-$t / 5);
    $ax1->title("減衰振動");
    $ax1->line($t, $y, color=>'blue', lw=>2);
    $ax1->axhline(0, color=>'gray', lw=>0.5, ls=>'dotted');
    $ax1->set_grid(1);
    $ax1->xlabel("t"); $ax1->ylabel("y");

    # [1,2] Histogram
    my $data = grandom(600);
    $ax2->title("ヒストグラム N(0,1)");
    $ax2->hist($data, bins=>25, color=>'steelblue', alpha=>0.8);
    $ax2->axvline(0, color=>'red', lw=>1.2, ls=>'dashed');
    $ax2->set_grid(1);
    $ax2->xlabel("value"); $ax2->ylabel("count");

    # [2,1] Bar chart
    my @cats = (1..6);
    my @vals = (3.2, 4.8, 2.1, 5.5, 3.9, 4.4);
    $ax3->title("棒グラフ");
    $ax3->bar(pdl(@cats), pdl(@vals), width=>0.6, color=>'coral', alpha=>0.85);
    $ax3->xticks(\@cats, [qw(Jan Feb Mar Apr May Jun)]);
    $ax3->ylim(0, 7); $ax3->set_grid(1);
    $ax3->xlabel("Month"); $ax3->ylabel("Value");

    # [2,2] Pie chart
    $ax4->title("円グラフ");
    $ax4->pie(pdl(35, 25, 20, 12, 8),
        labels  => [qw(Alpha Beta Gamma Delta Other)],
        autopct => "%.0f%%",
        explode => [0.06, 0, 0, 0, 0],
    );

    show_fig($fig);
    print "  → ウィンドウが開きました\n";
}

print "\nAll demos done.\n";
print "Close the windows or press Ctrl-C to exit.\n";
