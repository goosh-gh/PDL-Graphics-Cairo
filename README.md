# PDL::Graphics::Cairo

**matplotlib-style scientific plotting for Perl/PDL, built on Cairo.**

PDL::Graphics::Cairo (P:G:C) is a high-level 2D plotting library for [PDL](https://pdl.perl.org/) that provides a matplotlib-compatible API. It handles axis scaling, tick placement, labels, legends, colormaps, and complex layouts — so you don't have to.

> Cairo is a low-level drawing API: "draw a line here", "place text there", one command at a time.  
> PDL::Graphics::Cairo is the high-level layer on top: axes, ticks, data transforms, color mapping, and layout — all done for you.

---

## Features

### Plot types
`line` · `scatter` · `bar` / `barh` · `hist` · `errorbar` · `fill_between` · `step` · `stem` · `imshow` · `contour` · `contourf` · `pcolormesh` / `pcolor` · `pie` · `boxplot` · `violin` · `quiver` · `heatmap` · `stackplot` · `eventplot` · `hexbin` · `specgram` · `plot_date` · and more

### Axes & decoration
- Auto-scaling with `tight_layout`; `uniform_margins => 1` option ensures all panels have identical plot-area dimensions in multi-panel grids made with `subplot` / `subplots` (avoids the default asymmetry where edge panels receive larger margins). It does not act on panels placed with `add_gridspec`; use `cell_margins` there
- `tight_layout` measures the tick numbers, axis labels and titles with Cairo before drawing, for the data and limits set at the time it is called, and leaves room for them: long tick numbers such as `-2.00e+04` no longer push the ylabel out of the figure, and the xlabel of a low figure is not cut. In very small cells the margins are still capped at 80% of the cell
- Legend outside the frame: `legend(loc => 'outside top')` puts the entries in one row in the title row, right-aligned (the title moves left, or the legend gets its own row, if they would touch); `legend(loc => 'outside right')` puts them in a column right of the frame and makes the frame narrower; `legend(loc => 'outside')` chooses `outside top` for up to `outside_max` entries (default 3), else `outside right`. `upper right` (default), `upper left`, `lower right`, `lower left` draw the boxed legend inside the frame
- Linear / log scale (`set_xscale`, `set_yscale`, `semilogy`, `loglog`)
- Tick control: `tick_params`, minor ticks, `xaxis_formatter` / `yaxis_formatter`
- Date/time axis: `plot_date` accepts UNIX epoch values or `DateTime` objects; tick spacing and label format (`HH:MM`, `Mon DD`, `Mon YYYY`, `YYYY`) are chosen automatically based on the data range
- Twin axes: `twinx` (shared X, independent Y on the right), `twiny` (shared Y, independent X on top) — combinable on the same parent Axes
- Inset axes: `inset_axes`
- Annotations: `annotate`, `axhline`, `axvline`, `axhspan`, `axvspan`, `text`
- Cross-axes connector: `$fig->add_connection(axA => $ax1, xyA => [x, y], coordsA => ..., axB => $ax2, xyB => [x, y], coordsB => ...)` draws a straight line between a point of one axes and a point of another, over all axes and unclipped (matplotlib `ConnectionPatch`). Each end is given in `'data'`, `'axes'` (fraction of the plot rectangle) or `'figure'` (fraction of the figure) coordinates, or mixed per component as `['data', 'axes']`; `color`, `lw`, `ls`, `alpha`
- `$fig->add_text(text => ..., ax => $ax, xy => [x, y], coords => ...)` — text in the same coordinates as `add_connection`, drawn over all axes and unclipped, so it can sit just outside a plot rectangle; `ha`, `va`, `offset => [dx, dy]` (pixels), `fontsize`, `weight`, `color`, `angle`
- `$ax->data_to_pixel($x, $y)` / `$ax->axes_to_pixel($fx, $fy)` — figure pixel coordinates of a data point or of a fraction of the plot rectangle, available once the axes has been drawn
- `$ax->clip_pad_top($px)` — how far above the plot rectangle plotted data may be drawn before it is clipped (default 15 px; 0 clips at the top edge)
- Multi-line text: `text()` splits on `\n` with `halign` (`left`/`right`/`center`), `valign` (`top`/`middle`/`bottom`), and `line_spacing`; rotated blocks stack correctly (`angle=0` vertical, `angle=90` side-by-side). Custom y-tick labels (e.g. `"name\n(scale)"`) reserve left margin from their longest line so `tight_layout` does not clip them
- `set_aspect('equal', $anchor)` — force equal data aspect (square pixels per data unit). `$anchor` places the freed space when the box is not square: `C` centre (default, back-compatible), `W`/`E` left/right, `N`/`S` top/bottom — e.g. `set_aspect('equal', 'W')` keeps the plot flush-left so a colour bar hangs tight against it
- An `axis('off')` panel reserves no tick/label/frame margin, so it packs flush against its neighbours (e.g. a round topomap between two line panels sits with almost no side gap)
- `scatter` marker styles: `o s ^ v < > d + x p h * P X` (14 styles, covering most matplotlib marker shorthands)
- `bar` / `barh` error bars (`yerr`, symmetric or `yerr_low`/`yerr_high` for asymmetric) and grouped bars (call `bar()` multiple times with shifted `x` and a shared `width`, matplotlib-style)

### Layouts
- `subplots(M, N)` — uniform grid
- `GridSpec` — non-uniform spanning panels, with **`height_ratios`/`width_ratios`** for per-row/column size control
- `$fig->tight_layout` called on a figure with a GridSpec or `subplot_mosaic` (without `cell_margins`) places the panels from what each needs around its plot rectangle — tick numbers, labels, title, colorbar, a twin axis — as matplotlib's `tight_layout`: the GridSpec's `left` / `right` / `top` / `bottom` / `hspace` / `wspace` are replaced, the plot rectangles of a row (column) line up, and `height_ratios` / `width_ratios` share the remaining height (width). When `save` / `show` lay out the figure by themselves, and for panels moved with `set_position`, the GridSpec's own bounds and gaps are kept
- `add_gridspec(..., cell_margins => 0)` — every Axes of the GridSpec gets the same fixed margins, so all panels have the same plot area wherever they are in the grid and whichever cells are left empty. With `0` the cell itself is the plot rectangle (as in matplotlib): tick numbers and labels are drawn in the gaps (`wspace` / `hspace`) and outside the grid (`left` / `right` / `top` / `bottom`). A number gives that many pixels on every side, a hash names the sides: `cell_margins => { left => 30, bottom => 20 }`
- `$fig->label_only($ax)` — tick numbers on `$ax` (or `[$ax, ...]`) only; `$fig->label_outer` — y numbers on the leftmost panel of each row and x numbers on the lowest panel of each column, found from the panel positions, so grids with empty cells work. Both take `axis => 'x' | 'y' | 'both'` and `axes => [...]`; tick marks stay on every panel
- In a GridSpec cell narrower (or lower) than the margins chosen for it, the margins are shrunk so that a plot rectangle remains (they used to cross, giving a negative width)
- `subplot_mosaic("AAB\nCDB")` — string-defined layouts
- `suptitle` — figure-level title

### Color
- Built-in colormaps: `viridis`, `plasma`, `jet`, `hot`, `cool`, `gray`, `RdBu`, `inferno`, `magma`, `coolwarm`
- `ListedColormap` — discrete color lists
- `Normalize`, `LogNorm`, `BoundaryNorm`, `TwoSlopeNorm` — data-to-color mapping
- `colorbar(label => '...')` — colorbar with an optional title, placed on any side (`top`/`bottom`/`left`/`right`). The reserved margin is sized from the actual bar width, tick-label width and caption (not a fixed constant), so a thin bar takes little space. A colorbar normally needs a visible axis; set `$ax->{_colorbar_force} = 1` to draw one on an `axis('off')` panel (e.g. to hang a colour bar off a round topomap). `colorbar(cmap => $name_or_object, vmin => ..., vmax => ...)` attaches a colorbar that does not come from a plot command of that Axes (an image the caller coloured itself); the object needs `rgb_at($v)`, and such a colorbar is drawn on an `axis('off')` panel too. `reserve => 0` takes no room from the plot rectangle, so an equal-aspect image narrower than its panel stays centred with the bar beside it. `tick_step => 1` puts the ticks at the multiples of that value instead of automatically chosen ones (thinned to every 2nd, 3rd, ... multiple when the numbers would overlap on a short bar)
- `pcolormesh` / `pcolor` — pseudocolor plots on a non-uniform grid (unlike `imshow`, cell boundaries don't need to be equally spaced)
- `imshow` draws the whole image in one call (each cell scaled without smoothing); cells whose value is not finite are left transparent

### Output
- PNG (via `PDL::IO::PNG` or Cairo), PDF, SVG
- Frames sent to `giza-server` are encoded as PNG in memory: with `PDL::IO::PNG::png_encode` when it is installed, otherwise with `Compress::Zlib`; figures with transparent pixels take the file-writing path above. `PDLCAIRO_PNG_LEVEL` sets the zlib level (default 1)
- Interactive display via `giza-server` (persistent window with tabs, sliders, resize, cursor/pick). Slider values arrive normalized `[0,1]` (the client assigns each slider's meaning); `show_interactive(init => { 0 => ..., 1 => ... })` sets each slider's initial thumb position.
- Interactive **3D mesh + point viewer** via `Driver::GS3D` (see [3D](#3d-drivergs3d) below) — triangle mesh surface (z-buffer Gouraud shading) with point markers, quaternion trackball rotation, wheel zoom; **macOS (Cocoa)** viewer (the Linux Xlib viewer does not render the 3D mesh)
- Interactive **grid scrub** via `show_grid_scrub` (`Driver::GS`) — double-click a subplot to open a zoomed child window; drag on the trace to mark that latency, draw a vertical line at the same latency in every parent subplot, and read out the point; the selection is kept after release and shared across all open child windows. With `main_scrub => 1` a click or drag on a panel of the grid itself selects the latency too. A panel whose Axes carries `$ax->{_scrub_skip} = 1` gets no latency line and is not a click target (for panels that are not a time axis, e.g. a scalp map); double-clicking it still opens it enlarged. **macOS (Cocoa)** `giza-server` only (needs a build that reports 2D double-click and button-drag events). With `PDLCAIRO_DEBUG=1` each frame prints `frame: build=.. png=.. send=.. gap=.. events=.. age=..` (time in the render callback, PNG encoding, socket write, interval since the window's previous frame, input events received since then, age of the newest one) and `ack: ..ms after send`
- Inline display in `App::PDL::Notebook` (via `$fig->to_inline`)

### Downsampling
- `PDL::Graphics::Cairo::LTTB` — Largest-Triangle-Three-Buckets downsampling
  - `lttb($x, $y, $n_out)` — original LTTB (Steinarsson 2013), spike-preserving
  - `lttb_minmax($x, $y, $n_out)` — **MinMax-LTTB** (v0.05+): selects min+max per bucket; pure PDL vector ops, ~10× faster than original LTTB for interactive use
- Preserves visual spikes (EOG artifacts, transients) unlike simple decimation
- Used automatically in `eeg_viewer_raw.pl` and `eeg_viewer.pl`

### Compatibility layers
- matplotlib API (`line`, `scatter`, `set_xlim`, `tick_params`, ...)
- PGPLOT API (`env`, `line`, `points`, `pgbox`, `pgaxis`, `pgtick`, `subp`/`panl`/`page`, ...) — multi-panel order follows the sign of `NXSUB` (`> 0` row-major, `< 0` column-major)
- gnuplot-style API (`:gnuplot` import tag)

---

## Quick start

```perl
use PDL;
use PDL::Graphics::Cairo qw(subplots);

my ($fig, $ax) = subplots(1, 1, width => 600, height => 400);

my $x = sequence(100) / 10;
$ax->line($x, sin($x),         color => 'steelblue', lw => 2, label => 'sin(x)');
$ax->line($x, cos($x),         color => 'tomato',    lw => 2, label => 'cos(x)');
$ax->fill_between($x, sin($x), cos($x), alpha => 0.15);

$ax->xlabel('x');
$ax->ylabel('y');
$ax->title('sin and cos');
$ax->legend;
$ax->grid(1);

$fig->tight_layout;
$fig->save('plot.png');
```

---

## More examples

### Spectrogram (audio analysis)

```perl
use PDL::Graphics::Cairo qw(subplots);

my $Fs  = 256;                          # sample rate (Hz)
my $t   = sequence($Fs * 5) / $Fs;
my $sig = sin(2*3.14159*10*$t) * exp(-($t-2.5)**2/0.5)  # alpha burst
        + 0.2 * grandom($t->nelem);

my ($fig, $ax) = subplots(1, 1, width => 700, height => 400);
$ax->specgram($sig, Fs => $Fs, NFFT => 128, noverlap => 112,
              window => 'hann', cmap => 'hot', vmin => -35, vmax => 5);
$ax->ylim(0, 40);
$ax->xlabel('Time (s)');
$ax->ylabel('Frequency (Hz)');
$fig->tight_layout;
$fig->save('specgram.png');
```

### Complex layouts with subplot_mosaic

```perl
use PDL::Graphics::Cairo qw(subplot_mosaic);

my ($fig, %ax) = subplot_mosaic("AAB\nCCB", width => 800, height => 500);

$ax{A}->line(pdl(0..10), pdl(map { sin($_) } 0..10));
$ax{A}->title('Panel A: full width');

$ax{B}->bar(pdl(1..4), pdl(3, 1, 4, 2));
$ax{B}->title('B: tall');

$ax{C}->scatter(grandom(50), grandom(50), s => 20);
$ax{C}->title('C');

$fig->suptitle('subplot_mosaic demo');
$fig->tight_layout;
$fig->save('mosaic.png');
```

### Hexbin density plot

```perl
use PDL::Graphics::Cairo qw(subplots);

my $x = grandom(5000);
my $y = $x * 0.8 + grandom(5000) * 0.6;

my ($fig, $ax) = subplots(1, 1, width => 600, height => 500);
$ax->hexbin($x, $y, gridsize => 30, cmap => 'plasma');
$ax->xlabel('X'); $ax->ylabel('Y');
$fig->tight_layout;
$fig->save('hexbin.png');
```

### Non-uniform grid with pcolormesh

```perl
use PDL::Graphics::Cairo qw(subplots);

# Cell boundary coordinates — unlike imshow, these don't need to be
# evenly spaced. $z's shape is (n_rows, n_cols) = (y-cells, x-cells).
my $x = pdl(0, 1, 3, 7, 15, 31);   # 5 cells, doubling width
my $y = pdl(0, 1, 2, 4, 8);        # 4 cells, doubling height
my $z = sequence(4, 5);

my ($fig, $ax) = subplots(1, 1, width => 600, height => 450);
$ax->pcolormesh($x, $y, $z, cmap => 'viridis');
$ax->colorbar(label => 'value');
$ax->xlabel('x'); $ax->ylabel('y');
$fig->tight_layout;
$fig->save('pcolormesh.png');
```

### Custom colormaps and normalization

```perl
use PDL::Graphics::Cairo qw(subplots ListedColormap TwoSlopeNorm);

my $cmap = ListedColormap(['#2166ac','#74add1','#fee090','#f46d43','#a50026']);
my $norm = TwoSlopeNorm(vmin => -10, vcenter => 0, vmax => 20);

my $vals = grandom(200) * 10;
my @c    = map { $norm->call($vals->at($_)) } 0..$vals->nelem-1;

my ($fig, $ax) = subplots(1, 1, width => 600, height => 400);
$ax->scatter(grandom(200), grandom(200), c => pdl(@c), cmap => $cmap, s => 25);
$fig->tight_layout;
$fig->save('custom_cmap.png');
```

---

## Installation

```bash
# Dependencies
cpanm Moo Cairo PDL PDL::IO::PNG

# Install
git clone https://github.com/goosh-gh/PDL-Graphics-Cairo
cd PDL-Graphics-Cairo
perl Makefile.PL && make && make install
```

For interactive display, also install [giza-server](https://github.com/goosh-gh/giza-server).

---

## Examples

See the `examples/` directory:

| File | Description |
|---|---|
| `eeg_viewer_raw.pl` | **MNE `raw.plot()`-style multi-channel EEG viewer (giza-server)** — page buttons, time-window control, amplitude gain, channel scroll, polarity toggle, time-position slider, LTTB downsampling, cursor/pick overlay, resize support |
| `eeg_viewer_raw.jp.pl` | Japanese-commented version of `eeg_viewer_raw.pl` |
| `example_gridspec.pl` | GridSpec, subplot_mosaic layouts |
| `example_hexbin.pl` | 2D density, scatter vs hexbin comparison |
| `example_colormap.pl` | ListedColormap, LogNorm, TwoSlopeNorm, BoundaryNorm |
| `specgram_demo.pl` | Chirp, EEG-like, multi-tone spectrograms |
| `example_contour.pl` | contour/contourf: sincos overlay, 4-panel gallery, topographic map |
| `example_stats.pl` | Statistical plots (boxplot, violin, histogram) |
| `example_png.pl` | Basic plotting quickstart |
| `example_gs.pl` | Interactive display via giza-server |
| `example_gs_zoom_pan.pl` | Interactive zoom/pan: pinch/scroll to zoom, two-finger drag to pan, double-click to reset; demonstrates `zoom_pan_redraw => 1` |
| `example_gs_cursor_overlay.pl` | Cursor coordinate overlay with mouse tracking |

### Running the EEG viewer

**giza-server version** (native window, full cursor/pick/zoom/pan):

```bash
# Demo mode (synthetic 34-channel × 30 s data, no files needed)
GIZA_SERVER=/path/to/giza_server \
PDLCAIRO_RENDER_SCALE=0.75 \
perl examples/eeg_viewer_raw.pl

# Real data (Nihon Kohden .eeg, requires PDL::EEG)
GIZA_SERVER=/path/to/giza_server \
perl examples/eeg_viewer_raw.pl /path/to/recording.eeg
```

**App-PDL-Notebook version** (browser UI, ~7 ms/frame — see [App-PDL-Notebook](https://github.com/goosh-gh/App-PDL-Notebook)):

```perl
# Inside a notebook cell:
use lib '/path/to/PDL-EEG/lib';
use PDL;
local @ARGV = ('/path/to/recording.eeg');   # omit for demo mode
do '/path/to/App-PDL-Notebook/examples/notebook_eeg_raw.pl';
```

Browser sliders (Position, Window, Gain, Ch offset, Neg-up) trigger live PNG
re-renders via `param`/`on_change`/`to_inline`. No giza-server required.

**Controls (giza-server version):**

| Control | Action |
|---|---|
| `[◀]` `[▶]` | Page backward / forward by one time window |
| `[−]` `[10s]` `[+]` | Shrink / expand time window (1 s steps) |
| `[−]` `[±100µV]` `[+]` | Decrease / increase amplitude gain (log steps: 10→20→50→100→…→500 µV) |
| `[▲]` `[▼]` | Scroll channels up / down |
| `[neg↑]` / `[pos↑]` | Toggle polarity: negative-up (EEG convention) ↔ positive-up |
| Position slider | Jump to any time position |
| Left-click (waveform) | PICK: snap cursor to nearest sample, show ch/time/value |
| Mouse move (waveform) | Cursor overlay across all channels |

**Optional arguments (Nihon Kohden files):**

```bash
# Load only block 1 (0-indexed)
perl examples/eeg_viewer_raw.pl recording.eeg --block=1

# Load and concatenate blocks 0 and 1
perl examples/eeg_viewer_raw.pl recording.eeg --blocks=0,1
```

---

## 3D (Driver::GS3D)

Interactive 3D viewer built on `giza-server`, for spatial layouts such as EEG
electrode montages overlaid on an anatomical cortex mesh. It renders a triangle
**mesh surface** and **point markers** with labels. It is not a general 3D
plotting API (no `surf`/`mesh` plotting commands; see "What P:G:C does NOT do").

```perl
use PDL;
use PDL::Graphics::Cairo::Driver::GS3D;

my $drv = PDL::Graphics::Cairo::Driver::GS3D->new(
    scene  => {
        mesh   => { verts => $V, faces => $F },  # [Nv,3] world XYZ, [Nf,3] vertex indices
        points => $pts,                          # [N,3] world XYZ (e.g. electrodes)
        colors => $rgb,                          # [N,3] 0..1
        labels => \@names,
    },
    render => 'zbuffer',                         # 'line' or 'zbuffer' (default 'line')
    width  => 700, height => 700,
);
$drv->run;                              # blocks; drives the interactive loop
```

**Mesh rendering**

| `render` | Behaviour |
|---|---|
| `'line'` | Scanline fill drawn as horizontal bars; no z-buffer, surface is see-through |
| `'zbuffer'` | Software z-buffer Gouraud triangle rasteriser: per-vertex colour interpolation, correct occlusion, smooth shading |

- Mesh colours (per face or per vertex) are shaded by a Lambert term; discrete mean-curvature grey shading (sulci dark / gyri light) is applied when curvature colours are supplied.
- Adaptive level of detail: a coarse mesh while dragging, a fine mesh when idle (`lod => { coarse => \%m, fine => \%m }`).
- `pivot => [x,y,z]` rotates and zooms about a chosen point (e.g. the mesh centroid), keeping the object centred.
- Clicking a vertex picks it; hover reports the vertex `x,y,z` (and an area name through an `on_pick` / `on_hover` callback).

`tools/demo_gs3d_nyhead.pl` renders a New York Head cortex mesh with a 10-20 or
`--elec` montage overlaid:

```bash
GIZA_SERVER=/path/to/giza_server perl tools/demo_gs3d_nyhead.pl \
    --lod --zbuffer --curv --recenter --pivot mesh \
    --elec /path/to/standard_1020.elc
```

It can also colour the cortex by a per-vertex **source-power** map
(`--source-power <file>`, one value per `cortex75K` vertex): an anatomical grey
base with a threshold colour overlay (`vcolor = grey·(1−α) + cmap(t)·α`,
`α = 0` below `--threshold`) so inactive cortex stays grey, plus a fixed
on-screen **colour-bar** HUD. `--cmap`, `--threshold`, `--base-grey`,
`--no-overlay`, `--no-colorbar`. This is how the New York Head inverse examples
in [`PDL-EEG`](https://github.com/goosh-gh/PDL-EEG) put e.g. an SEP N20 source
on the cortex. The colour-bar and overlay are drawn client-side (line/label
primitives), so `giza-server` needs no change.


## 3D scene export (SceneExport)

`PDL::Graphics::Cairo::SceneExport` writes the current 3D scene (the frame
sent to the Cocoa viewer) to Wavefront `.obj` or USD ASCII `.usda`, in MNI
millimetre world coordinates. It writes:

- the cortex mesh with per-vertex colours (curvature / activation);
- electrode markers as thin disc cylinders (8 mm diameter, 2 mm height)
  oriented to the scalp normal (radially outward from the head centre);
- picked seed markers, in the seed palette;
- electrode and seed labels as filled Helvetica text, placed radially and
  facing outward.

Text labels are produced by `PDL::Graphics::Cairo::LabelCairo` (glyph outlines
from cairo `text_path`, requires the `Cairo` module and a Helvetica font) and
`PDL::Graphics::Cairo::LabelGeom` (polygon-with-holes tessellation, multi-glyph
grouping, and billboard placement; pure Perl, no PDL).

Serialization follows the PDL::IO::NYHead conventions: OBJ faces 1-based,
USDA `faceVertexIndices` 0-based, `%.6f`, with `OBJ face − 1 == USDA index`.
USDA output carries `upAxis = "Z"`, `metersPerUnit = 0.001`,
`subdivisionScheme = "none"`, and `doubleSided = true` on flat disc/text
meshes.

The format core (`SceneExport`, `LabelGeom`) is pure Perl and covered by
`t/33_scene_export.t` (26 tests) and `t/34_label_geom.t` (14 tests).

Export is driven from the Cocoa giza-server viewer only (File → Export 3D as
OBJ/USDA…). The Linux Xlib viewer does not render or export 3D.


**Controls**

| Input | Action |
|---|---|
| Drag | Trackball rotation (quaternion — no gimbal lock, no poles) |
| Wheel / pinch | Zoom |
| `r` | Reset to the canonical view |
| `p` | Toggle perspective / orthographic |

**Canonical view** (what `r` restores): Fp at top, T3 on screen-left, T4 on
screen-right, Cz centred and nearest the viewer — the conventional EEG
topographic orientation, seen from above.

**Platforms:** the interactive 3D **mesh** rendering (z-buffer Gouraud, thick-fill,
adaptive LOD) is implemented in the macOS (Cocoa) `giza-server` only; the Linux
(Xlib) viewer does not render the 3D mesh. Pan is not yet
implemented on either. Requires a `giza-server` built with 3D support.

**Try it:**

```bash
GIZA_SERVER=/path/to/giza_server perl tools/demo_gs3d_electrodes.pl \
    --elc /path/to/standard_1020.elc
```

The hemispheres are coloured asymmetrically (T3 orange, T4 cyan) on purpose: a
symmetric head cannot reveal a mirrored projection, so chirality bugs would pass
unnoticed.

**Verification** — the rotation and projection are checked numerically rather
than by eye:

```bash
perl tools/verify_gs3d.pl              # structure, quaternion invariants, POD
perl tools/verify_gs3d_projection.pl   # canonical view, pole-free 2pi sweeps
```

---

## Architecture

```
PDL::Graphics::Cairo        ← this library
├── Figure                  ← canvas, layout (subplots, GridSpec, mosaic)
├── Axes                    ← one subplot: plots, axes, ticks, legends
├── Driver::Cairo           ← Cairo surface rendering (PNG/PDF/SVG)
├── Driver::GS              ← giza-server interactive display (2D)
├── Driver::GS3D            ← giza-server interactive 3D mesh surface + point cloud (trackball)
├── Interactive::Scrub      ← nearest-point / latency helper for show_grid_scrub
├── ColorMap                ← built-in colormaps
├── ListedColormap          ← discrete color lists
├── GridSpec                ← non-uniform subplot layout (height_ratios, width_ratios)
├── LTTB                    ← downsampling: lttb() and lttb_minmax() (MinMax-LTTB)
├── Transform::Linear/Log   ← data→pixel coordinate transforms
├── Scale::Log              ← log-scale tick placement
└── Tick                    ← tick generation (nice_ticks, minor_ticks)
```

---

## Performance (interactive EEG viewer, Apple Silicon M-series)

Profiled with `eeg_viewer_raw.pl` (8 ch visible × 10 s × 1 kHz, 1100×900 window):

| Step | Before | After | Change |
|------|--------|-------|--------|
| LTTB (8 ch) | 230 ms | 17 ms | `lttb_minmax` replaces per-channel Perl loop |
| PNG compress | 40 ms | 5–7 ms | `PDL::IO::PNG` level 1 + `FILTER_NONE` |
| Cairo render | 60 ms | 12–22 ms | `PDLCAIRO_RENDER_SCALE=0.5–0.75` |
| **Total/frame** | **~330 ms** | **~46 ms** | **~7× faster** |

`PDLCAIRO_RENDER_SCALE` controls render resolution (default `1.0`;
`eeg_viewer_raw.pl` sets `0.75` when it is not set): the figure
is rendered at a fraction of the window size and scaled up by the Cocoa/Xlib
viewer — no loss of interactivity.

### Grid scrub (`examples/avg_grid_scrub.pl` of PDL-EEG)

19 waveform panels and a scalp map, 1100×850 window, one frame while
dragging the latency (Apple M5 Pro, perl 5.40, PDL 2.104, `PDLCAIRO_DEBUG=1`):

| Step | 0.4 | 0.41 |
|------|-----|------|
| Cairo render | 34 ms | 13 ms |
| PNG | 20 ms | 6 ms |

The render step got faster because `imshow` (the scalp map) is drawn as one
image instead of one rectangle per cell, and the PNG step because frames are
encoded in memory with `PDL::IO::PNG::png_encode`.

---

## Status

Active development. matplotlib API coverage:

| Category | Status |
|---|---|
| Plot types | ✅ 20+ types incl. hexbin, specgram, contour/contourf, pcolormesh, plot_date |
| Axes decoration | ✅ tick_params, minor ticks, formatters, inset_axes, `set_aspect` anchor, axis-off tight margins, content-aware colorbar margin |
| Text & labels | ✅ multi-line `text()` with halign / valign / line_spacing; longest-line margin reservation for y-tick labels |
| Layouts | ✅ GridSpec (height_ratios/width_ratios), subplot_mosaic, suptitle |
| Colormaps | ✅ 12 built-in + ListedColormap |
| Normalization | ✅ Normalize, LogNorm, BoundaryNorm, TwoSlopeNorm |
| Signal analysis | ✅ specgram (STFT, windowing, dB scale) |
| Interactive (2D) | ✅ giza-server (tabs, sliders, resize, cursor/pick, zoom/pan on macOS; zoom on Xlib — pan incomplete) |
| Interactive (3D) | ✅ `Driver::GS3D` — triangle mesh surface (z-buffer Gouraud) + point markers/labels, trackball rotation, wheel zoom, adaptive LOD, vertex pick. **macOS (Cocoa) only**; the Linux (Xlib) viewer does not render the 3D mesh. Pan not yet implemented |
| Reactive controls | ✅ `param` / `button` / `on_change` bridge for App::PDL::Notebook |
| 3D mesh surface (GS3D) | ✅ triangle mesh with z-buffer Gouraud + curvature shading (EEG / anatomy viewer); no general `surf`/`mesh` plotting command |
| streamplot | 🔲 low priority |
| spine control | 🔲 low priority |

---

## What P:G:C does NOT do

To set expectations clearly:

**Out of scope (by design):**
- **General 3D surface / wireframe plotting commands** — `surf`, `mesh`, 3D contours → use `PDL::Graphics::Gnuplot` or `PDL::Graphics::TriD`.
  Note: the `Driver::GS3D` viewer *does* render a triangle **mesh surface** (z-buffer Gouraud shading) plus point markers — e.g. an EEG montage over a cortex mesh — see the 3D section above. Out of scope is a general `surf(z)` / `mesh` plotting command, not surface rendering itself.
- **Real-time animation** — frame-by-frame output is possible, but no animation API
- **pandas-style DataFrames** — Perl has no DataFrame equivalent; use PDL ndarrays directly

**Implemented via giza-server (not P:G:C/Cairo alone):**
- **Mouse-gesture pan/zoom** — P:G:C only renders static PNG/PDF/SVG; interactive pan/zoom is provided by the companion [giza-server](https://github.com/goosh-gh/giza-server) process plus `Driver::GS`. `show_interactive(zoom_pan_redraw => 1)` sends `GSP_MSG_ZOOM` to `Driver::GS`, which updates `xlim`/`ylim` and redraws at full resolution. Zoom confirmed on macOS (Cocoa) and Xlib; pan confirmed on macOS, incomplete on Xlib.

**Not yet implemented:**
- `streamplot` — streamlines for vector fields
- Spine control — `ax.spines['top'].set_visible(False)` equivalent
- `constrained_layout` — automatic margin optimization (use `tight_layout` + manual `hspace`/`wspace`)

**What this means in practice:**
For 2D scientific plotting of PDL data — line, scatter, histogram, contour, spectrogram,
hexbin, complex layouts — P:G:C handles everything. For 3D visualization, use a dedicated 3D library.

---

## License

Same as Perl itself (Artistic License 2.0 / GPL).

## Author

goosh-gh
