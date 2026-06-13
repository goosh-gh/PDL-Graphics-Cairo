use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo;

# 精度許容値
my $EPS = 1e-6;

sub near {
    my ($a, $b, $label) = @_;
    if (!defined $a || !defined $b) {
        fail("$label: undef値");
        return;
    }
    ok(abs($a - $b) < $EPS, $label)
        or diag("got $a, expected $b, diff=".abs($a-$b));
}

# $fig->to_png で _render_to → ax->draw() が走り _plot_ml 等がキャッシュされる
sub render {
    my ($fig) = @_;
    $fig->tight_layout;
    $fig->to_png;   # headless 描画トリガー（Cairo :memory: に書く）
}

# ─── テスト1: 通常軸（非反転）の往復変換 ─────────────────────────────
{
    my $fig = PDL::Graphics::Cairo->new(figsize => [8, 6]);
    my ($ax) = $fig->subplots(1, 1);
    $ax->xlim(0, 10);
    $ax->ylim(0, 5);
    $ax->line(pdl(0,10), pdl(0,5));
    render($fig);

    my ($fx, $fy) = $ax->data_to_image_frac(5, 2.5);
    my ($xd, $yd) = $ax->image_frac_to_data($fx, $fy);
    near($xd, 5,   'round-trip x, 通常軸');
    near($yd, 2.5, 'round-trip y, 通常軸');

    ($fx, $fy) = $ax->data_to_image_frac(0, 0);
    ($xd, $yd) = $ax->image_frac_to_data($fx, $fy);
    near($xd, 0, 'round-trip x=0');
    near($yd, 0, 'round-trip y=0');

    ($fx, $fy) = $ax->data_to_image_frac(10, 5);
    ($xd, $yd) = $ax->image_frac_to_data($fx, $fy);
    near($xd, 10, 'round-trip x=xmax');
    near($yd, 5,  'round-trip y=ymax');
}

# ─── テスト2: _y_reversed (ERP/PGPLOT流 negative-up) ─────────────────
{
    my $fig = PDL::Graphics::Cairo->new(figsize => [8, 6]);
    my ($ax) = $fig->subplots(1, 1);
    $ax->xlim(0, 1000);
    $ax->ylim(10, -10);   # negative up → _y_reversed=1
    $ax->line(pdl(0,1000), pdl(0,0));
    render($fig);

    ok($ax->{_y_reversed}, '_y_reversed が設定されている');

    my ($fx, $fy) = $ax->data_to_image_frac(500, 0);
    my ($xd, $yd) = $ax->image_frac_to_data($fx, $fy);
    near($xd, 500, 'round-trip x, reversed y');
    near($yd, 0,   'round-trip y=0, reversed y');

    ($fx, $fy) = $ax->data_to_image_frac(200, -5);
    ($xd, $yd) = $ax->image_frac_to_data($fx, $fy);
    near($xd, 200, 'round-trip x=200, reversed y');
    near($yd, -5,  'round-trip y=-5, reversed y');
}

# ─── テスト3: プロット枠外では undef を返す ────────────────────────────
{
    my $fig = PDL::Graphics::Cairo->new(figsize => [8, 6]);
    my ($ax) = $fig->subplots(1, 1);
    $ax->xlim(0, 10);
    $ax->ylim(0, 10);
    $ax->line(pdl(0,10), pdl(0,10));
    render($fig);

    my ($xd, $yd) = $ax->image_frac_to_data(0.0, 0.0);
    ok(!defined($xd), 'frac(0,0) は枠外 → x undef');
    ok(!defined($yd), 'frac(0,0) は枠外 → y undef');

    ($xd, $yd) = $ax->image_frac_to_data(1.0, 1.0);
    ok(!defined($xd), 'frac(1,1) は枠外 → x undef');
    ok(!defined($yd), 'frac(1,1) は枠外 → y undef');
}

# ─── テスト4: set_aspect('equal') でも往復変換が成立 ──────────────────
{
    my $fig = PDL::Graphics::Cairo->new(figsize => [8, 6]);
    my ($ax) = $fig->subplots(1, 1);
    $ax->xlim(-1, 1);
    $ax->ylim(-1, 1);
    $ax->set_aspect('equal');
    $ax->line(pdl(-1,1), pdl(-1,1));
    render($fig);

    my ($fx, $fy) = $ax->data_to_image_frac(0, 0);
    my ($xd, $yd) = $ax->image_frac_to_data($fx, $fy);
    near($xd, 0, 'round-trip x=0, equal aspect');
    near($yd, 0, 'round-trip y=0, equal aspect');
}

# ─── テスト5: draw()前に呼ぶとdieする ─────────────────────────────────
{
    my $fig = PDL::Graphics::Cairo->new(figsize => [8, 6]);
    my ($ax) = $fig->subplots(1, 1);
    $ax->xlim(0, 10); $ax->ylim(0, 10);
    eval { $ax->image_frac_to_data(0.5, 0.5) };
    like($@, qr/draw\(\)/, 'draw()前の呼び出しでdie');
}

done_testing;
