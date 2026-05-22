# PDL::Graphics::Cairo

A matplotlib-inspired 2D plotting library for PDL (Perl Data Language),
using Cairo and Pango as the rendering backend.
Also includes a **PGPLOT compatibility layer** for migrating existing PGPLOT scripts.

## Features

- matplotlib-style API (`figure`, `axes`, `line`, `scatter`, `hist`, ...)
- PGPLOT-compatible API (`pgbegin`, `pgenv`, `pgline`, `pgbox`, ...)
- PNG, PDF, SVG file output — no X11 or libgiza required
- **macOS native Cocoa window display** (`$fig->show(backend => 'osx')`) — no gnuplot or AquaTerm required
- Interactive display via gnuplot (aqua/wxt/x11)
- Black background support (`PGPLOT_BACKGROUND=black`)
- Negative-up Y axis support (`pgenv` with ymin > ymax)
- Multi-panel subplots with minimal margins
- 6×6 multi-panel (36 subplots) layout tested

---

## Synopsis

### matplotlib-style API

```perl
use PDL;
use PDL::Graphics::Cairo qw(figure);

my $x   = sequence(200) / 10;
my $fig = figure(width => 800, height => 500);
my $ax  = $fig->axes();
$ax->line($x, sin($x), color => 'blue', label => 'sin(x)');
$ax->set_xlabel('x');
$ax->set_ylabel('y');
$ax->legend();
$fig->save('plot.png');          # file output
$fig->show();                    # interactive (gnuplot)
$fig->show(backend => 'osx');   # macOS native Cocoa window
```

### PGPLOT compatibility layer

```perl
use PDL;
use PDL::Graphics::Cairo::PGPLOT qw(:all);

pgbegin(0, "output.png/PNG", -6, 6);  # 6x6 subpanels
pgpap(13, 0.75);                        # 13-inch wide

pgenv(-100, 899, 10, -10, 0, -2);      # negative up
pgsci(3);                               # green
pgline($n, \@time, \@data);
pgsci(1);                               # foreground color
pgbox("ANST", 0.0, 1, "ANTV", 5.0, 2);
pgmtxt("TR", -1, 0.1, 1.0, "Fz");
pgpage();

pgend();
```

---

## Installation

```bash
perl Makefile.PL
make
make test
sudo make install
```

On macOS, `make` automatically builds `pdlcairo_viewer` (the native Cocoa
window viewer) using Xcode Command Line Tools. No additional dependencies
beyond Cairo are required.

### Prerequisites

- PDL >= 2.0
- Cairo (Perl binding)
- Pango (Perl binding)
- Moo

**macOS (MacPorts):**
```bash
sudo port install p5-cairo p5-pango p5-moo
# Xcode Command Line Tools (for pdlcairo_viewer):
xcode-select --install
```

**Ubuntu/Debian:**
```bash
sudo apt install libcairo-perl libpango-perl libmoo-perl
```

### Interactive Display

#### macOS native (recommended on macOS)

After `make install`, use the native Cocoa backend — no gnuplot or AquaTerm needed:

```perl
$fig->show(backend => 'osx');
```

Or set the environment variable to make it the default:

```bash
export PDLCAIRO_BACKEND=osx
```

Press `q`, `ESC`, or `Return` to close the window.

#### gnuplot (cross-platform)

`$fig->show()` uses gnuplot for interactive display.

**macOS:**
```bash
sudo port install gnuplot +aquaterm
# or
sudo port install gnuplot +x11   # requires XQuartz
```

**Ubuntu:**
```bash
sudo apt install gnuplot-x11
```

---

## macOS Native Backend

`Driver::OSX` provides a native Cocoa window without gnuplot or AquaTerm:

```
Cairo image surface (software rendering)
    ↓ PNG temporary file
pdlcairo_viewer (standalone Cocoa app, built by make)
    ↓ NSImage → NSWindow/NSView
macOS native window
```

The architecture follows the same design as the
[giza /osx driver](https://github.com/danieljprice/giza) —
aspect-ratio-preserving scaling (letterbox/pillarbox) on resize,
keyboard input to close the window.

| Feature | Status |
|---------|--------|
| Native NSWindow display | ✅ |
| Aspect-ratio resize | ✅ |
| Close with q/ESC/Return | ✅ |
| Retina/HiDPI | not yet |
| Multiple windows | planned |

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
| `imshow` | 2D image with colorbar |
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
| `twinx` | Dual Y axis |

---

## PGPLOT Compatibility

See [`docs/PGPLOT_compatibility_en.md`](docs/PGPLOT_compatibility_en.md)
for the full function list and implementation status.

### Implementation summary

| Status | Count | Description |
|--------|-------|-------------|
| ✅ Full | 53 | All functions used in typical EEG scripts |
| ⚠️ Partial | 19 | Working with limitations |
| 🆕 New (untested) | 5 | `pgrnd`, `pgrnge`, `pgnumb`, `pgsave`, `pgunsa` |
| 🔲 Stub | 10 | Interactive/cursor functions (not needed for file output) |

### Environment variables

| Variable | Description |
|----------|-------------|
| `PGPLOT_BACKGROUND` | `black` = dark background (default: white) |
| `PGPLOT_DEV` | Default device string |
| `PDLCAIRO_BACKEND` | `osx` = use macOS native backend for `show()` |
| `PDLCAIRO_VIEWER` | Full path to `pdlcairo_viewer` binary (override) |

---

## Documentation

| File | Description |
|------|-------------|
| `docs/PGPLOT_compatibility_ja.md` | PGPLOT compatibility layer details (Japanese) |
| `docs/PGPLOT_compatibility_en.md` | PGPLOT compatibility layer (English) |
| `docs/matplotlib_comparison.md` | matplotlib vs PDL::Graphics::Cairo comparison |

---

## Examples

```bash
perl examples/example_png.pl          # basic PNG output
perl examples/example_stats.pl        # statistical plots
perl examples/pdlcairo_osx_demo.pl    # macOS native 4-panel demo
perl examples/pdlcairo_osx_demo.pl gnuplot   # same via gnuplot
```

---

## License

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
