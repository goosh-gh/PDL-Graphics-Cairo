# PDL::Graphics::Cairo

PDL（Perl Data Language）向けの2Dプロットライブラリです。
CairoとPangoをレンダリングバックエンドとして使用します。

**macOS および Linux（Ubuntu/Debian）で動作します。**

matplotlib・PGPLOT・gnuplot、いずれのスタイルでも書けます。
PDL::Graphics::Cairo がレンダリングを担います。

## 特徴

- matplotlib風API（`figure`、`axes`、`line`、`scatter`、`hist` など）
- PGPLOT互換レイヤー（`pgbegin`、`pgenv`、`pgline`、`pgbox` など）
- gnuplot風のコマンド対応（matplotlib APIにマッピング）
- PNG・PDF・SVGファイル出力 — X11・libgiza 不要
- **macOSネイティブCocoaウィンドウ表示**（`$fig->show(backend => 'osx')`）— gnuplot・AquaTerm 不要
- **複数プロットをタブで1ウィンドウ表示**（macOSネイティブバックエンド）
- gnuplot経由のインタラクティブ表示（aqua/wxt/x11）— クロスプラットフォーム
- macOS以外では `backend => 'osx'` が自動的にgnuplotへフォールバック
- CairoによるAxes枠・目盛り・数値ラベルの描画
- Dual Y軸サポート（`twinx`）— 両軸独立した目盛り・ラベル
- 黒背景サポート（`PGPLOT_BACKGROUND=black`）
- Negative-up Y軸: `pgenv`でymin>ymax、`$ax->ylim(lo, hi)`でlo>hiのとき自動反転
- `tight_layout()`によるマルチパネルサブプロット
- 6×6マルチパネル（36サブプロット）動作確認済み

---

## 使い方

慣れ親しんだスタイルでそのまま書けます。

### matplotlib 風に書く場合

```perl
use PDL;
use PDL::Graphics::Cairo qw(figure);

my $x   = sequence(200) / 10;
my $fig = figure(width => 800, height => 500);
my $ax  = $fig->axes();
$ax->line($x, sin($x), color => 'blue', label => 'sin(x)');
$ax->xlabel('x');
$ax->ylabel('y');
$ax->set_grid(1);
$ax->legend();
$fig->tight_layout();
$fig->save('plot.png');          # PNGファイル
$fig->show(backend => 'osx');   # macOSネイティブウィンドウ
$fig->show();                   # gnuplot経由（Linux/macOS）
$fig->show(terminal => 'aqua'); # AquaTerm経由（macOS）
```

### PGPLOT 風に書く場合

```perl
use PDL::Graphics::Cairo::PGPLOT qw(:all);

my @x = (-100 .. 899);
my @y = map { 10 + $_ * (-20 / 999) } (0 .. 999);
my $n = scalar @x;

pgbegin(0, "/osx", 1, 1);              # macOSネイティブ
# pgbegin(0, "/xw",  1, 1);            # X11（gnuplot経由）
# pgbegin(0, "/aqua", 1, 1);           # AquaTerm（gnuplot経由）
# pgbegin(0, "output.png/PNG", 1, 1);  # PNGファイル

pgenv(-100, 899, 10, -10, 0, -2);      # negative up（ymin > ymax）
pgsci(3);                               # 緑
pgline($n, \@x, \@y);
pgsci(1);
pgbox("ANST", 0.0, 1, "ANTV", 5.0, 2);
pgmtxt("TR", -1, 0.1, 1.0, "Ch1");
pgend();
```

### gnuplot 風に書く場合

```perl
use PDL;
use PDL::Graphics::Cairo qw(figure);

my $x = pdl(-100 .. 899);
my $y = 10 + $x * (-20 / 999);

my $fig = figure(width => 800, height => 500);
my $ax  = $fig->axes();
$ax->line($x, $y, color => 'green', lw => 1.5);  # plot ... with lines lc "green"
$ax->xlim(-100, 899);                              # set xrange [-100:899]
$ax->ylim(10, -10);                                # set yrange [10:-10]（negative up）
$ax->text(870, 9.5, "Ch1", color => 'black');      # set label "Ch1" at ...
$fig->tight_layout();
$fig->show(backend => 'osx');   # macOSネイティブ
$fig->show();                   # gnuplot経由（Linux/macOS）
$fig->save('output.png');       # PNGファイル
```

各APIの詳細は[ドキュメント](#ドキュメント)セクションを参照してください。

---

## インストール

```bash
perl Makefile.PL
make
make test
sudo make install
```

macOSでは `make` 時に Xcode Command Line Tools を使って
`pdlcairo_viewer`（ネイティブCocoaビューア）が自動ビルドされます。

### 必要モジュール

- PDL >= 2.0
- Cairo（Perlバインディング）
- Pango（Perlバインディング）
- Moo

**macOS（MacPorts）:**
```bash
sudo port install p5-cairo p5-pango p5-moo
xcode-select --install   # pdlcairo_viewer のビルドに必要
```

**Ubuntu/Debian:**
```bash
sudo apt install libcairo-perl libpango-perl libmoo-perl
sudo apt install gnuplot-x11   # インタラクティブ表示用
```

### インタラクティブ表示

#### macOSネイティブ（macOSで推奨）

```perl
$fig->show(backend => 'osx');
```

`q`・`ESC`・`Return` でウィンドウを閉じます。複数figureをタブで表示：

```perl
$fig1->show(backend => 'osx', nowait => 1, title => 'Demo 1');
$fig2->show(backend => 'osx', nowait => 1, title => 'Demo 2');
PDL::Graphics::Cairo::Driver::OSX->wait_all();
```

#### gnuplot経由（クロスプラットフォーム）

```bash
# macOS
sudo port install gnuplot +aquaterm   # または +x11

# Ubuntu/Debian
sudo apt install gnuplot-x11
```

---

## ディレクトリ構成

```
PDL-Graphics-Cairo/
├── lib/PDL/Graphics/Cairo/
│   ├── Cairo.pm          # 公開APIエントリポイント: figure(), subplots()
│   ├── Figure.pm         # Figureクラス: save(), show(), tight_layout()
│   ├── Axes.pm           # Axesクラス: line(), scatter(), xlim(), ylim(), ...
│   ├── PGPLOT.pm         # PGPLOT互換レイヤー: pgbegin/pgline/pgend/...
│   ├── Driver/
│   │   ├── Cairo.pm      # Cairo/Pangoレンダリングバックエンド（PNG/PDF/SVG出力）
│   │   ├── OSX.pm        # macOSネイティブCocoaバックエンド（pdlcairo_viewer経由）
│   │   └── Gnuplot.pm    # gnuplot表示バックエンド（aqua/wxt/x11）
│   ├── Transform/        # 座標変換（linear, log）
│   ├── ColorMap.pm       # カラーマップ（viridis, plasma, ...）
│   └── Tick.pm           # 目盛り計算
├── src/osx/
│   ├── pdlcairo_viewer.m # スタンドアロンCocoaビューアアプリ（macOSのみ）
│   └── build.sh          # pdlcairo_viewer のビルドスクリプト
├── docs/
│   ├── PGPLOT_compatibility_en.md
│   ├── PGPLOT_compatibility_ja.md
│   ├── gnuplot_compatibility.md
│   └── matplotlib_comparison.md
└── examples/
```

### 2つのCairo.pmの役割分担

`Cairo.pm`という名前のファイルが2つありますが、役割は全く異なります：

| ファイル | 役割 |
|----------|------|
| `lib/PDL/Graphics/Cairo.pm` | 公開APIエントリポイント。`figure()`と`subplots()`をエクスポートする。ユーザーが`use PDL::Graphics::Cairo`で読み込むファイル。 |
| `lib/PDL/Graphics/Cairo/Driver/Cairo.pm` | 内部レンダリングドライバ。Cairo/Pango Cライブラリを使って線・テキスト・図形をイメージサーフェスに描画し、PNG/PDF/SVGとして保存する。ユーザーが直接読み込むことはない。 |

---

## 重要: tight_layout() を必ず呼ぶこと

`$fig->show()` や `$fig->save()` の前に `$fig->tight_layout()` を呼んでください：

```perl
$fig->tight_layout();
$fig->show(backend => 'osx');
```

---

## macOSネイティブバックエンド

```
Cairo image surface（ソフトウェアレンダリング）
    ↓ PNGテンポラリファイル
pdlcairo_viewer（スタンドアロンCocoaアプリ、make でビルド）
    ↓ NSImage → NSWindow/NSView（タブ表示）
macOSネイティブウィンドウ
```

| 機能 | 状態 |
|------|------|
| NSWindowネイティブ表示 | ✅ |
| 複数figureのタブ表示 | ✅ |
| letterboxリサイズ（白背景） | ✅ |
| q/ESC/Returnで閉じる | ✅ |
| Retina/HiDPI | 未対応 |

---

## 環境変数

| 変数 | 説明 |
|------|------|
| `PGPLOT_BACKGROUND` | `black` で黒背景（デフォルト: white） |
| `PGPLOT_DEV` | `pgbegin`のデフォルトデバイス。指定可能な値: `/OSX` `/XW` `/XWIN` `/X11` `/XSERVE` `/AQT` `/AQUA` `/WXT` `/QT` `/PNG` `/PDF` `/SVG` `/PS` `/CPS` |
| `PDLCAIRO_BACKEND` | `osx` で `show()` のデフォルトをOSXバックエンドに |
| `PDLCAIRO_VIEWER` | `pdlcairo_viewer` バイナリのフルパスを指定（自動検出を上書き） |

---

## プロット種別（matplotlib API）

| メソッド | 説明 |
|----------|------|
| `line` | 折れ線グラフ |
| `scatter` | 散布図（カラーマップ対応） |
| `bar` / `barh` | 縦・横棒グラフ |
| `hist` / `hist_kde` | ヒストグラム / KDEオーバーレイ |
| `errorbar` / `errorbar_stats` | エラーバー |
| `fill_between` | 塗りつぶし帯 |
| `step` | ステップ関数 |
| `stem` | ステムプロット |
| `imshow` | 2D画像（カラーバー付き） |
| `contourf` | 等高線（塗りつぶし） |
| `pie` | 円グラフ |
| `boxplot` | 箱ひげ図 |
| `violinplot` | バイオリンプロット |
| `qqplot` | Q-Qプロット（正規分布比較） |
| `heatmap` | ヒートマップ（ラベル付き） |
| `stackplot` | 積み上げ面グラフ |
| `eventplot` | ラスタ・スパイクプロット |
| `axhline` / `axvline` | 水平・垂直参照線 |
| `axvspan` / `axhspan` | 網掛け領域 |
| `annotate` | 矢印アノテーション |
| `twinx` | 双Y軸（両軸独立した目盛り） |

---

## ドキュメント

| ファイル | 内容 |
|----------|------|
| `docs/PGPLOT_compatibility_en.md` | PGPLOT互換レイヤー — 関数一覧・デバイス文字列（英語） |
| `docs/PGPLOT_compatibility_ja.md` | 同上（日本語） |
| `docs/gnuplot_compatibility.md` | gnuplotコマンドとのマッピング・比較（英語） |
| `docs/matplotlib_comparison.md` | matplotlib vs PDL::Graphics::Cairo 比較 |

---

## 実行例

```bash
# クロスプラットフォーム（macOS・Linux共通）
perl examples/example_png.pl               # 基本PNG出力
perl examples/example_stats.pl             # 統計プロット
perl examples/example_cairo_api.pl         # matplotlib風（negative-up Y軸）
perl examples/example_pgplot.pl            # PGPLOT互換API

# インタラクティブ表示
perl examples/example_show.pl              # 自動検出
perl examples/example_show.pl osx          # macOSネイティブ（macOSのみ）
perl examples/example_show.pl aqua         # gnuplot/AquaTerm（macOS）
perl examples/example_show.pl x11          # gnuplot/X11（Linux/XQuartz）

# macOS 4パネルデモ
perl examples/pdlcairo_osx_demo.pl         # macOSネイティブ
perl examples/pdlcairo_osx_demo.pl gnuplot # gnuplot経由
```

---

## ライセンス

このライブラリはフリーソフトウェアです。Perl自体と同じ条件のもとで
再配布・改変することができます。
