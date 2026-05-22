use strict;
use warnings;
use ExtUtils::MakeMaker;

# macOSかどうか判定
my $is_mac = ($^O eq 'darwin');

WriteMakefile(
    NAME             => 'PDL::Graphics::Cairo',
    AUTHOR           => 'Shugo Suwazono  <zvb10512@nifty.ne.jp>',
    VERSION_FROM     => 'lib/PDL/Graphics/Cairo.pm',
    ABSTRACT_FROM    => 'lib/PDL/Graphics/Cairo.pm',
    LICENSE          => 'perl_5',
    MIN_PERL_VERSION => '5.016',
    PREREQ_PM => {
        'PDL'        => '2.0',
        'Moo'        => '2.0',
        'Cairo'      => '1.0',
        'Pango'      => '1.0',
        'Encode'     => '0',
        'File::Temp' => '0',
        'IPC::Open3' => '0',
        'POSIX'      => '0',
        'List::Util' => '0',
        'Exporter'   => '0',
    },
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
            },
        },
    },
    # macOSのみ: pdlcairo_viewerをINSTALLBINにインストール
    ($is_mac ? (
        EXE_FILES => ['bin/pdlcairo_viewer'],
    ) : ()),
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
    clean => { FILES    => 'PDL-Graphics-Cairo-* bin/pdlcairo_viewer' },
);

# ------------------------------------------------------------------
# postamble: macOSのみ pdlcairo_viewer をビルド
# ------------------------------------------------------------------
{
    package MY;
    sub postamble {
    return '' unless $is_mac;

    return <<'MAKE_FRAG';
# pdlcairo_viewer: macOSネイティブCocoaビューア
# src/osx/pdlcairo_viewer.m → bin/pdlcairo_viewer

bin/pdlcairo_viewer: src/osx/pdlcairo_viewer.m
	@echo "=== Building pdlcairo_viewer (macOS Cocoa) ==="
	@mkdir -p bin
	clang -fobjc-arc -framework Cocoa \
	    -o bin/pdlcairo_viewer \
	    src/osx/pdlcairo_viewer.m
	@echo "=== pdlcairo_viewer built ==="

all :: bin/pdlcairo_viewer

pure_all :: bin/pdlcairo_viewer

clean ::
	rm -f bin/pdlcairo_viewer

MAKE_FRAG
    }
}
