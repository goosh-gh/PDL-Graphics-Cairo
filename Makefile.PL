use strict;
use warnings;
use ExtUtils::MakeMaker;

# Cairo::GObject is required on macOS (MacPorts) but not on Ubuntu/Linux
# where Pango initializes GObject internally.
# Listed under optional_features, not PREREQ_PM.

WriteMakefile(
    NAME             => 'PDL::Graphics::Cairo',
    AUTHOR           => 'Shugo Suwazono  <zvb10512@nifty.ne.jp>',
    VERSION_FROM     => 'lib/PDL/Graphics/Cairo.pm',
    ABSTRACT_FROM    => 'lib/PDL/Graphics/Cairo.pm',
    LICENSE          => 'perl_5',

    MIN_PERL_VERSION => '5.016',

    PREREQ_PM => {
        'PDL'        => '2.0',   # Numerical computation engine
        'Moo'        => '2.0',   # Object system
        'Cairo'      => '1.0',   # Perl bindings for the Cairo C library
        'Pango'      => '1.0',   # Unicode text rendering (Cairo alone is insufficient)
        'Encode'     => '0',     # UTF-8 / byte string conversion
        'File::Temp' => '0',     # Temporary files for show()
        'IPC::Open3' => '0',     # gnuplot process management
        'POSIX'      => '0',
        'List::Util' => '0',
        'Exporter'   => '0',
    },

    # Cairo::GObject is needed on macOS, not on Linux.
    # Verify manually after perl Makefile.PL:
    #   macOS:  sudo port install p5-cairo-gobject
    #   Ubuntu: usually not needed (included in libpango-perl)

    TEST_REQUIRES => {
        'Test::More' => '0.98',
    },

    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/goosh-gh/PDL-Graphics-Cairo.git',
                web  => 'https://github.com/goosh-gh/PDL-Graphics-Cairo',
            },
        },
        prereqs => {
            runtime => {
                recommends => {
                    'Cairo::GObject' => '0',  # required on macOS
                },
                suggests => {
                    # For interactive display (show() method)
                    # gnuplot is not on CPAN; install via OS package manager
                },
            },
        },
    },

    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
    clean => { FILES    => 'PDL-Graphics-Cairo-*' },
);
