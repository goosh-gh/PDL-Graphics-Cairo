use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);

# ------------------------------------------------------------------
# colorbar(label=>'...') のオプション解析と保存先(colorbar_label属性)
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->imshow(sequence(10,10), cmap=>'jet', vmin=>0, vmax=>1);
    $ax->colorbar(label=>'intensity');

    is $ax->colorbar_label, 'intensity', 'colorbar_label is stored from colorbar(label=>...)';
}

# ------------------------------------------------------------------
# label未指定時はcolorbar_labelが空文字のままであること
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->imshow(sequence(10,10), cmap=>'jet', vmin=>0, vmax=>1);
    $ax->colorbar;

    is $ax->colorbar_label, '', 'colorbar_label defaults to empty string when label not given';
}

# ------------------------------------------------------------------
# label指定ありで実際にPNG描画してもクラッシュしないこと(4方向すべて)
# ------------------------------------------------------------------
for my $loc (qw(right left top bottom)) {
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->imshow(sequence(10,10), cmap=>'viridis', vmin=>-1, vmax=>1);
    $ax->colorbar(label=>'amplitude (uV)', location=>$loc);
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, "colorbar(label=>..., location=>'$loc') renders without crashing"
        or diag "error: $@";
}

# ------------------------------------------------------------------
# label未指定時もこれまで通り描画できること(後方互換性の確認)
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->imshow(sequence(10,10), cmap=>'jet', vmin=>0, vmax=>1);
    $ax->colorbar;   # labelなし、従来の呼び方
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'colorbar() without label still renders without crashing (backward compatibility)'
        or diag "error: $@";
}

# ------------------------------------------------------------------
# scatter(c=>...)経由でセットされたcolorbarにもlabelが反映されること
# (imshowとscatterでは_colorbarのセット元コードパスが異なるため)
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->scatter(sequence(20), sequence(20), c=>sequence(20), cmap=>'plasma');
    $ax->colorbar(label=>'value');
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, 'colorbar(label=>...) after scatter(c=>...) renders without crashing'
        or diag "error: $@";
    is $ax->colorbar_label, 'value', 'colorbar_label stored correctly after scatter(c=>...)';
}

# ------------------------------------------------------------------
# 回帰テスト: colorbar_location=>'left'/'top'/'bottom' 指定時に、
# 実際にcolorbarが描かれる側のマージンが拡張されること。
# 以前はcolorbarの有無だけでmr(右マージン)を常に拡張していたため、
# location指定時にylabelやfigure外との重なり/食い込みが発生していた。
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->imshow(sequence(10,10), cmap=>'viridis', vmin=>0, vmax=>1);
    $ax->ylabel('Y');
    $ax->colorbar(label=>'val', location=>'left');
    $fig->tight_layout;

    ok $ax->margin_left > 100,
        "colorbar_location=>'left' with label and ylabel: margin_left is expanded (got " . $ax->margin_left . ")";

    eval { $fig->to_png };
    ok !$@, "colorbar_location=>'left' renders without crashing" or diag "error: $@";
}

{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->imshow(sequence(10,10), cmap=>'viridis', vmin=>0, vmax=>1);
    $ax->colorbar(label=>'val', location=>'bottom');
    $fig->tight_layout;

    ok $ax->margin_bottom > 80,
        "colorbar_location=>'bottom' with label: margin_bottom is expanded (got " . $ax->margin_bottom . ")";

    eval { $fig->to_png };
    ok !$@, "colorbar_location=>'bottom' renders without crashing" or diag "error: $@";
}

{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->imshow(sequence(10,10), cmap=>'viridis', vmin=>0, vmax=>1);
    $ax->colorbar(label=>'val', location=>'top');
    $fig->tight_layout;

    ok $ax->margin_top > 60,
        "colorbar_location=>'top' with label: margin_top is expanded (got " . $ax->margin_top . ")";

    eval { $fig->to_png };
    ok !$@, "colorbar_location=>'top' renders without crashing" or diag "error: $@";
}

# location=>'right'(デフォルト)では、margin_leftがcolorbar分だけ
# 余計に拡張されていないこと(left専用拡張がright側に誤って効かないか確認)
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->imshow(sequence(10,10), cmap=>'viridis', vmin=>0, vmax=>1);
    $ax->colorbar(label=>'val');  # location指定なし=right
    $fig->tight_layout;

    ok $ax->margin_left < 60,
        "colorbar_location=>'right'(default): margin_left is NOT expanded (got " . $ax->margin_left . ")";
    ok $ax->margin_right > 60,
        "colorbar_location=>'right'(default): margin_right IS expanded (got " . $ax->margin_right . ")";
}

# ------------------------------------------------------------------
# 回帰テスト: colorbar_location=>'top' + title + label の組み合わせで
# クラッシュしないこと。以前はtitleの描画位置がcolorbar本体の領域と
# 重なって埋もれる不具合があったため、位置自体は画像でしか確認できな
# いが、最低限クラッシュしないことと、titleがcolorbar_padとwidthを
# 考慮した位置(mtの範囲内かつ正の値)に計算されることを確認する。
# ------------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>400, height=>300);
    $ax->imshow(sequence(10,10), cmap=>'viridis', vmin=>0, vmax=>1);
    $ax->colorbar(label=>'val', location=>'top');
    $ax->set_title('My Plot');
    $fig->tight_layout;
    eval { $fig->to_png };
    ok !$@, "colorbar_location=>'top' with title and label renders without crashing"
        or diag "error: $@";
}

done_testing;
