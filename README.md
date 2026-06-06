# PDL::Graphics::Cairo

A 2D plotting library for PDL (Perl Data Language),
using Cairo and Pango as the rendering backend.

Runs on **macOS and Linux (Ubuntu/Debian)**.

You can write plots in whichever style you are familiar with —
matplotlib, PGPLOT, or gnuplot.
PDL::Graphics::Cairo handles the rendering.

## Features

- matplotlib-style API (`figure`, `axes`, `line`, `scatter`, `hist`, ...)
- PGPLOT compatibility layer (`pgbegin`, `pgenv`, `pgline`, `pgbox`, ...)
- gnuplot-style API via matplotlib layer (familiar command mapping)
- PNG, PDF, SVG file output — no X11 or libgiza required
- **macOS native display via giza_server** — the default on macOS; plain `$fig->show()` opens a native window. In-memory PNG over a Unix-domain socket, persistent tabbed windows that outlive the program, shared with giza/PGPLOT C programs. Works on Linux too (GTK3/Xlib server).
- **Multiple plots in a tabbed window** (giza_server)
- Interactive display via gnuplot (aqua/wxt/x11) — cross-platform; automatic fallback when `giza_server` is unavailable
- Legacy macOS Cocoa viewer (`backend => 'osx'`, `pdlcairo_viewer`) retained as a **deprecated** opt-in fallback only — no longer the default, no longer built by `make`
- Axes frame, ticks, and tick labels rendered by Cairo
- Dual Y axis support (`twinx`) with independent tick labels on both axes
- Black background support (`PGPLOT_BACKGROUND=black`)
- Negative-up Y axis: `pgenv` with ymin > ymax, or `$ax->ylim(lo, hi)` with lo > hi
- Multi-panel subplots with `tight_layout()`
- 6×6 multi-panel (36 subplots) layout tested

---

## Synopsis

### If you write matplotlib-style

```perl
use PDL;
use PDL::Graphics::Cairo qw(figure);

my $x   = sequence(200) / 10;
my $fig = figure(width => 800, height => 500);
my $ax  = $fig->axes();
$ax->line($x, sin($x), color => 'blue', label => 'sin(x)');
$ax->set_xlabel('x');
$ax->set_ylabel('y');
$ax->set_grid(1);
$ax->legend();
$fig->tight_layout();
$fig->save('plot.png');         # PNG file
$fig->show();                   # macOS: giza_server window (default); Linux: gnuplot
```

### If you write PGPLOT-style

```perl
use PDL::Graphics::Cairo::PGPLOT qw(:all);

my @x = (-100 .. 899);
my @y = map { 10 + $_ * (-20 / 999) } (0 .. 999);
my $n = scalar @x;

pgbegin(0, "/osx", 1, 1);              # macOS native
# pgbegin(0, "/xw",  1, 1);            # X11 via gnuplot
# pgbegin(0, "/aqua", 1, 1);           # AquaTerm via gnuplot
# pgbegin(0, "output.png/PNG", 1, 1);  # PNG file

pgenv(-100, 899, 10, -10, 0, -2);      # negative up (ymin > ymax)
pgsci(3);                               # green
pgline($n, \@x, \@y);
pgsci(1);
pgbox("ANST", 0.0, 1, "ANTV", 5.0, 2);
pgmtxt("TR", -1, 0.1, 1.0, "Ch1");
pgend();
```

### If you write gnuplot-style

```perl
use PDL;
use PDL::Graphics::Cairo qw(figure);

my $x = pdl(-100 .. 899);
my $y = 10 + $x * (-20 / 999);

my $fig = figure(width => 800, height => 500);
my $ax  = $fig->axes();
$ax->line($x, $y, color => 'green', lw => 1.5);  # plot ... with lines lc "green"
$ax->set_xlim(-100, 899);                          # set xrange [-100:899]
$ax->set_ylim(10, -10);                            # set yrange [10:-10] (negative up)
$ax->text(870, 9.5, "Ch1", color => 'black');      # set label "Ch1" at ...
$fig->tight_layout();
$fig->show();                   # macOS: giza_server (default); Linux: gnuplot
$fig->save('output.png');       # PNG file
```

For details of each API, see the [Documentation](#documentation) section below.

### Method naming

Setter methods use matplotlib's Axes-method names as the canonical form:
`set_xlim` / `set_ylim` / `set_xlabel` / `set_ylabel` / `set_title` /
`set_xticks` / `set_yticks`, and `plot` (an alias of `line`). The shorter
pyplot-style forms `xlim` / `ylim` / `xticks` / `yticks` are kept as permanent
aliases (not deprecated), so existing scripts and matplotlib muscle-memory both
work. The entry point is the `figure()` function; `PDL::Graphics::Cairo->new()`
is an equivalent constructor-style alias.

---

## Installation

```bash
perl Makefile.PL
make
make test
sudo make install
```

On macOS, native window display uses `giza_server` (a separate binary — see
the Interactive Display section below). No Cocoa viewer is built by `make`.

### Prerequisites

- PDL >= 2.0
- Cairo (Perl binding)
- Pango (Perl binding)
- Moo

**macOS (MacPorts):**
```bash
sudo port install p5-cairo p5-pango p5-moo
```

**Ubuntu/Debian:**
```bash
sudo apt install libcairo-perl libpango-perl libmoo-perl
sudo apt install gnuplot-x11   # for interactive display
```

### Optional: faster image loading for imread()

`imread()` picks the fastest available backend, in this order:
`PDL::IO::PNG` (libpng, ~2.5 ms) → `PDL::IO::Image` (FreeImage, ~5.3 ms) →
`PDL::IO::Pic` (rpic, ~18.9 ms; bundled with PDL). All paths normalize the
result to `[H,W,3]` float32 with row 0 = top.

```bash
cpan PDL::IO::PNG        # fastest; PNG only
# or, for multi-format support:
cpan Alien::FreeImage
cpan PDL::IO::Image
```

If neither `PDL::IO::PNG` nor `PDL::IO::Image` is installed, `imread()` falls
back to `PDL::IO::Pic` (rpic) automatically.

### Interactive Display

#### giza_server — default on macOS, also on Linux

On macOS, plain `$fig->show()` opens a native window via `giza_server`.
You normally don't pass a backend at all:

```perl
$fig->show();                                     # macOS default: giza_server
$fig->show(backend => 'gs');                      # explicit; auto-launches the server
$fig->show(backend => 'gs', start => 'connect');  # connect to a running server only
```

Renders the figure to an in-memory PNG and sends it to a `giza_server`
process over a Unix-domain socket — no temporary files. The server owns
the window, so it persists after the program exits, the window is tabbed,
and the same server is shared by giza/PGPLOT C/Fortran programs using the
`/gs` device. The binary is found via `$GIZA_SERVER`, a sibling
`../giza-server` checkout, or `$PATH`.
See https://github.com/goosh-gh/giza-server.

When `giza_server` is unavailable, `show()` falls back to gnuplot — it does
**not** fall back to the legacy Cocoa viewer. `wait_all()` is a no-op on the
`gs` path (windows already persist), so legacy `nowait` + `wait_all` scripts
still run unchanged.

#### gnuplot (cross-platform fallback)

```perl
$fig->show(terminal => 'x11');   # or 'aqua', 'wxt', 'qt'
```

```bash
# macOS
sudo port install gnuplot +aquaterm   # or +x11

# Ubuntu/Debian
sudo apt install gnuplot-x11
```

#### Legacy Cocoa viewer (deprecated)

`backend => 'osx'` (the standalone `pdlcairo_viewer` Cocoa app) is retired and
kept only as a deprecated, opt-in fallback. It is no longer the default and is
no longer built by `make`. New code should use the default (`giza_server`) path.

---

## Image Display with imread()

Use `imread()` to load images for `imshow()`. It automatically selects the
fastest available backend and normalizes the array to `[H,W,3]` float32:

```perl
use PDL::Graphics::Cairo qw(figure imread);

my $img = imread("photo.png");   # [H,W,3] float32, row=0 = top
my $fig = figure(width => 800, height => 600);
my $ax  = $fig->axes();
$ax->imshow($img);
$ax->axis('off');                # hide frame, ticks, labels
$fig->tight_layout();
$fig->show();
```

| Backend | Speed (1000×1000) | Install |
|---------|-------------------|---------|
| `PDL::IO::PNG` (libpng) | ~2.5 ms ✅ | `cpan PDL::IO::PNG` |
| `PDL::IO::Image` (FreeImage) | ~5.3 ms | `cpan Alien::FreeImage PDL::IO::Image` |
| `PDL::IO::Pic` (rpic, fallback) | ~18.9 ms | included with PDL |

---

## Directory Structure

```
PDL-Graphics-Cairo/
├── lib/PDL/Graphics/Cairo/
│   ├── Cairo.pm          # Main entry point: figure(), subplots()
│   ├── Figure.pm         # Figure class: save(), show(), tight_layout()
│   ├── Axes.pm           # Axes class: line(), scatter(), xlim(), ylim(), ...
│   ├── PGPLOT.pm         # PGPLOT compatibility layer: pgbegin/pgline/pgend/...
│   ├── Driver/
│   │   ├── Cairo.pm      # Cairo/Pango rendering backend (PNG/PDF/SVG output)
│   │   ├── GS.pm         # giza_server backend (default macOS native display; Linux too)
│   │   ├── OSX.pm        # legacy Cocoa backend (deprecated; via pdlcairo_viewer)
│   │   └── Gnuplot.pm    # gnuplot display backend (aqua/wxt/x11)
│   ├── Transform/        # Coordinate transforms (linear, log)
│   ├── ColorMap.pm       # Colormaps (viridis, plasma, ...)
│   └── Tick.pm           # Tick mark calculation
├── src/osx/              # legacy Cocoa viewer (deprecated; not built by make)
│   ├── pdlcairo_viewer.m # Standalone Cocoa viewer app (macOS only)
│   └── build.sh          # Build script for pdlcairo_viewer
├── docs/
│   ├── PGPLOT_compatibility_en.md
│   ├── PGPLOT_compatibility_ja.md
│   ├── gnuplot_compatibility.md
│   └── matplotlib_comparison.md
└── examples/
```

### Role of the two Cairo.pm files

There are two files named `Cairo.pm` with distinct roles:

| File | Role |
|------|------|
| `lib/PDL/Graphics/Cairo.pm` | Public API entry point. Exports `figure()` and `subplots()`. The file a user loads with `use PDL::Graphics::Cairo`. |
| `lib/PDL/Graphics/Cairo/Driver/Cairo.pm` | Internal rendering driver. Uses the Cairo/Pango C libraries to draw lines, text, and shapes onto an image surface, and saves it as PNG/PDF/SVG. Never loaded directly by users. |

---

## Important: always call tight_layout()

Call `$fig->tight_layout()` before `$fig->show()` or `$fig->save()`:

```perl
$fig->tight_layout();
$fig->show();
```

---

## macOS Native Backend

macOS native display is provided by `giza_server` (the default). The figure is
rendered to an in-memory PNG and streamed over a Unix-domain socket to the
server, which owns a tabbed, persistent native window:

```
Cairo image surface (software rendering)
    ↓ in-memory PNG over Unix-domain socket (no temp files)
giza_server (separate process — Cocoa on macOS, GTK3/Xlib on Linux)
    ↓ NSImage / GTK → native window (tabbed, persistent)
native window
```

The legacy standalone `pdlcairo_viewer` Cocoa app (`backend => 'osx'`) is
deprecated and no longer built by `make`.

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `PGPLOT_BACKGROUND` | `black` = dark background (default: white) |
| `PGPLOT_DEV` | Default device for `pgbegin`. Accepted values: `/OSX` `/XW` `/XWIN` `/X11` `/XSERVE` `/AQT` `/AQUA` `/WXT` `/QT` `/PNG` `/PDF` `/SVG` `/PS` `/CPS` |
| `PDLCAIRO_BACKEND` | Override the `show()` backend: `gs` (default on macOS), `gnuplot`, or `osx` (deprecated) |
| `GIZA_SERVER` | Full path to the `giza_server` binary (override auto-detection) |
| `PDLCAIRO_VIEWER` | Full path to the legacy `pdlcairo_viewer` binary (deprecated `osx` backend) |

---

## Plot Types (matplotlib API)

| Method | Description |
|--------|-------------|
| `line` | Line plot |
| `scatter` | Scatter plot (colormap supported) |
| `bar` / `barh` | Vertical / horizontal bar chart |
| `hist` / `hist_kde` | Histogram / Histogram + KDE overlay |
| `errorbar` / `errorbar_stats` | Error bars |
| `fill_between` | Filled confidence band |
| `step` | Step function |
| `stem` | Stem plot |
| `imshow` | 2D image or RGB image [H,W,3] with colorbar; use `imread()` to load |
| `contourf` | Filled contour |
| `pie` | Pie chart |
| `boxplot` | Box-and-whisker |
| `violinplot` | Violin plot |
| `qqplot` | Q-Q plot vs. normal |
| `heatmap` | Heatmap with labels |
| `stackplot` | Stacked area |
| `eventplot` | Raster / spike plot |
| `axhline` / `axvline` | Reference lines |
| `axvspan` / `axhspan` | Shaded regions |
| `annotate` | Arrow annotation |
| `twinx` | Dual Y axis (independent ticks on both axes) |

---

## Documentation

| File | Description |
|------|-------------|
| `docs/PGPLOT_compatibility_en.md` | PGPLOT compatibility layer — full function list and device strings |
| `docs/PGPLOT_compatibility_ja.md` | Same in Japanese |
| `docs/gnuplot_compatibility.md` | gnuplot-style API mapping and comparison |
| `docs/matplotlib_comparison.md` | matplotlib vs PDL::Graphics::Cairo comparison |

---

## Examples

```bash
# Cross-platform (macOS and Linux)
perl examples/example_png.pl               # basic PNG output
perl examples/example_stats.pl             # statistical plots
perl examples/example_cairo_api.pl         # matplotlib-style with negative-up Y axis
perl examples/example_pgplot.pl            # PGPLOT-style API

# Interactive display
perl examples/example_show.pl              # auto-detect terminal
perl examples/example_show.pl osx          # macOS native (macOS only)
perl examples/example_show.pl aqua         # gnuplot/AquaTerm (macOS)
perl examples/example_show.pl x11          # gnuplot/X11 (Linux/XQuartz)

# macOS 4-panel demo
perl examples/pdlcairo_osx_demo.pl         # macOS native
perl examples/pdlcairo_osx_demo.pl gnuplot # via gnuplot
```

---

## License

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
