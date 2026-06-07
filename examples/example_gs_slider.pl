#!/usr/bin/env perl
use strict; use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure);
use PDL::Graphics::Cairo::Driver::GS;

my $gs = PDL::Graphics::Cairo::Driver::GS->new(
    width => 640, height => 480, title => 'sin demo (gs)',
    # start => 'auto',  # 既定。スライダ対応 giza_server が必要
);

$gs->show_interactive(
    init   => { 0 => 1.0, 1 => 1.0 },
    render => sub {
        my ($s, $w, $h) = @_;            # $w/$h = 現在の窓サイズ(px)
        my $k = $s->{0} // 1.0;
        my $A = $s->{1} // 1.0;
        my $x = sequence(500) / 499 * (2 * 3.14159265358979);
        my $y = $A * sin($k * $x);

        # $w/$h を使うとリサイズに追従して再レイアウト（AquaTerm 風）。
        # 初回は new() の width/height（640x480）が渡る。
        my $fig = figure(width => $w, height => $h);
        my ($ax) = $fig->subplots(1, 1);
        $ax->line($x, $y);
        $ax->ylim(-2.2, 2.2);
        $fig->tight_layout;
        return $fig;
    },
);
