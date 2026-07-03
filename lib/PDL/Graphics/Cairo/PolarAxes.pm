package PDL::Graphics::Cairo::PolarAxes;

# ==================================================================
# PolarAxes — matplotlib ax.set_projection('polar') 相当
# ==================================================================
# 使い方:
#   my ($fig, $ax) = subplots(figsize=>[6,6]);
#   $ax = $fig->add_subplot(1,1,1, projection=>'polar');
#   $ax->plot($theta, $r);   # $theta: ラジアン PDL, $r: 振幅 PDL
#   $ax->set_title('Polar');
#   $fig->tight_layout(); $fig->save('polar.png');
#
# サポートするメソッド:
#   plot($theta, $r, %opt)  — 極座標折れ線
#   scatter($theta, $r, %opt) — 極座標散布図
#   bar($theta, $r, %opt)   — 極座標バー(rose diagram / wind rose)
#   fill($theta, $r, %opt)  — 閉じた領域を塗りつぶす
#   set_rmax($r)            — r軸最大値
#   set_rmin($r)            — r軸最小値 (デフォルト 0)
#   set_rlabel_position($deg) — r軸ラベルの角度(度)
#   set_theta_zero_location($loc) — 'N','E','S','W'
#   set_theta_direction($dir)     — 1(反時計, デフォルト) or -1(時計回り)
#   set_rticks(\@ticks)     — r軸目盛り値
#   set_thetagrids(\@deg)   — θ方向格子線の角度(度)
#   grid(1)                 — 格子を表示
#   legend(%opt)            — 凡例
#   set_title($str)         — タイトル
#   set_facecolor($c)       — 背景色

use strict;
use warnings;
use PDL;
use Moo;
use POSIX qw(floor);
# PDL は min/max をプロトタイプなしでエクスポートしており、List::Util の
# min/max (プロトタイプ '(@)') と名前が衝突して 'Prototype mismatch' 警告
# が出る。本モジュールでは PDL オブジェクトではなくスカラー比較
# (例: min($fw,$fh) でFigureの幅高さ比較)に List::Util 版が必要なため、
# List::Util::min/max を明示的にフルネームで呼び出して警告を避ける。
use List::Util ();

use PDL::Graphics::Cairo::Driver::Cairo;

# Figure から参照される最小限の属性 (Axes 互換)
has width    => (is => 'rw', required => 1);
has height   => (is => 'rw', required => 1);
has fig_x    => (is => 'rw', default  => sub { 0 });
has fig_y    => (is => 'rw', default  => sub { 0 });

# tight_layout から参照されるマージン属性（PolarAxes では使われないが存在が必要）
has margin_left   => (is => 'rw', default => sub { 0 });
has margin_right  => (is => 'rw', default => sub { 0 });
has margin_top    => (is => 'rw', default => sub { 0 });
has margin_bottom => (is => 'rw', default => sub { 0 });

# 凡例/タイトル等の互換属性
has title    => (is => 'rw', default => sub { '' });
has xlabel   => (is => 'rw', default => sub { '' });
has ylabel   => (is => 'rw', default => sub { '' });
has ylabel_rotation => (is => 'rw', default => sub { 90 });

# tight_layout / twin / inset 判定用
has _is_twin    => (is => 'rw', default => sub { 0 });
has _twin_of    => (is => 'rw', default => sub { undef });
has _twin_type  => (is => 'rw', default => sub { undef });
has _twin_ax    => (is => 'rw', default => sub { undef });
has _twin_axes  => (is => 'rw', default => sub { [] });
has _is_inset   => (is => 'rw', default => sub { 0 });
has _compact_labels => (is => 'rw', default => sub { 0 });
has _figure     => (is => 'rw');
has _colorbar   => (is => 'rw');
has _facecolor  => (is => 'rw', default => sub { undef });

# 極座標固有の設定
has _rmax        => (is => 'rw', default => sub { undef });
has _rmin        => (is => 'rw', default => sub { 0 });
has _rlabel_pos  => (is => 'rw', default => sub { 45 });   # degrees
has _theta0_loc  => (is => 'rw', default => sub { 'E'  }); # 0=東(右)
has _theta_dir   => (is => 'rw', default => sub { 1    }); # 1=反時計, -1=時計
has _rticks      => (is => 'rw', default => sub { undef });
has _thetagrids  => (is => 'rw', default => sub { undef });
has _grid_on     => (is => 'rw', default => sub { 1 });
has _queue       => (is => 'ro', default => sub { [] });
has _legends     => (is => 'ro', default => sub { [] });
has _show_legend => (is => 'rw', default => sub { 0 });
has _legend_loc  => (is => 'rw', default => sub { 'upper right' });
has _color_idx   => (is => 'rw', default => sub { 0 });

# ==================================================================
# 設定メソッド
# ==================================================================
sub set_rmax             { my ($s,$v)=@_; $s->_rmax($v); $s }
sub set_rmin             { my ($s,$v)=@_; $s->_rmin($v); $s }
sub set_rlabel_position  { my ($s,$v)=@_; $s->_rlabel_pos($v); $s }
sub set_theta_zero_location {
    my ($self, $loc) = @_;
    # 'N','E','S','W' を受け付ける
    $self->_theta0_loc(uc($loc // 'E'));
    return $self;
}
sub set_theta_direction  { my ($s,$d)=@_; $s->_theta_dir($d); $s }
sub set_rticks           { my ($s,$t)=@_; $s->_rticks($t); $s }
sub set_thetagrids       { my ($s,$g)=@_; $s->_thetagrids($g); $s }
sub grid                 { my ($s,$on)=@_; $s->_grid_on($on//1); $s }
sub legend               { my ($s,%o)=@_; $s->_show_legend(1); $s->_legend_loc($o{loc}//'upper right'); $s }
sub set_title            { my ($s,$t,%o)=@_; $s->title($t); $s }
sub set_xlabel           { my ($s,$t,%o)=@_; $s->xlabel($t); $s }
sub set_ylabel           { my ($s,$t,%o)=@_; $s->ylabel($t); $s }
sub set_facecolor        { my ($s,$c)=@_; $s->_facecolor($c); $s }

# ==================================================================
# データプロット
# ==================================================================
sub _next_color {
    my ($self) = @_;
    my $cycle = $PDL::Graphics::Cairo::_RCPARAMS{_color_cycle};
    my @colors = ($cycle && ref($cycle) eq 'ARRAY' && @$cycle)
        ? @$cycle
        : ([0.122,0.467,0.706],[1.000,0.498,0.055],[0.173,0.627,0.173],
           [0.839,0.153,0.157],[0.580,0.404,0.741],[0.549,0.337,0.294]);
    my $c = $colors[$self->_color_idx % scalar @colors];
    $self->_color_idx($self->_color_idx + 1);
    return ref($c) ? $c : _parse_color_str($c);
}

sub _parse_color_str {
    my ($c) = @_;
    return $c if ref($c) eq 'ARRAY';
    if ($c =~ /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i) {
        return [hex($1)/255, hex($2)/255, hex($3)/255];
    }
    return [0,0,0];
}

sub _parse_color {
    my ($self, $c) = @_;
    return _parse_color_str($c);
}

# plot($theta_pdl, $r_pdl, %opt)
sub plot {
    my ($self, $theta, $r, %opt) = @_;
    $theta = pdl($theta) unless ref($theta) && $theta->isa('PDL');
    $r     = pdl($r)     unless ref($r)     && $r->isa('PDL');
    my $color = exists $opt{color}
        ? $self->_parse_color($opt{color}) : $self->_next_color();
    push @{ $self->_queue }, {
        type   => 'polar_line',
        theta  => $theta, r => $r,
        color  => $color,
        lw     => $opt{linewidth} // $opt{lw} // 1.5,
        ls     => $opt{linestyle} // 'solid',
        alpha  => $opt{alpha} // 1.0,
        label  => $opt{label} // undef,
        marker => $opt{marker} // undef,
        ms     => $opt{markersize} // 4,
        fill   => (($opt{fillstyle}//'full') eq 'none') ? 0 : 1,
    };
    $self->_update_rmax($r);
    if (defined $opt{label}) {
        push @{ $self->_legends }, {
            type => 'line', color => $color,
            label => $opt{label}, lw => $opt{linewidth}//1.5,
        };
    }
    return $self;
}
sub line { goto &plot }

# scatter($theta_pdl, $r_pdl, %opt)
sub scatter {
    my ($self, $theta, $r, %opt) = @_;
    $theta = pdl($theta) unless ref($theta) && $theta->isa('PDL');
    $r     = pdl($r)     unless ref($r)     && $r->isa('PDL');
    my $color = exists $opt{color}
        ? $self->_parse_color($opt{color}) : $self->_next_color();
    push @{ $self->_queue }, {
        type   => 'polar_scatter',
        theta  => $theta, r => $r,
        color  => $color,
        size   => $opt{s} // $opt{size} // 4,
        marker => $opt{marker} // 'o',
        alpha  => $opt{alpha} // 0.8,
        label  => $opt{label} // undef,
        fill   => (($opt{fillstyle}//'full') eq 'none') ? 0 : 1,
    };
    $self->_update_rmax($r);
    if (defined $opt{label}) {
        push @{ $self->_legends }, {
            type => 'marker', color => $color,
            label => $opt{label}, marker => $opt{marker}//'o',
        };
    }
    return $self;
}

# bar($theta, $r, %opt) — Rose diagram / Polar bar
# $theta: 各バーの中心角(ラジアン), $r: 各バーの高さ
sub bar {
    my ($self, $theta, $r, %opt) = @_;
    $theta = pdl($theta) unless ref($theta) && $theta->isa('PDL');
    $r     = pdl($r)     unless ref($r)     && $r->isa('PDL');
    my $color = exists $opt{color}
        ? $self->_parse_color($opt{color}) : $self->_next_color();
    my $width = $opt{width} // (2 * 3.14159265358979 / $theta->nelem);

    # bottom: スカラー(全方位共通の底辺)または PDL配列(方位ごとに異なる
    # 積み上げ底辺、matplotlib の stacked bar 相当)の両方を受け付ける。
    # 積み上げ時、r は「そのビンの相対的な大きさ」であり、実際に描く
    # 棒の絶対的な上端は bottom + r になる(下のbottom配列がスカラー0の
    # 場合は単純化されて r と同じになる)。
    my $bottom_raw = $opt{bottom} // 0;
    my $bottom = (ref($bottom_raw) && $bottom_raw->isa('PDL'))
        ? $bottom_raw
        : (ones($theta->nelem) * $bottom_raw);   # スカラー → 全要素同値のPDLに展開

    push @{ $self->_queue }, {
        type   => 'polar_bar',
        theta  => $theta, r => $r,
        width  => $width,
        bottom => $bottom,
        color  => $color,
        alpha  => $opt{alpha}  // 0.8,
        label  => $opt{label}  // undef,
    };
    $self->_update_rmax($bottom + $r);   # 積み上げ時は底辺+高さがrmaxになる
    if (defined $opt{label}) {
        push @{ $self->_legends }, {
            type => 'rect', color => $color, label => $opt{label},
        };
    }
    return $self;
}

# fill($theta, $r, %opt) — 閉じた塗りつぶし領域
sub fill {
    my ($self, $theta, $r, %opt) = @_;
    $theta = pdl($theta) unless ref($theta) && $theta->isa('PDL');
    $r     = pdl($r)     unless ref($r)     && $r->isa('PDL');
    my $color = exists $opt{color}
        ? $self->_parse_color($opt{color}) : $self->_next_color();
    push @{ $self->_queue }, {
        type  => 'polar_fill',
        theta => $theta, r => $r,
        color => $color,
        alpha => $opt{alpha} // 0.3,
        label => $opt{label} // undef,
    };
    $self->_update_rmax($r);
    return $self;
}

sub _update_rmax {
    my ($self, $r) = @_;
    my $mx = $r->max;
    if (!defined $self->_rmax || $mx > $self->_rmax) {
        $self->_rmax($mx);
    }
}

# ==================================================================
# draw($backend) — Figure::_render_to から呼ばれる
# ==================================================================
sub draw {
    my ($self, $b) = @_;

    my $fw = $self->width;
    my $fh = $self->height;
    my $fx = $self->fig_x;
    my $fy = $self->fig_y;

    # 極座標軸は正方形の円盤として描く
    # 円の中心とサイズを決定
    my $pad = 48;   # ラベル・目盛り用余白
    my $cx  = $fx + $fw / 2;
    my $cy  = $fy + $fh / 2;
    my $rad = List::Util::min($fw, $fh) / 2 - $pad;  # 円の半径 (px)
    return if $rad < 10;

    # r軸範囲
    my $rmin  = $self->_rmin // 0;
    my $rmax  = $self->_rmax // 1;
    $rmax     = 1 if $rmax <= $rmin;

    # r目盛り
    my @rticks = $self->_rticks ? @{$self->_rticks} : _nice_rticks($rmin, $rmax, 4);

    # θ目盛り (度)
    my @thetagrids = $self->_thetagrids
        ? @{$self->_thetagrids}
        : (0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330);

    # θ0 オフセット (ラジアン) — 0度の位置
    my $t0_offset = _theta0_offset($self->_theta0_loc);

    # ====================
    # 背景色
    # ====================
    my $fc = $self->_facecolor;
    unless (defined $fc) {
        my $rcp = $PDL::Graphics::Cairo::_RCPARAMS{'axes.facecolor'} // 'white';
        $fc = _parse_color_str($rcp) unless $rcp eq 'white';
    }
    if (defined $fc) {
        $b->set_color(@$fc, 1.0);
        _draw_filled_circle($b, $cx, $cy, $rad);
        $b->set_color(0,0,0,1.0);
    }

    # ====================
    # 格子線 (r 同心円、θ 放射線)
    # ====================
    if ($self->_grid_on) {
        $b->set_color(0.7, 0.7, 0.7, 1.0);
        $b->set_linewidth(0.5);

        # r同心円
        for my $rt (@rticks) {
            my $rp = _r2px($rt, $rmin, $rmax, $rad);
            next if $rp <= 0;
            _draw_circle($b, $cx, $cy, $rp);
        }

        # θ放射線
        for my $tdeg (@thetagrids) {
            my $tr = _theta_to_screen($tdeg * 3.14159265358979 / 180,
                                      $t0_offset, $self->_theta_dir);
            my $ex = $cx + $rad * cos($tr);
            my $ey = $cy - $rad * sin($tr);  # y軸反転
            $b->line_seg($cx, $cy, $ex, $ey);
        }
        $b->set_color(0,0,0,1.0);
        $b->set_linewidth(1.5);
    }

    # 外周の円
    $b->set_color(0,0,0,1.0);
    $b->set_linewidth(1.0);
    _draw_circle($b, $cx, $cy, $rad);

    # ====================
    # データ描画
    # ====================
    for my $cmd (@{ $self->_queue }) {
        $self->_render_polar_cmd($b, $cmd, $cx, $cy, $rad, $rmin, $rmax,
                                 $t0_offset, $self->_theta_dir);
    }

    # ====================
    # r軸目盛りラベル
    # ====================
    {
        my $lpos_rad = _theta_to_screen(
            $self->_rlabel_pos * 3.14159265358979 / 180,
            $t0_offset, $self->_theta_dir
        );
        $b->set_color(0.3,0.3,0.3,1.0);
        $b->set_font(size => 8);
        for my $rt (@rticks) {
            next if $rt == $rmin;
            my $rp = _r2px($rt, $rmin, $rmax, $rad);
            next if $rp <= 0;
            my $lx = $cx + $rp * cos($lpos_rad);
            my $ly = $cy - $rp * sin($lpos_rad);
            my $lstr = _fmt_tick($rt);
            $b->text($lx+2, $ly-2, $lstr, align=>'left', valign=>'bottom');
        }
    }

    # ====================
    # θ目盛りラベル
    # ====================
    {
        $b->set_color(0,0,0,1.0);
        $b->set_font(size => 9);
        for my $tdeg (@thetagrids) {
            my $tr = _theta_to_screen($tdeg * 3.14159265358979 / 180,
                                      $t0_offset, $self->_theta_dir);
            my $ex = $cx + ($rad + 16) * cos($tr);
            my $ey = $cy - ($rad + 16) * sin($tr);
            $b->text($ex, $ey, "${tdeg}°",
                align  => 'center',
                valign => 'middle');
        }
    }

    # ====================
    # タイトル
    # ====================
    if ($self->title ne '') {
        $b->set_color(0,0,0,1.0);
        $b->set_font(size => 12, weight => 'bold');
        $b->text($cx, $fy + 14, $self->title,
            align => 'center', valign => 'top');
        $b->set_font(size => 11, weight => 'normal');
    }

    # ====================
    # 凡例
    # ====================
    if ($self->_show_legend && @{ $self->_legends }) {
        $self->_draw_polar_legend($b, $fx, $fy, $fw, $fh);
    }
}

# ==================================================================
# 各描画コマンドの実行
# ==================================================================
sub _render_polar_cmd {
    my ($self, $b, $cmd, $cx, $cy, $rad, $rmin, $rmax, $t0, $tdir) = @_;
    my $type = $cmd->{type};

    if ($type eq 'polar_line') {
        my @theta = list($cmd->{theta});
        my @r     = list($cmd->{r});
        my (@px, @py);
        for my $i (0..$#theta) {
            my $tr = _theta_to_screen($theta[$i], $t0, $tdir);
            my $rp = _r2px($r[$i], $rmin, $rmax, $rad);
            push @px, $cx + $rp * cos($tr);
            push @py, $cy - $rp * sin($tr);
        }
        $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
        $b->set_linewidth($cmd->{lw});
        $b->set_linestyle($cmd->{ls}, $cmd->{lw});
        $b->polyline(pdl(@px), pdl(@py));
        $b->set_linestyle('solid');
        if (defined $cmd->{marker}) {
            $b->set_linewidth(0.8);
            for my $i (0..$#px) {
                $b->marker($px[$i], $py[$i], $cmd->{ms}, $cmd->{marker}, $cmd->{fill}//1);
            }
        }
    }
    elsif ($type eq 'polar_scatter') {
        $b->set_linewidth(0.5);
        my @theta = list($cmd->{theta});
        my @r     = list($cmd->{r});
        for my $i (0..$#theta) {
            my $tr = _theta_to_screen($theta[$i], $t0, $tdir);
            my $rp = _r2px($r[$i], $rmin, $rmax, $rad);
            my $px = $cx + $rp * cos($tr);
            my $py = $cy - $rp * sin($tr);
            $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
            my $radius = sqrt($cmd->{size} / 3.14159265) || 1;
            $b->marker($px, $py, $radius, $cmd->{marker}, $cmd->{fill}//1);
        }
    }
    elsif ($type eq 'polar_bar') {
        my @theta = list($cmd->{theta});
        my @r     = list($cmd->{r});
        # bottom は bar() で常に PDL配列(方位ごとの底辺値)として渡される。
        # 積み上げ時(stacked bar)、実際に描く棒の絶対上端は bottom[i] + r[i]。
        my @bot   = list($cmd->{bottom});
        my $hw = $cmd->{width} / 2;
        $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
        for my $i (0..$#theta) {
            my $t_center = _theta_to_screen($theta[$i], $t0, $tdir);
            my $t1 = $t_center - $hw * $tdir;
            my $t2 = $t_center + $hw * $tdir;
            my $bot_i = $bot[$i] // 0;
            my $top_i = $bot_i + $r[$i];
            my $r0 = _r2px($bot_i, $rmin, $rmax, $rad);
            my $r1 = _r2px($top_i, $rmin, $rmax, $rad);
            next if $r1 <= $r0;
            _draw_wedge($b, $cx, $cy, $r0, $r1, $t1, $t2);
        }
    }
    elsif ($type eq 'polar_fill') {
        my @theta = list($cmd->{theta});
        my @r     = list($cmd->{r});
        my (@px, @py);
        for my $i (0..$#theta) {
            my $tr = _theta_to_screen($theta[$i], $t0, $tdir);
            my $rp = _r2px($r[$i], $rmin, $rmax, $rad);
            push @px, $cx + $rp * cos($tr);
            push @py, $cy - $rp * sin($tr);
        }
        $b->set_color(@{$cmd->{color}}, $cmd->{alpha});
        $b->filled_polygon(pdl(@px), pdl(@py));
    }
}

# ==================================================================
# 凡例描画（Axes._draw_legend と同様のロジック）
# ==================================================================
sub _draw_polar_legend {
    my ($self, $b, $fx, $fy, $fw, $fh) = @_;
    my @legs = grep { defined $_->{label} } @{ $self->_legends };
    return unless @legs;
    my $fs  = 9;
    my $lh  = 18;
    my $pad = 6;
    my $pw  = 24;
    my $box_h = @legs * $lh + $pad;
    my $box_w = 120;
    my $lx = $fx + $fw - $box_w - 8;
    my $ly = $fy + 8;
    $b->set_color(1,1,1,0.85);
    $b->rect_fill($lx, $ly, $box_w, $box_h);
    $b->set_color(0.6,0.6,0.6);
    $b->set_linewidth(1.0);
    $b->rect_stroke($lx, $ly, $box_w, $box_h);
    for my $i (0..$#legs) {
        my $lg = $legs[$i];
        my $y0 = $ly + $pad/2 + $i*$lh + $lh/2;
        my $x0 = $lx + $pad;
        $b->set_color(@{$lg->{color}});
        if ($lg->{type} eq 'line') {
            $b->set_linewidth($lg->{lw}//1.5);
            $b->line_seg($x0, $y0, $x0+$pw, $y0);
        } elsif ($lg->{type} eq 'marker') {
            $b->marker($x0+$pw/2, $y0, 4, $lg->{marker}//'o', 1);
        } elsif ($lg->{type} eq 'rect') {
            $b->rect_fill($x0, $y0-5, $pw, 10);
        }
        $b->set_color(0,0,0);
        $b->set_font(size => $fs);
        $b->text($x0+$pw+$pad, $y0, $lg->{label}, align=>'left', valign=>'middle');
    }
}

# ==================================================================
# 内部ユーティリティ
# ==================================================================

# θ軸の0度位置オフセット(ラジアン)
sub _theta0_offset {
    my ($loc) = @_;
    return 0         if $loc eq 'E';   # 右
    return 3.14159265358979 / 2        if $loc eq 'N';   # 上
    return 3.14159265358979            if $loc eq 'W';   # 左
    return 3 * 3.14159265358979 / 2   if $loc eq 'S';   # 下
    return 0;
}

# データ角度 → 画面角度変換
sub _theta_to_screen {
    my ($theta, $t0_offset, $tdir) = @_;
    # tdir=1: 反時計回り (標準数学), tdir=-1: 時計回り (方位角等)
    return $t0_offset + $tdir * $theta;
}

# r値 → 画面ピクセル半径
sub _r2px {
    my ($r, $rmin, $rmax, $rad) = @_;
    return 0 if $rmax <= $rmin;
    my $t = ($r - $rmin) / ($rmax - $rmin);
    return $t * $rad;
}

# 円を描く（塗りなし）
sub _draw_circle {
    my ($b, $cx, $cy, $r) = @_;
    my $cr = $b->{cr};
    $cr->arc($cx, $cy, $r, 0, 2*3.14159265358979);
    $cr->stroke;
}

# 塗りつぶし円
sub _draw_filled_circle {
    my ($b, $cx, $cy, $r) = @_;
    my $cr = $b->{cr};
    $cr->arc($cx, $cy, $r, 0, 2*3.14159265358979);
    $cr->fill;
}

# ウェッジ（扇形）を描く（polar bar用）
sub _draw_wedge {
    my ($b, $cx, $cy, $r0, $r1, $t1, $t2) = @_;
    my $cr = $b->{cr};
    my $pi = 3.14159265358979;
    # 内弧始点
    my ($x0, $y0) = ($cx + $r0 * cos($t1), $cy - $r0 * sin($t1));
    $cr->move_to($x0, $y0);
    # 外弧（t1→t2）
    if ($t2 > $t1) {
        $cr->arc($cx, $cy, $r1, -$t1, -$t2);      # Cairoはy下向きなのでマイナス
    } else {
        $cr->arc_negative($cx, $cy, $r1, -$t1, -$t2);
    }
    # 内弧（t2→t1）逆順
    if ($t2 > $t1) {
        $cr->arc_negative($cx, $cy, $r0, -$t2, -$t1);
    } else {
        $cr->arc($cx, $cy, $r0, -$t2, -$t1);
    }
    $cr->close_path;
    $cr->fill_preserve;
    $cr->set_source_rgba(0,0,0,0.3);
    $cr->set_line_width(0.5);
    $cr->stroke;
}

# 数値フォーマット
sub _fmt_tick {
    my ($v) = @_;
    return '0' if $v == 0;
    return sprintf('%g', $v);
}

# r軸のきれいな目盛り値を生成
sub _nice_rticks {
    my ($rmin, $rmax, $n) = @_;
    $n //= 4;
    my $range = $rmax - $rmin;
    return ($rmax) if $range <= 0;
    my $step = $range / $n;
    my $mag  = 10 ** floor(log($step)/log(10));
    my $nice_step = $mag * (int($step/$mag) || 1);
    $nice_step = $mag if $nice_step <= 0;
    my @ticks;
    my $v = $rmin;
    while ($v <= $rmax * 1.001) {
        push @ticks, $v if $v > $rmin;
        $v += $nice_step;
    }
    return @ticks ? @ticks : ($rmax);
}

1;

__END__

=head1 NAME

PDL::Graphics::Cairo::PolarAxes — 極座標プロット (matplotlib polar projection 相当)

=head1 SYNOPSIS

  use PDL;
  use PDL::Graphics::Cairo qw(figure);

  my $theta = sequence(100) / 100 * 2 * 3.14159;
  my $r     = sin(2*$theta)**2;

  my $fig = figure(width=>600, height=>600);
  my $ax  = $fig->add_subplot(1,1,1, projection=>'polar');
  $ax->plot($theta, $r, color=>'steelblue', lw=>2, label=>'sin²(2θ)');
  $ax->set_title('Rose Curve');
  $ax->legend();
  $fig->tight_layout();
  $fig->save('polar.png');

=head1 METHODS

=head2 plot($theta, $r, %opt)

Polar line plot. C<$theta> in radians.

=head2 scatter($theta, $r, %opt)

Polar scatter plot.

=head2 bar($theta, $r, %opt)

Rose diagram / wind rose bar chart.

=head2 fill($theta, $r, %opt)

Filled polar region.

=head2 set_theta_zero_location($loc)

Set the location of the 0° angle: C<'N'>, C<'E'> (default), C<'S'>, C<'W'>.

=head2 set_theta_direction($dir)

C<1> = counterclockwise (default, mathematical). C<-1> = clockwise (compass/bearing).

=head2 set_rmax($r)

Set maximum radius.

=head2 set_rticks(\@ticks)

Specify r-axis tick values.

=head2 set_thetagrids(\@degrees)

Specify angular gridline positions in degrees.

=cut
