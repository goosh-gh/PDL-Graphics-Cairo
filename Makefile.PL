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
                    'PDL::IO::PNG'   => '0',  # optional: faster PNG I/O
                },
            },
        },
    },
    # macOS ネイティブビューア pdlcairo_viewer は退役（ドライバ一本化）。
    # 表示は giza_server バックエンド (Driver::GS, 'gs') に集約したため、
    # インストールしない。ソースは src/osx/ に残置（可逆）。
    # 復活させたい場合は次行のコメントを外す:
    #   ($is_mac ? ( EXE_FILES => ['bin/pdlcairo_viewer'] ) : ()),
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
    clean => { FILES    => 'PDL-Graphics-Cairo-* bin/pdlcairo_viewer' },
);

# ------------------------------------------------------------------
# Optional speed-up advisory. PDL::IO::PNG makes PNG output and imread()
# faster, but is NOT required: PNG writing falls back to Cairo's own
# write_to_png, and imread() falls back to PDL::IO::Image / rpic. We do not
# put it in PREREQ_PM (it stays optional); we just tell the user once, here,
# so they can choose to install it for the fast path.
# ------------------------------------------------------------------
unless (eval { require PDL::IO::PNG; 1 }) {
    print <<'PNGNOTE';

  Note: PDL::IO::PNG is not installed (optional).
        PDL::Graphics::Cairo works fine without it, but PNG output is faster
        with it (~3.4 ms vs ~9.2 ms via Cairo), and imread() is faster too.
        To enable the fast path:  cpan PDL::IO::PNG

PNGNOTE
}

# ------------------------------------------------------------------
# postamble: pdlcairo_viewer のビルドは退役（ドライバ一本化）。
# macOS ネイティブ表示は giza_server ('gs') に集約したため、ここでは
# 何もビルドしない。src/osx/pdlcairo_viewer.m は可逆性のため残置。
# 復活させたい場合は下のヒアドキュメント本体を return すればよい。
# ------------------------------------------------------------------
{
    package MY;
    sub postamble {
    return '';   # retired: no pdlcairo_viewer build

    # --- 旧ビルドフラグメント（復活用に保存） ---------------------------
    # return '' unless $is_mac;
    # return <<'MAKE_FRAG';
    # bin/pdlcairo_viewer: src/osx/pdlcairo_viewer.m
    # 	@mkdir -p bin
    # 	clang -framework Cocoa -o bin/pdlcairo_viewer src/osx/pdlcairo_viewer.m
    # all :: bin/pdlcairo_viewer
    # pure_all :: bin/pdlcairo_viewer
    # clean ::
    # 	rm -f bin/pdlcairo_viewer
    # MAKE_FRAG
    }
}
