# PDL::Graphics::Cairo::PGPLOT — PGPLOT Compatibility Layer

## Overview

`PDL::Graphics::Cairo::PGPLOT` is a drop-in compatibility layer that renders
existing PGPLOT code using PDL::Graphics::Cairo (Cairo/Pango backend).
It produces PNG, PDF, SVG output and native macOS window display,
without requiring libgiza or X11.

---

## Basic Usage

```perl
use PDL::Graphics::Cairo::PGPLOT qw(:all);

my @x = (-100 .. 899);
my @y = map { 10 + $_ * (-20 / 999) } (0 .. 999);
my $n = scalar @x;

pgbegin(0, "/osx", 1, 1);          # macOS native window
# pgbegin(0, "output.png/PNG", 1, 1);  # PNG file
# pgbegin(0, "/xw", 1, 1);             # X11 via gnuplot
# pgbegin(0, "/aqua", 1, 1);           # AquaTerm via gnuplot

pgenv(-100, 899, 10, -10, 0, -2);  # negative up supported
pgsci(3);
pgline($n, \@x, \@y);
pgsci(1);
pgbox("ANST", 0.0, 1, "ANTV", 5.0, 2);
pgmtxt("TR", -1, 0.1, 1.0, "Ch1");
pgend();
```

**Note:** `$n` must be defined as `scalar @x`. An undefined `$n` produces no output.

## Device Strings

| String | Output |
|--------|--------|
| `/PNG` | pgplot.png |
| `file.png/PNG` | file.png |
| `/PDF` | pgplot.pdf |
| `/SVG` | pgplot.svg |
| `/PS` `/CPS` | pgplot.pdf (PDF substitute) |
| `/OSX` `/osx` | **macOS native Cocoa window** (no gnuplot required) |
| `/XW` `/XWIN` `/X11` | Interactive via gnuplot x11 |
| `/AQT` `/AQUA` | Interactive via gnuplot aqua (AquaTerm, macOS) |
| `/WXT` | Interactive via gnuplot wxt |

### macOS Native Window (`/osx`)

`/osx` uses `pdlcairo_viewer` (built by `make`) directly — no gnuplot or
AquaTerm required. `tight_layout()` is called automatically.

```perl
pgbegin(0, "/osx", 1, 1);
# ... plot commands ...
pgend();   # displays native Cocoa window, blocks until closed
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `PGPLOT_BACKGROUND` | `black` = black background, white foreground (default: white) |
| `PGPLOT_DEV` | Default device when pgbegin device is empty |
| `PGPLOT_XW_WINDOW` | Window geometry string (gnuplot interactive) |
| `PDLCAIRO_VIEWER` | Full path to `pdlcairo_viewer` binary (override) |

## Fonts

The rendering font is Pango default (typically DejaVu Sans).
To change it, modify `lib/PDL/Graphics/Cairo/Driver/Cairo.pm`,
specifically the `Pango::FontDescription` in `set_font()`.
Support for a `PGPLOT_FONT_FAMILY` environment variable may be added in the future.

---

## Function Implementation Status

### ✅ Fully Implemented (53 functions)

Includes all functions used in typical scientific analysis scripts.

**Device Management**
- `cpgbeg`/`pgbegin` — Open device, set subpanel layout
- `cpgopen`/`pgopen` — Open device
- `cpgend`/`pgend` — Close device and save output
- `cpgclos`/`pgclos`/`pgclose` — Close device
- `cpgpage`/`pgpage` — Advance to next page/panel
- `cpgsubp`/`pgsubp` — Set subpanel layout
- `cpgpanl`/`pgpanl` — Move to specified panel
- `cpgpap`/`pgpap` — Set page size (inches)

**Coordinate System**
- `cpgenv`/`pgenv` — Set window and draw axes (ymin > ymax reverses Y axis)
- `cpgswin`/`pgswin` — Set coordinate window only
- `cpgsvp`/`pgsvp` — Set viewport
- `cpgvstd`/`pgvstd` — Standard viewport

**Text**
- `cpglab`/`pglab`/`pglabel` — X/Y/title labels
- `cpgmtxt`/`pgmtxt` — Text at panel edge (multi-line via disp parameter)
- `cpgtext`/`pgtext` — Text at world coordinates
- `cpgptxt`/`pgptxt` — Text at angle

**Lines and Shapes**
- `cpgline`/`pgline` — Polyline
- `cpgmove`/`pgmove` — Move pen
- `cpgdraw`/`pgdraw` — Draw to position
- `cpgpoly`/`pgpoly` — Polygon
- `cpgrect`/`pgrect` — Rectangle
- `cpgarro`/`pgarro` — Arrow
- `cpgcirc`/`pgcirc` — Circle

**Points and Markers**
- `cpgpt`/`pgpt`/`pgpoint`/`pgpoints` — Draw markers
- `cpgpt1`/`pgpt1` — Draw single marker

**Graphics Attributes**
- `cpgsci`/`pgsci` — Set color index
- `cpgscr`/`pgscr` — Define color index RGB
- `cpgshls`/`pgshls` — Set color by HLS
- `cpgslw`/`pgslw` — Set line width
- `cpgsls`/`pgsls` — Set line style (1=solid 2=dashed 3=dotted 4=dash-dot)
- `cpgsch`/`pgsch` — Set character height
- `cpgscf`/`pgscf` — Set font (1=normal 2=roman 3=italic 4=script)
- `cpgsfs`/`pgsfs` — Set fill style

**Error Bars**
- `cpgerry`/`pgerry` — Vertical error bars
- `cpgerrx`/`pgerrx` — Horizontal error bars
- `cpgerr1`/`pgerr1` — Single-point error bar
- `cpgerrb`/`pgerrb` — Bidirectional error bars

**Histograms**
- `cpghist`/`pghist` — Histogram
- `cpgbin`/`pgbin` — Binned data bar chart

**Images**
- `cpggray`/`pggray` — Grayscale image
- `cpgimag`/`pgimag` — Color image

**Contours**
- `cpgcont`/`pgcont` — Contour map (simplified)
- `cpgconf`/`pgconf` — Filled contour map

**Buffering**
- `cpgbbuf`/`pgbbuf` — Begin buffered output
- `cpgebuf`/`pgebuf` — End buffered output and flush
- `cpgupdt`/`pgupdt` — Force update

**Attribute Queries**
- `cpgqwin` — Query current window
- `cpgqvp` — Query current viewport
- `cpgqvsz` — Query viewport size in pixels
- `cpgqci` — Query current color index
- `cpgqch` — Query current character height
- `cpgqlw` — Query current line width
- `cpgqls` — Query current line style
- `cpgqcr` — Query RGB of color index

**Axis Decoration**
- `cpgbox`/`pgbox` — Draw axes, ticks, and numeric labels
  - `A` = axis lines through (0,0)
  - `N` = numeric labels (at border position)
  - `S` = minor tick marks (on axis line)
  - `T` = major tick marks (on axis line)
  - `B`/`C` = bottom+left / top+right border
  - `G` = grid lines
  - `V` = Y-axis labels horizontal (not rotated)

---

### ⚠️ Partially Implemented (19 functions)

Work with limitations; substitute behavior provided.

| Function | Status |
|----------|--------|
| `cpgsvp/vstd/vsiz` | Converted to margin settings |
| `cpgwnad` | Equal-aspect via set_aspect |
| `cpgwedg/ctab/sitf` | Color bar shown after imshow |
| `cpgconb/cons` | Handled by cpgcont |
| `cpgeras` | Creates new Figure |
| `cpgqcf/qfs/qcs/qah/qhs/qinf` | Returns fixed default values |
| `cpgsah` | Records arrowhead style (not yet reflected in drawing) |

---

### 🆕 Newly Implemented — Not Yet Tested in Real Scripts

**Warning: The following functions have been implemented but have NOT been
tested with actual PGPLOT scripts. Please verify behavior before use.**

| Function | Description | Notes |
|----------|-------------|-------|
| `cpgrnd(x, nsub)` | Round x to a "nice" value | Returns 1,2,2.5,5,10×10^n |
| `cpgrnge(x1,x2,xlo,xhi)` | Compute nice range covering x1..x2 | Pass references for xlo,xhi |
| `cpgnumb(mm,pp,form,str,nc)` | Format mm×10^pp as string | form=0: floating, 1: scientific |
| `cpgsave`/`pgsave` | Push graphics attributes onto stack | Saves: ci,lw,ls,ch,cf,fs |
| `cpgunsa`/`pgunsa` | Pop and restore graphics attributes | LIFO stack |

Example usage:
```perl
pgsave();            # save current attributes
pgsci(2); pgslw(3);  # temporary changes
pgline(...);
pgunsa();            # restore saved attributes

my $nice = cpgrnd(157.3, 5);   # → 200

my ($xlo, $xhi);
cpgrnge(-3.7, 8.2, \$xlo, \$xhi);  # → xlo=-4, xhi=9
```

---

### 🔲 Stub Functions (10 functions)

Interactive/terminal-dependent features not needed for file output.

| Function | Behavior |
|----------|----------|
| `cpgask` | No-op |
| `cpgiden` | No-op |
| `cpgscrl` | No-op |
| `cpgband/curs/ncur/lcur` | Always returns 0 |

---

## pgbox and pgenv Pattern

Typical EEG analysis pattern:

```perl
# axis=-2: suppress default axes (pgbox draws them explicitly)
pgenv($xmin, $xmax, $ymin, $ymax, 0, -2);

# Draw data
pgsci(3);  # green
pgline($n, \@x, \@y);

# Draw axes in current color (e.g. pgsci(1)=white on black background)
pgsci(1);
pgbox("ANST", 0.0, 1, "ANTV", 5.0, 2);

# Channel label at upper-left of panel
pgmtxt("TR", -1, 0.1, 1.0, "A1");
```

## Negative-Up Y Axis

When `ymin > ymax`, the Y axis is reversed (positive down, negative up).
Useful for time series data where convention requires this orientation.

```perl
# ymin > ymax triggers Y-axis reversal
pgenv(-100, 899, 10, -10, 0, -2);
#                    ^    ^
#                  ymin  ymax   (10 > -10 → negative up)
```

## Multi-Panel Column-Major Layout

```perl
pgbegin(0, "/XW", -6, 6);   # 6×6 panels, column-major order
pgpap(13, 0.75);             # 13-inch wide, 0.75 aspect ratio
```

Panels are filled column by column (top→bottom, then next column),
matching original PGPLOT behavior when `nxsub` is negative.

---

## Known Limitations

- `cpgconb/cons`: delegated to `cpgcont` (full marching-squares not implemented)
- `cpgwedg`: shown as color bar (detailed style options not supported)
- Interactive display via gnuplot requires gnuplot installed separately
- `/osx` requires `pdlcairo_viewer` built by `make` (macOS only)
- `cpgsah` arrowhead style is recorded but not yet applied to arrow drawing

## Dependencies

```
Cairo          # required
Pango          # required (text rendering)
Moo            # required
PDL            # required
gnuplot        # optional (for /XW /AQT /WXT interactive display)
pdlcairo_viewer # optional (for /OSX native display, macOS only)
```

---

## Cairo API Equivalent

The same plot can be written using the Cairo API (matplotlib-style).
When `ylim(lo, hi)` is called with `lo > hi`, the Y axis is automatically
reversed (negative up).

```perl
use PDL;
use PDL::Graphics::Cairo qw(figure);

my $x = pdl(-100 .. 899);
my $y = 10 + $x * (-20 / 999);

my $fig = figure(width => 800, height => 500);
my $ax  = $fig->axes();

$ax->line($x, $y, color => 'green', lw => 1.5);
$ax->xlim(-100, 899);
$ax->ylim(10, -10);   # lo > hi → negative up (Y axis auto-reversed)

$fig->tight_layout();
$fig->show(backend => 'osx');   # macOS native
# $fig->show();                 # via gnuplot
# $fig->save('output.png');     # PNG file
```

Device switching via `show()` arguments:

| Display | Code |
|---------|------|
| macOS native | `$fig->show(backend => 'osx')` |
| gnuplot/AquaTerm | `$fig->show(terminal => 'aqua')` |
| gnuplot/X11 | `$fig->show(terminal => 'x11')` |
| PNG file | `$fig->save('output.png')` |
