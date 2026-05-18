#!/usr/bin/env perl
# =============================================================
# example_stats.pl  --  PDL::Graphics::Cairo + PDL::Stats demo
#
# Run from PDL-Graphics-Cairo/ root:
#   perl -I./lib examples/example_stats.pl
#
# Requirements:
#   PDL::Stats  (cpan PDL::Stats  or  apt install libpdl-stats-perl)
#
# Output:
#   Interactive display via gnuplot (aqua / x11 / wxt auto-detected)
#   Pass terminal as argument: perl example_stats.pl aqua
# =============================================================

use strict;
use warnings;
use PDL;
use PDL::Stats::Basic;
use PDL::Graphics::Cairo qw(figure subplots);

srand(42);

my $term_arg = $ARGV[0] // '';
sub show_fig {
    my ($fig) = @_;
    $term_arg ? $fig->show(terminal => $term_arg) : $fig->show();
}

# =============================================================
# Common test data: 4 groups x 20 samples each
# =============================================================
my @GROUP_NAMES = qw(Control Drug-A Drug-B Drug-C);
my @GROUP_MEANS = (2.0,  3.5,  1.5,  4.2);
my @GROUP_STDS  = (0.4,  0.6,  0.3,  0.8);

my @groups = map {
    my ($mu, $sigma) = ($GROUP_MEANS[$_], $GROUP_STDS[$_]);
    $mu + grandom(20) * $sigma
} 0..3;

# =============================================================
# stats_01: Error bar comparison (SEM / SD / 95%CI)
# =============================================================
{
    my $fig = figure(width=>800, height=>520);
    my $ax  = $fig->axes();

    $ax->title("Error bar comparison: SEM / SD / 95% CI");
    $ax->xlabel("Group");
    $ax->ylabel("Value");
    $ax->set_grid(1);

    $ax->errorbar_stats(\@groups,
        type => 'sem', color => 'steelblue',
        capsize => 6, marker => 'o', markersize => 6,
        label => "Mean \x{00B1} SEM",
    );
    $ax->errorbar_stats(\@groups,
        type => 'sd', color => 'coral',
        capsize => 6, marker => 's', markersize => 6,
        x => pdl(0.15, 1.15, 2.15, 3.15),
        label => "Mean \x{00B1} SD",
    );
    $ax->errorbar_stats(\@groups,
        type => 'ci95', color => 'seagreen',
        capsize => 6, marker => '^', markersize => 6,
        x => pdl(0.30, 1.30, 2.30, 3.30),
        label => "Mean \x{00B1} 95% CI",
    );

    $ax->xticks([0.15, 1.15, 2.15, 3.15], \@GROUP_NAMES);
    $ax->legend(loc => 'upper left');
    $ax->ylim(0, 6.5);

    show_fig($fig);
    print "stats_01: errorbar\n";
}

# =============================================================
# stats_02: Boxplot (Tukey method)
# =============================================================
{
    my $fig = figure(width=>800, height=>520);
    my $ax  = $fig->axes();

    $ax->title("Boxplot (Tukey method)");
    $ax->xlabel("Group");
    $ax->ylabel("Value");
    $ax->set_grid(1);

    $ax->boxplot(\@groups,
        showmeans => 1, showfliers => 1, showcaps => 1, width => 0.55);
    $ax->xticks([0,1,2,3], \@GROUP_NAMES);
    $ax->ylim(0, 6.5);

    my $ctrl_med = $groups[0]->median;
    $ax->axhline($ctrl_med, color=>'gray', lw=>1.0, ls=>'dashed');
    $ax->text(3.6, $ctrl_med + 0.08, "ctrl median", color=>'gray', fontsize=>9);

    show_fig($fig);
    print "stats_02: boxplot\n";
}

# =============================================================
# stats_03: Violin plot (Gaussian KDE)
# =============================================================
{
    my $fig = figure(width=>800, height=>520);
    my $ax  = $fig->axes();

    $ax->title("Violin plot (Gaussian KDE)");
    $ax->xlabel("Group");
    $ax->ylabel("Value");
    $ax->set_grid(1);

    $ax->violinplot(\@groups,
        showmedians => 1, showmeans => 1, showbox => 1,
        width => 0.7, points => 150);
    $ax->xticks([0,1,2,3], \@GROUP_NAMES);
    $ax->ylim(0, 6.5);

    show_fig($fig);
    print "stats_03: violin\n";
}

# =============================================================
# stats_04: Three plots side by side
# =============================================================
{
    my ($fig, $ax1, $ax2, $ax3) = subplots(1, 3, width=>1350, height=>500);
    $fig->set_suptitle("PDL::Graphics::Cairo + PDL::Stats  --  Statistical Plots");

    for my $ax ($ax1, $ax2, $ax3) {
        $ax->set_grid(1);
        $ax->ylim(0, 6.5);
        $ax->xticks([0,1,2,3], \@GROUP_NAMES);
        $ax->ylabel("Value");
    }

    $ax1->title("errorbar_stats (SEM)");
    $ax1->errorbar_stats(\@groups,
        type=>'sem', color=>'steelblue', capsize=>6, marker=>'o', markersize=>7);

    $ax2->title("boxplot");
    $ax2->boxplot(\@groups, showmeans=>1, width=>0.55);

    $ax3->title("violinplot");
    $ax3->violinplot(\@groups, showmedians=>1, showbox=>1, width=>0.7);

    show_fig($fig);
    print "stats_04: combined\n";
}

# =============================================================
# stats_05: Q-Q plot
# =============================================================
{
    my $fig = figure(width=>800, height=>500);
    my $ax  = $fig->axes();

    $ax->title("Q-Q plot: Normal vs Skewed data");
    $ax->set_grid(1);

    my $normal = grandom(200);
    my $skewed = grandom(200)**2;

    $ax->qqplot($normal,
        color      => 'steelblue',
        label      => 'Normal data',
        line_color => 'steelblue',
    );
    $ax->qqplot($skewed,
        color      => 'coral',
        marker     => 's',
        label      => 'Skewed data',
        line_color => 'coral',
        line_label => 'normal ref',
    );
    $ax->legend(loc => 'upper left');

    show_fig($fig);
    print "stats_05: qqplot\n";
}

# =============================================================
# stats_06: Histogram + KDE overlay
# =============================================================
{
    my ($fig, $ax1, $ax2) = subplots(1, 2, width=>1100, height=>480);
    $fig->set_suptitle("Histogram + KDE overlay");

    my $d1 = grandom(400) * 1.5 + 3;
    $ax1->title("Single distribution");
    $ax1->set_grid(1);
    $ax1->hist_kde($d1,
        bins=>25, color=>'steelblue', kde_color=>'red',
        label=>'data', kde_label=>'KDE');
    $ax1->legend(loc=>'upper right');
    $ax1->xlabel("Value"); $ax1->ylabel("Density");

    my $d2 = pdl(list(grandom(200) + 0), list(grandom(200) + 4));
    $ax2->title("Bimodal distribution");
    $ax2->set_grid(1);
    $ax2->hist_kde($d2,
        bins=>30, color=>'coral', kde_color=>'darkred',
        label=>'bimodal', kde_label=>'KDE');
    $ax2->legend(loc=>'upper right');
    $ax2->xlabel("Value"); $ax2->ylabel("Density");

    show_fig($fig);
    print "stats_06: hist_kde\n";
}

print "\nAll stats demos complete.\n";
