package PDL::Graphics::Cairo::Driver::OSX;

# =============================================================
# Driver::OSX — macOSネイティブCocoaウィンドウ表示
#
# 方式: Driver::Gnuplotと同じ「PNG経由」アプローチ
#   1. Cairo::ImageSurface → PNG一時ファイル
#   2. pdlcairo_viewer（独立Cocoaアプリ）をexecして表示
#
# gnuplot・AquaTerm・X11・FFI不要
# NSAppはpdlcairo_viewerプロセス内のメインスレッドで動くので
# macOS 15のスレッド制約に抵触しない
#
# 使い方:
#   $fig->show(backend => 'osx');
#   $fig->show(backend => 'osx', title => 'My Plot', keep => 1);
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

# pdlcairo_viewerのパスを探す
my $VIEWER = _find_viewer();

sub _find_viewer {
    # 1. 環境変数で上書き
    return $ENV{PDLCAIRO_VIEWER} if $ENV{PDLCAIRO_VIEWER} && -x $ENV{PDLCAIRO_VIEWER};

    # 2. このpmファイルからの相対パス（開発時）
    #    lib/PDL/Graphics/Cairo/Driver/OSX.pm → src/osx/pdlcairo_viewer
    use File::Basename qw(dirname);
    my $base = dirname(__FILE__);          # .../Driver/
    my $dev  = "$base/../../../../../src/osx/pdlcairo_viewer";
    # パスを正規化
    if (-x $dev) {
        require Cwd;
        return Cwd::realpath($dev);
    }

    # 3. インストール先
    for my $p (qw(/usr/local/bin/pdlcairo_viewer
                  /opt/local/bin/pdlcairo_viewer)) {
        return $p if -x $p;
    }

    return undef;
}

# ------------------------------------------------------------------
# show($figure)
# ------------------------------------------------------------------
sub show {
    my ($self, $figure) = @_;

    die "Driver::OSX: pdlcairo_viewer が見つかりません。\n"
      . "  ビルド: cd src/osx && bash build.sh\n"
      . "  または: PDLCAIRO_VIEWER=/path/to/pdlcairo_viewer を設定\n"
      unless defined $VIEWER && -x $VIEWER;

    # 1. PNG一時ファイルに描画
    my ($fh, $tmpfile) = tempfile(
        'pdlcairo_osx_XXXXXX',
        SUFFIX => '.png',
        TMPDIR => 1,
        UNLINK => $self->keep ? 0 : 1,
    );
    close $fh;

    my $png = PDL::Graphics::Cairo::Driver::Cairo->new(
        width  => $self->width,
        height => $self->height,
        file   => $tmpfile,
    );
    $figure->_render_to($png);

    # 2. pdlcairo_viewerを起動して表示（ウィンドウが閉じられるまで待機）
    my $title = $self->title;
    system($VIEWER, $tmpfile, $title);
}

1;

__END__

=head1 NAME

PDL::Graphics::Cairo::Driver::OSX - macOS native Cocoa window display

=head1 SYNOPSIS

  $fig->show(backend => 'osx');
  $fig->show(backend => 'osx', title => 'My Plot');

=head1 DESCRIPTION

PNG一時ファイル経由でpdlcairo_viewerに表示を委譲します。
gnuplot・AquaTerm・X11不要。

=head1 ENVIRONMENT

  PDLCAIRO_VIEWER   pdlcairo_viewerのフルパスを指定
  PDLCAIRO_BACKEND  'osx'を設定するとshow()のデフォルトになる

=cut
