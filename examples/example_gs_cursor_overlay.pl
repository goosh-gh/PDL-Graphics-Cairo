#!/usr/bin/env perl
# P:G:C09 段階A デモ — cursor_overlay で座標テキストを自動表示
#
# cursor_overlay => 1 を指定すると、マウス移動/クリック時に自動再描画され、
# render コールバックの $state に以下のキーが入る:
#   _cursor_x, _cursor_y  ... データ座標（プロット枠外なら undef）
#   _cursor_fx, _cursor_fy ... 画像分率 (0..1)
#   _cursor_type          ... 'cursor' (移動) or 'pick' (クリック)
#   _cursor_btn           ... ボタン番号
#
# 変換は Axes->image_frac_to_data() が担当するため、
# 呼び出し側がマージンや xlim/ylim を知る必要はない（Prima超えポイント）。

use strict; use warnings;
use PDL;
use PDL::Graphics::Cairo qw(figure subplots);
use PDL::Graphics::Cairo::Driver::GS;

# --- データ ---
my $x = sequence(100) / 10;    # 0..10
my $y = sin($x) * exp(-$x/8);  # damped sine

# --- render コールバック ---
my $render = sub {
    my ($state, $w, $h) = @_;
    my ($fig, $ax) = subplots(1, 1, width => $w, height => $h);

    $ax->line($x, $y, color => 'steelblue', lw => 2);
    $ax->xlim(0, 10);
    $ax->ylim(-1.1, 1.1);
    $ax->set_xlabel('x');
    $ax->set_ylabel('y');
    $ax->set_title('cursor_overlay デモ — マウスを動かすと座標が表示される');

    # --- 座標テキストオーバーレイ ---
    if (defined $state->{_cursor_x}) {
        my ($cx, $cy) = ($state->{_cursor_x}, $state->{_cursor_y});
        my $type = $state->{_cursor_type} // 'cursor';
        my $label = sprintf("%s  x=%.3f  y=%.4f",
            ($type eq 'pick' ? 'PICK' : 'cursor'), $cx, $cy);
        # プロット枠内・左上（データ座標で xmin+5%, ymax-5% 付近）に描画
        $ax->text(0.3, 0.95, $label,
            ha => 'left', va => 'top',
            fontsize => 11, color => ($type eq 'pick' ? 'red' : 'darkgreen'));

        # PICK の場合は最近傍点をハイライト
        if ($type eq 'pick') {
            my $dist2 = ($x - $cx)**2 + ($y - $cy)**2;
            my $i     = $dist2->minimum_ind->sclr;
            $ax->scatter(pdl($x->at($i)), pdl($y->at($i)),
                color => 'red', s => 80, zorder => 5);
            my $near_label = sprintf("(%.3f, %.4f)", $x->at($i), $y->at($i));
            $ax->text($x->at($i), $y->at($i) + 0.08, $near_label,
                ha => 'center', va => 'bottom', fontsize => 9, color => 'red');
        }
    } elsif (defined $state->{_cursor_fx}) {
        # プロット枠外: frac を表示
        $ax->text(0.3, 0.95,
            sprintf("枠外  fx=%.3f fy=%.3f",
                $state->{_cursor_fx}, $state->{_cursor_fy}),
            ha => 'left', va => 'top',
            fontsize => 11, color => 'gray');
    }

    $fig->tight_layout;
    return $fig;
};

# --- インタラクティブ起動 ---
my $drv = PDL::Graphics::Cairo::Driver::GS->new(
    width  => 800,
    height => 500,
    title  => 'P:G:C09 cursor_overlay',
);

print "マウスを動かすと座標が表示されます。クリックで最近傍点をハイライト。\n";
print "ウィンドウを閉じると終了します。\n";

$drv->show_interactive(
    render         => $render,
    cursor_overlay => 1,
    # 追加コールバック（端末出力）
    on_cursor => sub {
        my ($fx, $fy) = @_;
        # 端末にはfracだけ表示（データ座標はrender内で取り出す）
        printf "\r  frac=(%.3f, %.3f)   ", $fx, $fy;
    },
    on_pick => sub {
        my ($fx, $fy, $btn) = @_;
        printf "\nPICK btn=%d frac=(%.3f, %.3f)\n", $btn, $fx, $fy;
    },
);
