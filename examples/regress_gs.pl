#!/usr/bin/env perl
# =============================================================
# regress_gs.pl — ドライバ一本化(/gs)後の回帰チェックハーネス
#
# 目的:
#   _default_backend() を darwin で 'gs' に昇格したあと、フロントエンド
#   の二系統 API（matplotlib 風 / PGPLOT 風）と show_interactive、および
#   wait_all の no-op 化、gnuplot フォールバックが壊れていないことを確認。
#
# 使い方:
#   perl -I./lib examples/regress_gs.pl            # 窓を出して全段（gs 経路の本番）
#   REGRESS_NOWIN=1 perl -I./lib examples/regress_gs.pl   # 窓なし(save系のみ)
#
# 重要:
#   REGRESS_NOWIN=1 では gs の「表示」段は [skip] になる（窓を開かない）。
#   gs 窓の回帰は窓ありで回すこと。ヘッダに実際の既定バックエンドと
#   giza_server の発見状況を出すので、まずそこを確認する。
#
#   giza_server が PATH に無ければ:
#     GIZA_SERVER=/path/to/giza_server perl -I./lib examples/regress_gs.pl
# =============================================================

use strict;
use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);
use PDL::Graphics::Cairo::Figure;
use PDL::Graphics::Cairo::Driver::GS;

my $WIN = !$ENV{REGRESS_NOWIN};   # 既定: 窓を出す。REGRESS_NOWIN=1 で抑止
my $OUT = $ENV{TMPDIR} || '/tmp';
$OUT =~ s{/+$}{};                 # 末尾スラッシュ正規化
my @fail;

sub stage { print "\n=== $_[0] ===\n" }
sub ok    { print "  [ok] $_[0]\n" }
sub skip  { print "  [skip] $_[0]\n" }
sub bad   { push @fail, $_[0]; print "  [FAIL] $_[0]\n" }
sub try   { my ($name,$code)=@_; eval { $code->(); ok($name); 1 } or bad("$name: $@") }
# 窓を開く段。WIN=0 なら正直に skip（実行しないので [ok] にしない）
sub win   { my ($name,$code)=@_; return skip("$name (WIN=0)") unless $WIN; try($name,$code) }

# -------------------------------------------------------------
# ヘッダ: 実際の既定バックエンドと giza_server の発見状況（最重要）
# -------------------------------------------------------------
my $defb     = eval { PDL::Graphics::Cairo::Figure::_default_backend() } // '(error)';
my $gs_found = PDL::Graphics::Cairo::Driver::GS::_find_server() // '(not found)';
my $gs_alive = PDL::Graphics::Cairo::Driver::GS::_server_alive() ? 'yes' : 'no';
print "regress_gs: OS=$^O  WIN=", ($WIN?1:0), "\n";
print "  default_backend = $defb    (darwin での期待値: 'gs')\n";
print "  giza_server bin = $gs_found\n";
print "  server alive    = $gs_alive\n";
if ($^O eq 'darwin' && $defb ne 'gs') {
    print "  [warn] darwin なのに既定が '$defb'。giza_server が見つからず\n";
    print "         gnuplot(aqua=AquaTerm) に退避しています。ドライバ一本化が\n";
    print "         効いていません。GIZA_SERVER を設定するか、giza_server を\n";
    print "         PATH か /usr/local/bin・/opt/local/bin に置いてください。\n";
}
print <<'NOTE';

  窓の種類（仕様。タブで挙動が違うのは正常）:
   - plain show()  … 静止 PNG のクライアント切断窓。スライダ無反応・ベクタ
                      保存不可（押すと「未対応」ダイアログ）。ステージ1,2,3。
   - show_interactive() … 生きた窓。スライダ可・File>Save で PDF/SVG 可。ステージ4。
NOTE

# -------------------------------------------------------------
# 1) matplotlib 風 API — 描画系(save) と 表示経路(show)
# -------------------------------------------------------------
stage('1. matplotlib-style: save + show (default backend)');
try 'mpl save png' => sub {
    my $x = sequence(200) / 20;
    my ($fig, $ax) = subplots(1, 1, width => 720, height => 420);
    $ax->line($x, sin($x), color => 'blue', lw => 1.5, label => 'sin');
    $ax->line($x, cos($x), color => 'red',  lw => 1.5, label => 'cos');
    $ax->set_title('regress: matplotlib-style');
    $ax->set_xlabel('x'); $ax->set_ylabel('y');
    $ax->legend();
    $fig->tight_layout();
    $fig->save("$OUT/regress_mpl.png");
    die "png not written\n" unless -s "$OUT/regress_mpl.png";
};
win 'mpl show (default backend; gs 窓 or aqua退避)' => sub {
    my $x = sequence(200) / 20;
    my ($fig, $ax) = subplots(1, 1, width => 720, height => 420);
    $ax->line($x, sin($x), color => 'blue', lw => 1.5, label => 'sin');
    $ax->set_title("regress: mpl show() [default=$defb]");
    $ax->legend();
    $fig->tight_layout();
    $fig->show();    # backend 未指定 → _default_backend()
};

# -------------------------------------------------------------
# 2) matplotlib 風 — 多パネルを明示 gs で表示
# -------------------------------------------------------------
stage('2. matplotlib-style: 2-panel show backend=>gs (explicit)');
win 'mpl 1x2 show backend=>gs' => sub {
    my $x = sequence(200) / 20;
    my ($fig, $ax1, $ax2) = subplots(1, 2, width => 980, height => 380);
    $ax1->line($x, sin($x), color => 'blue');  $ax1->set_title('sin');
    $ax2->line($x, $x*$x,   color => 'green'); $ax2->set_title('parabola');
    $fig->tight_layout();
    $fig->show(backend => 'gs', title => 'regress: 1x2 /gs');
};

# -------------------------------------------------------------
# 3) PGPLOT 風 API — /gs デバイス（および退役 /osx の gs ルーティング）
#    save 段(PNG)は WIN に関係なく実行（非インタラクティブ＝窓を開かない）。
# -------------------------------------------------------------
stage('3. PGPLOT-style: /gs device + PNG save');
try 'pgplot PNG save (non-interactive)' => sub {
    require PDL::Graphics::Cairo::PGPLOT;
    PDL::Graphics::Cairo::PGPLOT->import(':all');
    no strict 'subs';
    my @xx = (-100 .. 899);
    my @yy = map { 10 + $_ * (-20 / 999) } (0 .. 999);
    pgbegin(0, "$OUT/regress_pgplot.png/PNG", 1, 1);   # PNG=非インタラクティブ
    pgenv(-100, 899, 10, -10, 0, -2);
    pgsci(3); pgline(scalar(@xx), \@xx, \@yy);
    pgsci(1); pgbox("ANST", 0.0, 1, "ANTV", 5.0, 2);
    pgmtxt("TR", -1, 0.1, 1.0, "Ch1");
    pgend();
    die "png not written\n" unless -s "$OUT/regress_pgplot.png";
};
win 'pgplot /gs device (window)' => sub {
    require PDL::Graphics::Cairo::PGPLOT;
    PDL::Graphics::Cairo::PGPLOT->import(':all');
    no strict 'subs';
    my @xx = (-100 .. 899);
    my @yy = map { 10 + $_ * (-20 / 999) } (0 .. 999);
    pgbegin(0, '/gs', 1, 1);          # 一本化で giza_server 経由
    pgenv(-100, 899, 10, -10, 0, -2);
    pgsci(3); pgline(scalar(@xx), \@xx, \@yy);
    pgsci(1); pgbox("ANST", 0.0, 1, "ANTV", 5.0, 2);
    pgend();
};
win 'pgplot legacy /osx -> gs (window)' => sub {
    require PDL::Graphics::Cairo::PGPLOT;
    PDL::Graphics::Cairo::PGPLOT->import(':all');
    no strict 'subs';
    my @xx = (0 .. 99);
    my @yy = map { $_*$_ } @xx;
    pgbegin(0, '/osx', 1, 1);         # 退役デバイス名だが gs にルーティング
    pgenv(0, 99, 0, 9801, 0, 0);
    pgsci(2); pgline(scalar(@xx), \@xx, \@yy);
    pgend();
};

# -------------------------------------------------------------
# 4) show_interactive — スライダ + File>Save(PDF/SVG) を手動確認
# -------------------------------------------------------------
stage('4. show_interactive: live window (2 sliders + vector save)');
win 'show_interactive (k=横, A=縦)' => sub {
    my $drv = PDL::Graphics::Cairo::Driver::GS->new(
        width => 720, height => 420, title => 'regress: interactive [LIVE]');
    print "  -> 横スライダ=周波数 k、縦スライダ=振幅 A。両方動かして再描画を確認。\n";
    print "  -> File>Save as PDF/SVG（生きた窓なので保存できるのが正）。\n";
    print "  -> 確認できたら窓を閉じる（このスクリプトが先へ進む）。\n";
    $drv->show_interactive(
        init   => { 0 => 1.0, 1 => 1.0 },     # 0=k(横) 1=A(縦) 両方読む
        render => sub {
            my ($state, $w, $h, $opts) = @_;
            my $is_save = $opts && $opts->{is_save};
            my $k = $state->{0} // 1.0;        # 周波数（横スライダ）
            my $A = $state->{1} // 1.0;        # 振幅（縦スライダ）
            my $x = sequence(400) / 400 * (2 * 3.14159265358979);
            my $fig_w = $is_save ? 1440 : ($w // 720);
            my $fig_h = $is_save ? 840  : ($h // 420);
            my $fig = figure(width => $fig_w, height => $fig_h);
            my $ax  = $fig->axes();
            $ax->line($x, $A * sin($k * $x), color => 'blue', lw => 1.5,
                      label => sprintf('%.2f*sin(%.2f x)', $A, $k));
            $ax->ylim(-2.5, 2.5);
            $ax->set_title('regress: drag both sliders, then File>Save');
            $ax->legend();
            $fig->tight_layout();
            return $fig;
        },
    );
};

# -------------------------------------------------------------
# 5) wait_all() の no-op 化 — gs 下で例外を出さず即返ること
# -------------------------------------------------------------
stage('5. wait_all() is a harmless no-op under gs');
try 'OSX->wait_all() no-op' => sub {
    require PDL::Graphics::Cairo::Driver::OSX;
    PDL::Graphics::Cairo::Driver::OSX->wait_all();   # OSX キューは空→黙って返る
    PDL::Graphics::Cairo::Driver::OSX->wait_all();   # 2回呼んでも安全
};

# -------------------------------------------------------------
# 6) gnuplot フォールバックが生きていること（save sanity）
# -------------------------------------------------------------
stage('6. gnuplot backend still reachable (save sanity)');
try 'gnuplot save sanity' => sub {
    my $x = sequence(100) / 10;
    my $fig = figure(width => 600, height => 360);
    my $ax  = $fig->axes();
    $ax->line($x, sin($x), color => 'black');
    $fig->tight_layout();
    $fig->save("$OUT/regress_gnuplot_sanity.png");
    die "png not written\n" unless -s "$OUT/regress_gnuplot_sanity.png";
};

# -------------------------------------------------------------
print "\n", ('=' x 50), "\n";
if (@fail) {
    print "REGRESS: ", scalar(@fail), " FAIL\n";
    print "  - $_\n" for @fail;
    exit 1;
} else {
    print "REGRESS: all executed stages PASS";
    print "  (WIN=0: gs 表示段は skip。窓ありで再実行して gs 窓を確認すること)" unless $WIN;
    print "\n  outputs in $OUT/regress_*.png\n";
    exit 0;
}
