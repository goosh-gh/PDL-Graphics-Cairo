#!/usr/bin/env perl
# t/61_without_pdl_stats.t — PDL::Stats が無い環境でも qqplot と hist_kde が描けること。
# PDL::Stats::Basic を @INC のフックで読めなくしてから P:G:C を読み込む。
# 標準偏差は母標準偏差(N で割る)。2,4,4,4,5,5,7,9 の母標準偏差は 2(よく知られた例)。
use strict;
use warnings;
use Test::More;

BEGIN {
    unshift @INC, sub {
        my (undef, $file) = @_;
        die "PDL::Stats hidden by t/61\n" if $file =~ m{^PDL/Stats};
        return;
    };
}
use PDL;
use PDL::Graphics::Cairo qw(figure);

ok(!eval { require PDL::Stats::Basic; 1 }, 'PDL::Stats::Basic cannot be loaded in this test');

is(PDL::Graphics::Cairo::Axes::_stdv_pop(pdl(2, 4, 4, 4, 5, 5, 7, 9)), 2,
   'population standard deviation of 2,4,4,4,5,5,7,9 is 2');
is(PDL::Graphics::Cairo::Axes::_stdv_pop(pdl(long, 3, 3, 3)), 0, 'constant data: 0 (integer input)');

for my $m (qw(qqplot hist_kde)) {
    my $f = figure(width => 300, height => 200);
    my $ax = $f->axes;
    my $data = sin(sequence(200) / 7) * 3 + sequence(200) / 100;
    ok(eval { $ax->$m($data); $f->to_png; 1 }, "$m draws without PDL::Stats") or diag $@;
}

done_testing;
