package PDL::Graphics::Cairo::Driver::OSX;

# =============================================================
# Driver::OSX — macOSネイティブCocoaウィンドウ表示
#
# 方式:
#   show()呼び出しごとにPNGを生成してキューに積む。
#   wait_all()で全PNGをまとめてpdlcairo_viewerに渡す。
#   → 1プロセス内でタブとして表示される。
#
# 使い方:
#   # 即時表示（ブロッキング）
#   $fig->show(backend => 'osx');
#
#   # 複数図をタブで同時表示
#   $fig1->show(backend => 'osx', nowait => 1, title => 'Demo 1');
#   $fig2->show(backend => 'osx', nowait => 1, title => 'Demo 2');
#   PDL::Graphics::Cairo::Driver::OSX->wait_all();
# =============================================================

use strict;
use warnings;
use Moo;
use File::Temp qw(tempfile);
use PDL::Graphics::Cairo::Driver::Cairo;

has width  => (is => 'ro', required => 1);
has height => (is => 'ro', required => 1);
has title  => (is => 'ro', default  => sub { 'PDL::Graphics::Cairo' });
has keep   => (is => 'ro', default  => sub { 0 });
has nowait => (is => 'ro', default  => sub { 0 });

my @_queue;
my $VIEWER = _find_viewer();

sub _find_viewer {
    return undef unless $^O eq 'darwin';  # macOS only, fallback to gnuplot on linux
    return $ENV{PDLCAIRO_VIEWER}
        if $ENV{PDLCAIRO_VIEWER} && -x $ENV{PDLCAIRO_VIEWER};

    use File::Basename qw(dirname);
    my $base = dirname(__FILE__);
    my $dev  = "$base/../../../../../src/osx/pdlcairo_viewer";
    if (-x $dev) {
        require Cwd;
        return Cwd::realpath($dev);
    }

    for my $p (qw(/usr/local/bin/pdlcairo_viewer
                  /opt/local/bin/pdlcairo_viewer)) {
        return $p if -x $p;
    }
    return undef;
}

sub _check_viewer {
    die "Driver::OSX: pdlcairo_viewer not found.\n"
      . "  Build: make\n"
      . "  Or set: PDLCAIRO_VIEWER=/path/to/pdlcairo_viewer\n"
      unless defined $VIEWER && -x $VIEWER;
}

sub _render_to_png {
    my ($self, $figure) = @_;

    my ($fh, $tmpfile) = tempfile(
        'pdlcairo_osx_XXXXXX',
        SUFFIX => '.png',
        TMPDIR => 1,
        UNLINK => 0,
    );
    close $fh;

    my $png = PDL::Graphics::Cairo::Driver::Cairo->new(
        width  => $self->width,
        height => $self->height,
        file   => $tmpfile,
    );
    $figure->_render_to($png);
    return $tmpfile;
}

sub show {
    my ($self, $figure) = @_;

    # pdlcairo_viewer が見つからない場合は gnuplot にフォールバック
    unless (defined $VIEWER && -x $VIEWER) {
        require PDL::Graphics::Cairo::Driver::Gnuplot;
        my $driver = PDL::Graphics::Cairo::Driver::Gnuplot->new(
            width  => $self->width,
            height => $self->height,
        );
        $driver->show($figure);
        return;
    }

    my $tmpfile = $self->_render_to_png($figure);

    if ($self->nowait) {
        push @_queue, { file => $tmpfile, title => $self->title };
    } else {
        system($VIEWER, $tmpfile, $self->title);
        unlink $tmpfile unless $self->keep;
    }
}


sub wait_all {
    my $class = shift;
    return unless @_queue;

    unless (defined $VIEWER && -x $VIEWER) {
        # Fallback: show each queued figure via gnuplot
        require PDL::Graphics::Cairo::Driver::Gnuplot;
        for my $item (@_queue) {
            my $driver = PDL::Graphics::Cairo::Driver::Gnuplot->new(
                width  => 800, height => 600,
            );
            system($driver->gnuplot, $item->{file});
        }
        unlink $_->{file} for @_queue;
        @_queue = ();
        return;
    }

    my @args  = map { ($_->{file}, $_->{title}) } @_queue;
    my @files = map { $_->{file} } @_queue;
    system($VIEWER, @args);
    unlink $_ for @files;
    @_queue = ();
}

sub clear_queue { @_queue = () }

1;

__END__

=head1 NAME

PDL::Graphics::Cairo::Driver::OSX - macOS native Cocoa window display

=head1 SYNOPSIS

  # ブロッキング
  $fig->show(backend => 'osx');

  # 複数図をタブで同時表示
  $fig1->show(backend => 'osx', nowait => 1, title => 'Demo 1');
  $fig2->show(backend => 'osx', nowait => 1, title => 'Demo 2');
  PDL::Graphics::Cairo::Driver::OSX->wait_all();

=head1 ENVIRONMENT

  PDLCAIRO_VIEWER   pdlcairo_viewerのフルパスを指定
  PDLCAIRO_BACKEND  'osx'を設定するとshow()のデフォルトになる

=cut
