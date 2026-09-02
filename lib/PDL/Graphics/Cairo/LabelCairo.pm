package PDL::Graphics::Cairo::LabelCairo;
# ============================================================================
# PDL::Graphics::Cairo::LabelCairo
#   電極ラベルの Helvetica アウトラインを cairo(text_path)で取り、
#   LabelGeom(検証済み・PDL 非依存)へ渡して「焼き込み塗り面テキスト」の
#   world 三角(scene->{labels3d})を作る。
#
#   ※ 本モジュールは cairo(Perl Cairo バインディング)と Helvetica フォントに
#     依存するため、ヘッドレス CI では検証していない(Mac 実機で確認する層)。
#     三角化・配置・OBJ/USDA 出力側(LabelGeom / SceneExport)は検証済み。
#
#   giza-server はラベルを画面 2D に貼る(常に正面=ビルボード)。静的ファイルは
#   ビルボードを保持できないので、エクスポート時のカメラ基底(right,up)へ
#   焼き込む=その角度では画面と一致、回すとモデルと一緒に回る。
# ============================================================================
use strict;
use warnings;
use Carp;
use PDL::Graphics::Cairo::LabelGeom qw(tessellate_text billboard_tris);


# ----------------------------------------------------------------------------
# text_to_contours($text, %opt) -> \@contours
#   cairo で $text を "Helvetica" の塗りパスにし、平坦化して閉輪郭の配列へ。
#   輪郭 = [[x,y],...](y-up・mm)。opt: font(既定 Helvetica), size_mm(既定 6)。
#   セット(outer/hole の判定)は LabelGeom::tessellate_text が包含関係で行う。
# ----------------------------------------------------------------------------
sub text_to_contours {
    my ($text, %opt) = @_;
    require Cairo;
    my $font = $opt{font}    // 'Helvetica';
    my $size = $opt{size_mm} // 6;

    my $surf = Cairo::ImageSurface->create('argb32', 4, 4);
    my $cr   = Cairo::Context->create($surf);
    $cr->select_font_face($font, 'normal', 'normal');
    $cr->set_font_size($size);

    # 水平センタリング用に幅を測る(anchor=center 時に使用)。
    my $ext = $cr->text_extents($text);
    my $w   = $ext->{width};

    $cr->new_path;
    $cr->move_to(0, 0);
    $cr->text_path($text);
    my $path = $cr->copy_path_flat;    # ベジエ → 線分に平坦化

    # Perl Cairo の path は要素 { type, points } の配列(バインディングにより
    # $path 直下 or $path->{path})。両対応で取り出す。
    my $segs = (ref $path eq 'HASH' && $path->{path}) ? $path->{path} : $path;

    my (@contours, @cur);
    for my $seg (@$segs) {
        my $type = $seg->{type};
        my $pts  = $seg->{points} || [];
        if ($type eq 'move-to') {
            push @contours, [@cur] if @cur >= 3;
            @cur = ([ $pts->[0][0], -$pts->[0][1] ]);   # cairo は y 下向き → 反転
        }
        elsif ($type eq 'line-to') {
            push @cur, [ $pts->[0][0], -$pts->[0][1] ];
        }
        elsif ($type eq 'close-path') {
            push @contours, [@cur] if @cur >= 3;
            @cur = ();
        }
        # 'curve-to' は copy_path_flat では出ない
    }
    push @contours, [@cur] if @cur >= 3;

    return { contours => \@contours, width => $w, height => $ext->{height} };
}

# ---- 小さなベクトル演算(radial 配置用) ----
sub _sub3  { my($a,$b)=@_; [ $a->[0]-$b->[0], $a->[1]-$b->[1], $a->[2]-$b->[2] ] }
sub _add3  { my($a,$b)=@_; [ $a->[0]+$b->[0], $a->[1]+$b->[1], $a->[2]+$b->[2] ] }
sub _scale { my($v,$s)=@_; [ $v->[0]*$s, $v->[1]*$s, $v->[2]*$s ] }
sub _len   { my($v)=@_; sqrt($v->[0]**2+$v->[1]**2+$v->[2]**2) }
sub _norm  { my($v)=@_; my $l=_len($v)||1e-9; [ $v->[0]/$l, $v->[1]/$l, $v->[2]/$l ] }
sub _cross { my($a,$b)=@_;
    [ $a->[1]*$b->[2]-$a->[2]*$b->[1],
      $a->[2]*$b->[0]-$a->[0]*$b->[2],
      $a->[0]*$b->[1]-$a->[1]*$b->[0] ] }

# ----------------------------------------------------------------------------
# electrode_labels_to_geom(%args) -> \@labels3d   ([{ tris=>..., color=>... }])
#   %args:
#     labels => \@str          電極ラベル(scene->{labels})
#     points => \@[x,y,z]      電極 world 座標(mm)。labels と同順・同数
#     right  => [rx,ry,rz]     カメラ基底(単位・直交)。GS3D の現在回転から
#     up     => [ux,uy,uz]
#     size_mm=> 6              文字の大きさ(cap 目安)
#     color  => [1,1,0.78]     ラベル色(giza の 255,255,200 相当)
#     font   => 'Helvetica'
#     anchor => 'center'       'center' | 'left'
#     off_r  => 0, off_u => 0  電極からの平面内オフセット(mm。right/up 方向)
#   各ラベルを個別 tessellate → billboard 配置して labels3d を作る。
# ----------------------------------------------------------------------------
sub electrode_labels_to_geom {
    my (%a) = @_;
    my $labels = $a{labels} or croak "labels required";
    my $points = $a{points} or croak "points required";
    my $size   = $a{size_mm}    // 8;
    my $color  = $a{color}      // [1, 1, 0.78];
    my $font   = $a{font}       // 'Helvetica';
    my $mode   = $a{mode}       // 'radial';   # 'radial'(既定) | 'camera'
    my $offout = $a{offset_out} // 6;          # 表面から外向きに浮かせる mm
    my $center = $a{center};
    my ($cR, $cU) = ($a{right}, $a{up});       # camera モード用の固定基底

    # radial: center 未指定なら電極重心を頭中心とみなす
    if ($mode eq 'radial' && !$center) {
        my @c = (0,0,0); my $n = 0;
        for my $p (@$points) { next unless $p;
            $c[0]+=$p->[0]; $c[1]+=$p->[1]; $c[2]+=$p->[2]; $n++; }
        $center = $n ? [ $c[0]/$n, $c[1]/$n, $c[2]/$n ] : [0,0,0];
    }

    my @out;
    for my $i (0 .. $#$labels) {
        my $text = $labels->[$i];
        next unless defined $text && length $text;
        my $p = $points->[$i] or next;

        my $r = text_to_contours($text, font => $font, size_mm => $size);
        my $contours = $r->{contours};
        next unless @$contours;

        my ($origin, $right, $up);
        if ($mode eq 'camera' && $cR && $cU) {
            # エクスポート時のカメラ平面に貼る(その角度で giza と一致)。
            ($right, $up, $origin) = ($cR, $cU, $p);
        } else {
            # 各電極から外向きに向いた面(頭中心 → 電極 = 外向き法線)。
            # up は MNI +Z を基準に面内へ。表面から offset_out だけ浮かせる。
            my $n  = _norm(_sub3($p, $center));
            my $u0 = [0,0,1];
            my $rr = _cross($u0, $n);
            if (_len($rr) < 1e-6) { $u0 = [0,1,0]; $rr = _cross($u0, $n); } # 極付近の縮退回避
            $right  = _norm($rr);
            $up     = _norm(_cross($n, $right));
            $origin = _add3($p, _scale($n, $offout));
        }

        # 水平・垂直センタリング(電極の外側に文字の中心が来るように)
        my $dx = -$r->{width}  / 2;
        my $dy = -$r->{height} / 2;
        my @shifted = map {
            [ map { [ $_->[0] + $dx, $_->[1] + $dy ] } @$_ ]
        } @$contours;

        my $tris2d = tessellate_text(\@shifted);
        next unless @$tris2d;
        push @out, { tris => billboard_tris($tris2d, $origin, $right, $up), color => $color };
    }
    return \@out;
}

1;

__END__

=encoding utf-8

=head1 GS3D への組み込み(opt-in・export 経路を壊さない)

Driver::GS3D の _export_scene で、書き出し直前に(fine 化の後)以下を行う。
$self->{export_labels} が真のときだけ動き、失敗しても eval で握って
mesh+電極の書き出しは必ず通す(ラベルが出ないだけ)。

    if ($self->{export_labels} && $self->{scene}{labels} && $self->{scene}{points}) {
        eval {
            require PDL::Graphics::Cairo::LabelCairo;

            # --- エクスポート時のカメラ基底(現在の回転 $rot から) ---
            # 画面 +x に対応する world 方向 = right、画面 +y(上) = up。
            # 投影の符号規約は実機で1度だけ確認し、鏡像/上下逆なら符号反転。
            my $rot = $self->{rot};                 # 3x3 回転(PDL)
            my @R = $rot->slice("(0),:")->list;     # row0 -> right
            my @U = $rot->slice("(1),:")->list;     # row1 -> up(必要なら map { -$_ })

            my @pts = map { [ $self->{scene}{points}->slice(":,($_)")->list ] }
                      0 .. $self->{scene}{points}->dim(1)-1;   # [x,y,z] の配列へ

            $self->{scene}{labels3d} = PDL::Graphics::Cairo::LabelCairo::electrode_labels_to_geom(
                labels  => $self->{scene}{labels},
                points  => \@pts,
                right   => \@R,
                up      => \@U,
                size_mm => $self->{export_label_size} // 6,
                color   => [1, 1, 0.78],
            );
            1;
        } or warn "[GS3D export] label geom skipped: $@";
    }

実機で確認する2点:
  (1) select_font_face('Helvetica') が実際に Helvetica に解決されるか
      (cairo が fontconfig 経由だと代替になることがある。CoreText/quartz
      バックエンドならそのまま)。
  (2) 文字が鏡像/上下逆でないか。逆なら up を map { -$_ } @U、または
      right を反転(投影の符号規約に合わせる)。

points の取り出し方($scene->{points} の軸順)は実データに合わせて微調整。
verts と同じ (N,3) なら上の slice(":,($_)") で [x,y,z] になる。

=cut
