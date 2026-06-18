use strict;
use warnings;
use Test::More;
use PDL;
use PDL::Graphics::Cairo qw(subplots);

# ----------------------------------------------------------------
# uniform_margins => 1 のとき、ylabel/xlabel の有無に関わらず
# グリッド内の全パネルで margin_left / margin_bottom が揃うこと。
# (5x5 EEGグリッドで左列のみylabelを付けると、その列だけプロット幅が
#  狭くなる不具合の回帰テスト)
# ----------------------------------------------------------------
{
    my ($fig, @rows) = subplots(3, 3, width=>600, height=>500);
    for my $r (0..2) {
        for my $c (0..2) {
            $rows[$r][$c]->line(sequence(10), sequence(10));
            $rows[$r][$c]->ylabel('uV') if $c == 0;   # 左列のみylabel
            $rows[$r][$c]->xlabel('s')  if $r == 2;   # 最下行のみxlabel
        }
    }
    $fig->tight_layout(uniform_margins=>1);

    my %ml_set = map { $rows[$_/3][$_%3]->margin_left  => 1 } 0..8;
    my %mb_set = map { $rows[$_/3][$_%3]->margin_bottom => 1 } 0..8;

    is scalar(keys %ml_set), 1,
        'uniform_margins: margin_left is identical across all panels regardless of ylabel placement';
    is scalar(keys %mb_set), 1,
        'uniform_margins: margin_bottom is identical across all panels regardless of xlabel placement';
}

# ----------------------------------------------------------------
# 比較: uniform_margins => 0（デフォルト）では列/行ごとに差が出ること
# （挙動が変わっていないことの確認）
# ----------------------------------------------------------------
{
    my ($fig, @rows) = subplots(3, 3, width=>600, height=>500);
    for my $r (0..2) {
        for my $c (0..2) {
            $rows[$r][$c]->line(sequence(10), sequence(10));
            $rows[$r][$c]->ylabel('uV') if $c == 0;
            $rows[$r][$c]->xlabel('s')  if $r == 2;
        }
    }
    $fig->tight_layout;   # uniform_margins指定なし

    my $ml_col0 = $rows[0][0]->margin_left;
    my $ml_col1 = $rows[0][1]->margin_left;
    isnt $ml_col0, $ml_col1,
        'non-uniform mode: margin_left still differs between ylabel column and others (no regression)';
}

# ----------------------------------------------------------------
# ylabelが一切ないグリッドではuniform_margins有無で結果が変わらないこと
# ----------------------------------------------------------------
{
    my ($fig, @rows) = subplots(2, 2, width=>400, height=>400);
    for my $r (0..1) {
        for my $c (0..1) {
            $rows[$r][$c]->line(sequence(10), sequence(10));
        }
    }
    $fig->tight_layout(uniform_margins=>1);
    eval { $fig->to_png };
    ok !$@, 'uniform_margins grid with no ylabel/xlabel anywhere does not crash'
        or diag "error: $@";
}

# ----------------------------------------------------------------
# uniform_margins => 1 でコンパクトラベルモードが有効になり、
# mt+mb の合計が非uniform時より圧縮されること。
# ----------------------------------------------------------------
{
    my ($fig, @rows) = subplots(3, 3, width=>600, height=>500);
    for my $r (0..2) {
        for my $c (0..2) {
            my $idx = $r*3+$c;
            $rows[$r][$c]->line(sequence(10), sequence(10));
            $rows[$r][$c]->set_title("ch$idx");
            $rows[$r][$c]->xlabel('s');
        }
    }
    $fig->tight_layout(uniform_margins=>1);

    ok $rows[1][1]->_compact_labels,
        'uniform_margins enables compact label mode on each Axes';

    my $mt = $rows[1][1]->margin_top;
    my $mb = $rows[1][1]->margin_bottom;
    ok $mt + $mb < 90,
        "uniform_margins: compact mt+mb total ($mt+$mb=" . ($mt+$mb) . ") is below the old 90px baseline";

    eval { $fig->to_png };
    ok !$@, 'uniform_margins grid with title+xlabel on every panel does not crash'
        or diag "error: $@";
}

# ----------------------------------------------------------------
# uniform_margins を使わない場合はコンパクトモードが無効のまま
# （単一figure表示や既存挙動への影響がないことの確認）
# ----------------------------------------------------------------
{
    my ($fig, $ax) = subplots(1,1, width=>500, height=>350);
    $ax->line(sequence(10), sequence(10));
    $ax->set_title('single');
    $fig->tight_layout;   # uniform_margins指定なし
    ok !$ax->_compact_labels,
        'non-uniform tight_layout leaves compact label mode disabled';
}

done_testing;
