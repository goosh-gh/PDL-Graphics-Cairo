use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo::PGPLOT;

# Module loading
use_ok 'PDL::Graphics::Cairo::PGPLOT';

# Basic cpgbeg/cpgend operation (PNG output)
my $tmpfile = "/tmp/test_pgplot_$$.png";
my $ret = cpgbeg(0, "$tmpfile/PNG", 1, 1);
is $ret, 1, 'cpgbeg returns 1';

# cpgenv
eval { cpgenv(0, 10, -1, 1, 0, 0) };
is $@, '', 'cpgenv no error';

# cpglab
eval { cpglab("x", "y", "title") };
is $@, '', 'cpglab no error';

# cpgline
my $x = sequence(10);
my $y = sin($x);
eval { cpgline(10, $x, $y) };
is $@, '', 'cpgline no error';

# cpgpt
eval { cpgpt(5, $x->slice('0:4'), $y->slice('0:4'), 4) };
is $@, '', 'cpgpt no error';

# cpgsci / cpgslw / cpgsls / cpgsch
eval { cpgsci(2); cpgslw(2); cpgsls(2); cpgsch(1.5) };
is $@, '', 'attribute setters no error';

# cpgmove / cpgdraw
eval { cpgmove(0, 0); cpgdraw(5, 0.5) };
is $@, '', 'cpgmove/cpgdraw no error';

# cpgend
eval { cpgend() };
is $@, '', 'cpgend no error';
ok -f $tmpfile, 'PNG file created';
unlink $tmpfile;

# Test pg-prefixed aliases (imported via :pg tag)
{
    # Use :pg tag in a separate scope
    require PDL::Graphics::Cairo::PGPLOT;
    PDL::Graphics::Cairo::PGPLOT->import(':pg');

    my $tmpfile2 = "/tmp/test_pg_prefix_$$.png";
    eval { pgbeg(0, "$tmpfile2/PNG", 1, 1) };
    is $@, '', 'pgbeg no error';

    eval { pgenv(0, 10, -1, 1, 0, 0) };
    is $@, '', 'pgenv no error';

    eval { pgline(5, pdl(1,2,3,4,5), pdl(0.1,0.4,0.9,0.4,0.1)) };
    is $@, '', 'pgline no error';

    eval { pgend() };
    is $@, '', 'pgend no error';
    ok -f $tmpfile2, 'pg prefix PNG created';
    unlink $tmpfile2;
}

done_testing;
