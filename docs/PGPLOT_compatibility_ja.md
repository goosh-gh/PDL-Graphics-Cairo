# PDL::Graphics::Cairo::PGPLOT 互換レイヤー — 実装状況

## 概要

`PDL::Graphics::Cairo::PGPLOT` は既存の PGPLOT コードを
PDL::Graphics::Cairo（Cairo/Pango ベース）で描画するための互換レイヤーです。
libgiza / X11 なしで PNG・PDF・SVG 出力および macOS ネイティブウィンドウ表示ができます。

---

## 使い方

```perl
use PDL::Graphics::Cairo::PGPLOT qw(:all);

my @x = (-100 .. 899);
my @y = map { 10 + $_ * (-20 / 999) } (0 .. 999);
my $n = scalar @x;   # ← $n は必ず定義すること（未定義だと描画されない）

pgbegin(0, "/osx", 1, 1);           # macOS ネイティブウィンドウ
# pgbegin(0, "output.png/PNG", 1, 1);  # PNG ファイル出力
# pgbegin(0, "/xw", 1, 1);             # X11 経由（gnuplot）
# pgbegin(0, "/aqua", 1, 1);           # AquaTerm 経由（gnuplot）

pgenv(-100, 899, 10, -10, 0, -2);   # negative up 対応
pgsci(3);
pgline($n, \@x, \@y);
pgsci(1);
pgbox("ANST", 0.0, 1, "ANTV", 5.0, 2);
pgmtxt("TR", -1, 0.1, 1.0, "Ch1");
pgend();
```

## デバイス文字列

| 指定 | 出力先 |
|------|--------|
| `/OSX` `/osx` | **macOS ネイティブ Cocoa ウィンドウ**（gnuplot 不要） |
| `/PNG` | pgplot.png |
| `file.png/PNG` | file.png |
| `/PDF` | pgplot.pdf |
| `/SVG` | pgplot.svg |
| `/PS` `/CPS` | pgplot.pdf（PDF で代替） |
| `/XW` `/XWIN` `/X11` | gnuplot x11 経由（インタラクティブ） |
| `/AQT` `/AQUA` | gnuplot aqua 経由（AquaTerm、macOS） |
| `/WXT` | gnuplot wxt 経由 |

### macOS ネイティブウィンドウ（`/osx`）

`/osx` は `pdlcairo_viewer`（`make` でビルド）を直接使用します。
gnuplot・AquaTerm は不要で、`tight_layout()` も自動的に呼ばれます。

```perl
pgbegin(0, "/osx", 1, 1);
# ... 描画コマンド ...
pgend();   # ネイティブ Cocoa ウィンドウを表示、閉じるまでブロック
```

## 環境変数

| 変数 | 説明 |
|------|------|
| `PGPLOT_BACKGROUND` | `black` で黒背景・白前景（デフォルト: white） |
| `PGPLOT_DEV` | デフォルトデバイス（pgbegin のデバイス未指定時） |
| `PGPLOT_XW_WINDOW` | ウィンドウ geometry（gnuplot 経由時） |
| `PDLCAIRO_VIEWER` | `pdlcairo_viewer` バイナリのフルパスを指定（上書き） |

## フォントについて

描画フォントは Pango のデフォルト（通常 DejaVu Sans）を使用します。
変更するには `lib/PDL/Graphics/Cairo/Driver/Cairo.pm` の
`set_font()` 内の `Pango::FontDescription` のフォント名を変更してください。
将来的には環境変数 `PGPLOT_FONT_FAMILY` での指定に対応予定です。

---

## 関数実装状況

### ✅ 完全実装（53 関数）

科学解析スクリプトで使用する主要関数を全て含みます。

**デバイス管理**
- `cpgbeg` / `pgbegin` — デバイスオープン・サブパネル設定
- `cpgopen` / `pgopen` — デバイスオープン
- `cpgend` / `pgend` — デバイスクローズ・保存
- `cpgclos` / `pgclos` / `pgclose` — デバイスクローズ
- `cpgpage` / `pgpage` — 次のページ・パネルへ移動
- `cpgsubp` / `pgsubp` — サブパネル設定
- `cpgpanl` / `pgpanl` — 指定パネルへ移動
- `cpgpap` / `pgpap` — ページサイズ設定（インチ単位）

**座標系**
- `cpgenv` / `pgenv` — 座標窓・軸設定（ymin > ymax で Y 軸を上下反転）
- `cpgswin` / `pgswin` — 座標窓のみ設定
- `cpgsvp` / `pgsvp` — ビューポート設定
- `cpgvstd` / `pgvstd` — 標準ビューポート

**テキスト**
- `cpglab` / `pglab` / `pglabel` — X/Y/タイトルラベル
- `cpgmtxt` / `pgmtxt` — パネル辺へのテキスト（disp で複数行対応）
- `cpgtext` / `pgtext` — 座標指定テキスト
- `cpgptxt` / `pgptxt` — 角度付きテキスト

**線・図形描画**
- `cpgline` / `pgline` — 折れ線
- `cpgmove` / `pgmove` — ペン移動
- `cpgdraw` / `pgdraw` — ペンダウンで線
- `cpgpoly` / `pgpoly` — ポリゴン
- `cpgrect` / `pgrect` — 矩形
- `cpgarro` / `pgarro` — 矢印
- `cpgcirc` / `pgcirc` — 円

**点・マーカー**
- `cpgpt` / `pgpt` / `pgpoint` / `pgpoints` — マーカー描画
- `cpgpt1` / `pgpt1` — 1点マーカー

**グラフィクス属性**
- `cpgsci` / `pgsci` — カラーインデックス設定
- `cpgscr` / `pgscr` — カラーインデックスの RGB 設定
- `cpgshls` / `pgshls` — HLS カラー設定
- `cpgslw` / `pgslw` — 線幅
- `cpgsls` / `pgsls` — 線種（1=実線 2=破線 3=点線 4=一点鎖線）
- `cpgsch` / `pgsch` — 文字高さ（フォントサイズの相対倍率）
- `cpgscf` / `pgscf` — フォント種別（1=normal 2=roman 3=italic 4=script）
- `cpgsfs` / `pgsfs` — 塗りつぶしスタイル

**エラーバー**
- `cpgerry` / `pgerry` — 縦エラーバー
- `cpgerrx` / `pgerrx` — 横エラーバー
- `cpgerr1` / `pgerr1` — 1点エラーバー
- `cpgerrb` / `pgerrb` — 両方向エラーバー

**ヒストグラム**
- `cpghist` / `pghist` — ヒストグラム
- `cpgbin` / `pgbin` — ビン描画

**画像**
- `cpggray` / `pggray` — グレースケール画像
- `cpgimag` / `pgimag` — カラー画像

**等高線**
- `cpgcont` / `pgcont` — 等高線（簡易版）
- `cpgconf` / `pgconf` — 等高線（塗りつぶし）

**バッファリング**
- `cpgbbuf` / `pgbbuf` — 描画バッファ開始
- `cpgebuf` / `pgebuf` — 描画バッファ終了・フラッシュ
- `cpgupdt` / `pgupdt` — 強制フラッシュ

**属性問い合わせ**
- `cpgqwin` — 現在の座標窓
- `cpgqvp` — 現在のビューポート
- `cpgqvsz` — ビューポートサイズ（ピクセル）
- `cpgqci` — 現在のカラーインデックス
- `cpgqch` — 現在の文字高さ
- `cpgqlw` — 現在の線幅
- `cpgqls` — 現在の線種
- `cpgqcr` — カラーインデックスの RGB 値

**軸装飾**
- `cpgbox` / `pgbox` — 軸線・目盛り・数字描画
  - `A` = 0軸線（y=0 横線・x=0 縦線）
  - `N` = 目盛り数字（外枠位置）
  - `S` = 小目盛り（軸線上）
  - `T` = 大目盛り（軸線上）
  - `B`/`C` = 外枠
  - `G` = グリッド
  - `V` = Y軸数字横書き

---

### ⚠️ 部分実装（19 関数）

機能制限はあるが代替動作します。

| 関数 | 状況 |
|------|------|
| `cpgsvp/vstd/vsiz` | margin に変換して対応 |
| `cpgwnad` | 等アスペクト比（set_aspect で代替） |
| `cpgwedg/ctab/sitf` | カラーバー（imshow 後に自動表示） |
| `cpgconb/cons` | cpgcont で代替 |
| `cpgeras` | 新しい Figure を作成して代替 |
| `cpgqcf/qfs/qcs/qah/qhs/qinf` | 固定値を返す |
| `cpgsah` | arrowhead スタイル記録のみ（描画は未反映） |

---

### 🆕 新規実装（テスト未実施）

**注意: 以下の関数は実装済みですが、実際の PGPLOT スクリプトでの
動作テストが未実施です。使用時は動作確認をお願いします。**

| 関数 | 説明 | 備考 |
|------|------|------|
| `cpgrnd(x, nsub)` | nice な数値に丸める | BSM 近似実装 |
| `cpgrnge(x1, x2, xlo, xhi)` | データ範囲から nice な min/max を計算 | 参照渡し |
| `cpgnumb(mm, pp, form, str, nc)` | 数値を文字列に変換 | form=0: floating, 1: scientific |
| `cpgsave` / `pgsave` | 描画属性をスタックに保存 | ci/lw/ls/ch/cf/fs を保存 |
| `cpgunsa` / `pgunsa` | 保存した属性を復元 | スタック方式（LIFO） |

使用例:
```perl
pgsave();            # 現在の属性を保存
pgsci(2); pgslw(3);  # 一時的に変更
pgline(...);
pgunsa();            # 保存した属性に戻す

my $nice = cpgrnd(157.3, 5);  # → 200

my ($xlo, $xhi);
cpgrnge(-3.7, 8.2, \$xlo, \$xhi);  # → xlo=-4, xhi=9
```

---

### 🔲 スタブ（10 関数）

インタラクティブ・端末依存機能（PNG/PDF 出力では不要）。

| 関数 | 説明 |
|------|------|
| `cpgask` | 確認プロンプト（no-op） |
| `cpgiden` | ID ラベル（no-op） |
| `cpgscrl` | スクロール（no-op） |
| `cpgband/curs/ncur/lcur` | マウスカーソル入力（常に 0 を返す） |

---

## pgbox と pgenv の組み合わせパターン

典型的な使用パターン:

```perl
# axis=-2: 軸装飾なし（pgbox で後から描く）
pgenv($xmin, $xmax, $ymin, $ymax, 0, -2);

# データ描画
pgsci(3);  # green
pgline($n, \@x, \@y);

# 軸装飾を追加
pgsci(1);
pgbox("ANST", 0.0, 1, "ANTV", 5.0, 2);
#      XOPT  xtick nxsub YOPT  ytick nysub

# チャンネル名
pgmtxt("TR", -1, 0.1, 1.0, "A1");
```

## negative up（Y 軸上下反転）

ymin > ymax のとき Y 軸が反転します（上が負、下が正）。

```perl
# ymin > ymax → Y 軸反転
pgenv(-100, 899, 10, -10, 0, -2);
#                    ^    ^
#                  ymin  ymax  (10 > -10 → negative up)
```

## 多段パネル（列優先レイアウト）

```perl
pgbegin(0, "/XW", -6, 6);   # 6×6 パネル、列優先
pgpap(13, 0.75);             # 13インチ幅、アスペクト比 0.75
```

`nxsub` が負のとき列優先（上→下→次の列）で埋めます。
元の PGPLOT の動作と一致します。

---

## 制限事項

- `cpgconb/cons` は `cpgcont` で代替（完全な等値線アルゴリズム未実装）
- `cpgwedg` はカラーバーとして表示（詳細スタイル指定は未対応）
- gnuplot 経由のインタラクティブ表示は gnuplot が別途必要
- `/osx` は `pdlcairo_viewer`（`make` でビルド）が必要（macOS のみ）
- `cpgsah` arrowhead スタイルは記録されるが描画には未反映

---

## 依存モジュール

```
Cairo          # 必須
Pango          # 必須（テキスト描画）
Moo            # 必須
PDL            # 必須
gnuplot        # 任意（/XW /AQT /WXT インタラクティブ表示）
pdlcairo_viewer # 任意（/OSX ネイティブ表示、macOS のみ）
```

---

## Cairo API による等価な書き方

PGPLOT 互換レイヤーの代わりに Cairo API（matplotlib 風）で同じ図を描くこともできます。
`ylim(lo, hi)` で `lo > hi` のとき自動的に Y 軸が反転します（negative up）。

```perl
use PDL;
use PDL::Graphics::Cairo qw(figure);

my $x = pdl(-100 .. 899);
my $y = 10 + $x * (-20 / 999);

my $fig = figure(width => 800, height => 500);
my $ax  = $fig->axes();

$ax->line($x, $y, color => 'green', lw => 1.5);
$ax->xlim(-100, 899);
$ax->ylim(10, -10);   # lo > hi → negative up（Y 軸自動反転）

$fig->tight_layout();
$fig->show(backend => 'osx');   # macOS ネイティブ表示
# $fig->show();                 # gnuplot 経由
# $fig->save('output.png');     # PNG 保存
```

デバイスの切り替えは `show()` の引数で行います：

| 表示方法 | 書き方 |
|----------|--------|
| macOS ネイティブ | `$fig->show(backend => 'osx')` |
| gnuplot/AquaTerm | `$fig->show(terminal => 'aqua')` |
| gnuplot/X11 | `$fig->show(terminal => 'x11')` |
| PNG 保存 | `$fig->save('output.png')` |
