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
        my ($s) = @_;
        my $k = $s->{0} // 1.0;
        my $A = $s->{1} // 1.0;
        my $x = sequence(500) / 499 * (2 * 3.14159265358979);
        my $y = $A * sin($k * $x);

        # ↓ 修正：plot → line、set_ylim → ylim
        my $fig = figure(width => 640, height => 480);
        my ($ax) = $fig->subplots(1, 1);
        $ax->line($x, $y);
        $ax->ylim(-2.2, 2.2);
        $fig->tight_layout;
        return $fig;


        # ↓ ここは P:G:Cairo の実際の Figure API に合わせて調整してください。
        #   run() が要求するのは「返り値が _render_to に応答する」ことだけ。
#        my $fig = figure(width => 640, height => 480);
#        my ($ax) = $fig->subplots(1, 1);
#        $ax->plot($x, $y);
#        $ax->set_ylim(-2.2, 2.2) if $ax->can('set_ylim');
#        $fig->tight_layout;
#        return $fig;
    },
);
