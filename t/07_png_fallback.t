use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure);

# PNG output must work whether or not PDL::IO::PNG (wpng) is available.
# Force the Cairo write_to_png fallback by clearing the HAVE_WPNG flag, the
# same state a machine without PDL::IO::PNG is in. This guards the optional-
# dependency design: the module loads and save() still produces a PNG.

# 1) Normal path (whatever is installed) produces a PNG.
{
    my $fig = figure(width => 200, height => 150);
    my $ax  = $fig->axes();
    $ax->line(sequence(10), sequence(10) ** 2);
    my $f = "/tmp/pgc_png_normal_$$.png";
    eval { $fig->save($f) };
    is $@, '', 'save() no error (default PNG path)';
    ok -s $f, 'PNG file created and non-empty (default path)';
    unlink $f;
}

# 2) Forced fallback: pretend PDL::IO::PNG is absent.
{
    local $PDL::Graphics::Cairo::Driver::Cairo::HAVE_WPNG = 0;
    my $fig = figure(width => 200, height => 150);
    my $ax  = $fig->axes();
    $ax->line(sequence(10), sequence(10) ** 2);
    my $f = "/tmp/pgc_png_fallback_$$.png";
    eval { $fig->save($f) };
    is $@, '', 'save() no error with HAVE_WPNG=0 (Cairo write_to_png fallback)';
    ok -s $f, 'PNG file created and non-empty (fallback path)';
    unlink $f;
}

done_testing;
