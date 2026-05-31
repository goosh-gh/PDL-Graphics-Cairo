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
- **macOS native Cocoa window display** (`$fig->show(backend => 'osx')`) — no gnuplot or AquaTerm required
- **Persistent windows via giza_server** (`$fig->show(backend => 'gs')`) — in-memory PNG over a socket, windows outlive the program, shared with giza/PGPLOT C programs, works on Linux too
- **Multiple plots in tabbed window** on macOS native backend
- Interactive display via gnuplot (aqua/wxt/x11) — cross-platform
- On non-macOS systems, `backend => 'osx'` automatically falls back to gnuplot
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
$ax->xlabel('x');
$ax->ylabel('y');
$ax->set_grid(1);
$ax->legend();
$fig->tight_layout();
$fig->save('plot.png');         # PNG file
$fig->show(backend => 'osx');  # macOS native window
$fig->show();                  # gnuplot (Linux/macOS)
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
$ax->xlim(-100, 899);                              # set xrange [-100:899]
$ax->ylim(10, -10);                                # set yrange [10:-10] (negative up)
$ax->text(870, 9.5, "Ch1", color => 'black');      # set label "Ch1" at ...
$fig->tight_layout();
$fig->show(backend => 'osx');   # macOS native
$fig->show();                   # gnuplot (Linux/macOS)
$fig->save('output.png');       # PNG file
```

For details of each API, see the [Documentation](#documentation) section below.

---

## Installation

```bash
perl Makefile.PL
make
make test
sudo make install
```

On macOS, `make` automatically builds `pdlcairo_viewer` (native Cocoa viewer)
using Xcode Command Line Tools.

### Prerequisites

- PDL >= 2.0
- Cairo (Perl binding)
- Pango (Perl binding)
- Moo

**macOS (MacPorts):**
```bash
sudo port install p5-cairo p5-pango p5-moo
xcode-select --install   # for pdlcairo_viewer
```

**Ubuntu/Debian:**
```bash
sudo apt install libcairo-perl libpango-perl libmoo-perl
sudo apt install gnuplot-x11   # for interactive display
```

### Optional: PDL::IO::Image (recommended for image display)

`imread()` uses `PDL::IO::Image` if available, falling back to `rpic`.
`PDL::IO::Image` is **28x faster** than `rpic` (0.2 ms vs 5.7 ms per image).

```bash
# macOS (requires Alien::FreeImage — see docs/image_io.md for build notes)
cpan Alien::FreeImage
cpan PDL::IO::Image
```

Without `PDL::IO::Image`, `imread()` falls back to `PDL::IO::Pic` (rpic) automatically.

### Interactive Display

#### macOS native (recommended on macOS)

```perl
$fig->show(backend => 'osx');
```

Press `q`, `ESC`, or `Return` to close. Multiple figures open as tabs:

```perl
$fig1->show(backend => 'osx', nowait => 1, title => 'Demo 1');
$fig2->show(backend => 'osx', nowait => 1, title => 'Demo 2');
PDL::Graphics::Cairo::Driver::OSX->wait_all();
```

#### giza_server (persistent windows, cross-platform)

```perl
$fig->show(backend => 'gs');                 # auto-launches giza_server
$fig->show(backend => 'gs', start => 'connect');  # connect only
```

Renders the figure to an in-memory PNG and sends it to a `giza_server`
process over a Unix-domain socket — no temporary files. The server owns
the window, so it persists after the program exits, and the same server
is shared by giza/PGPLOT C/Fortran programs using the `/gs` device.
Requires the `giza_server` binary (found via `$GIZA_SERVER` or `$PATH`).
See https://github.com/goosh-gh/giza-server.

#### Which backend? (`osx` vs `gs`)

Both display native windows on macOS; they differ in what they depend on
and how long the window lives:

| | `backend => 'osx'` | `backend => 'gs'` |
|---|---|---|
| Helper needed | `pdlcairo_viewer` (bundled) | `giza_server` (separate) |
| Temp files | yes | no (in-memory PNG) |
| Window lifetime | tied to the session | persists after exit |
| Linux | falls back to gnuplot | yes (GTK3 server) |
| Shared with C/Fortran giza | no | yes (`/gs` device) |

Use `osx` for a self-contained P:G:Cairo setup with no extra server.
Use `gs` if you also run giza/PGPLOT programs and want persistent windows
shared across processes (and on Linux).

#### gnuplot (cross-platform)

```bash
# macOS
sudo port install gnuplot +aquaterm   # or +x11

# Ubuntu/Debian
sudo apt install gnuplot-x11
```

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
$fig->show(backend => 'osx');
```

| Backend | Speed | Install |
|---------|-------|---------|
| `PDL::IO::Image` (FreeImage) | 0.2 ms/image ✅ | `cpan Alien::FreeImage PDL::IO::Image` |
| `PDL::IO::Pic` (rpic, fallback) | 5.7 ms/image | included with PDL |

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
│   │   ├── OSX.pm        # macOS native Cocoa backend (via pdlcairo_viewer)
│   │   └── Gnuplot.pm    # gnuplot display backend (aqua/wxt/x11)
│   ├── Transform/        # Coordinate transforms (linear, log)
│   ├── ColorMap.pm       # Colormaps (viridis, plasma, ...)
│   └── Tick.pm           # Tick mark calculation
├── src/osx/
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
$fig->show(backend => 'osx');
```

---

## macOS Native Backend

```
Cairo image surface (software rendering)
    ↓ PNG temporary file
pdlcairo_viewer (standalone Cocoa app, built by make)
    ↓ NSImage → NSWindow/NSView (tabbed)
macOS native window
```

| Feature | Status |
|---------|--------|
| Native NSWindow display | ✅ |
| Multiple figures as tabs | ✅ |
| Letterbox resize (white background) | ✅ |
| Close with q/ESC/Return | ✅ |
| Retina/HiDPI | not yet |

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `PGPLOT_BACKGROUND` | `black` = dark background (default: white) |
| `PGPLOT_DEV` | Default device for `pgbegin`. Accepted values: `/OSX` `/XW` `/XWIN` `/X11` `/XSERVE` `/AQT` `/AQUA` `/WXT` `/QT` `/PNG` `/PDF` `/SVG` `/PS` `/CPS` |
| `PDLCAIRO_BACKEND` | `osx` = use macOS native backend for `show()` |
| `PDLCAIRO_VIEWER` | Full path to `pdlcairo_viewer` binary (override auto-detection) |

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
