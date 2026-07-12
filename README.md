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
- Auto-scaling with `tight_layout`; `uniform_margins => 1` option ensures all panels have identical plot-area dimensions in multi-panel grids (avoids the default asymmetry where edge panels receive larger margins)
- Linear / log scale (`set_xscale`, `set_yscale`, `semilogy`, `loglog`)
- Tick control: `tick_params`, minor ticks, `xaxis_formatter` / `yaxis_formatter`
- Date/time axis: `plot_date` accepts UNIX epoch values or `DateTime` objects; tick spacing and label format (`HH:MM`, `Mon DD`, `Mon YYYY`, `YYYY`) are chosen automatically based on the data range
- Twin axes: `twinx` (shared X, independent Y on the right), `twiny` (shared Y, independent X on top) — combinable on the same parent Axes
- Inset axes: `inset_axes`
- Annotations: `annotate`, `axhline`, `axvline`, `axhspan`, `axvspan`, `text`
- `scatter` marker styles: `o s ^ v < > d + x p h * P X` (14 styles, covering most matplotlib marker shorthands)
- `bar` / `barh` error bars (`yerr`, symmetric or `yerr_low`/`yerr_high` for asymmetric) and grouped bars (call `bar()` multiple times with shifted `x` and a shared `width`, matplotlib-style)

### Layouts
- `subplots(M, N)` — uniform grid
- `GridSpec` — non-uniform spanning panels, with **`height_ratios`/`width_ratios`** for per-row/column size control
- `subplot_mosaic("AAB\nCDB")` — string-defined layouts
- `suptitle` — figure-level title

### Color
- Built-in colormaps: `viridis`, `plasma`, `jet`, `hot`, `cool`, `gray`, `RdBu`, `inferno`, `magma`, `coolwarm`
- `ListedColormap` — discrete color lists
- `Normalize`, `LogNorm`, `BoundaryNorm`, `TwoSlopeNorm` — data-to-color mapping
- `colorbar(label => '...')` — colorbar with an optional title, placed on any side (`top`/`bottom`/`left`/`right`)
- `pcolormesh` / `pcolor` — pseudocolor plots on a non-uniform grid (unlike `imshow`, cell boundaries don't need to be equally spaced)

### Output
- PNG (via `PDL::IO::PNG` or Cairo), PDF, SVG
- Interactive display via `giza-server` (persistent window with tabs, sliders, resize, cursor/pick). Slider values arrive normalized `[0,1]` (the client assigns each slider's meaning); `show_interactive(init => { 0 => ..., 1 => ... })` sets each slider's initial thumb position.
- Interactive **3D point-cloud viewer** via `Driver::GS3D` (see [3D](#3d-drivergs3d) below) — quaternion trackball rotation, wheel zoom; macOS (Cocoa) and Linux (Xlib)
- Inline display in `App::PDL::Notebook` (via `$fig->to_inline`)

### Downsampling
- `PDL::Graphics::Cairo::LTTB` — Largest-Triangle-Three-Buckets downsampling
  - `lttb($x, $y, $n_out)` — original LTTB (Steinarsson 2013), spike-preserving
  - `lttb_minmax($x, $y, $n_out)` — **MinMax-LTTB** (v0.05+): selects min+max per bucket; pure PDL vector ops, ~10× faster than original LTTB for interactive use
- Preserves visual spikes (EOG artifacts, transients) unlike simple decimation
- Used automatically in `eeg_viewer_raw.pl` and `eeg_viewer.pl`

### Compatibility layers
- matplotlib API (`line`, `scatter`, `set_xlim`, `tick_params`, ...)
- PGPLOT API (`env`, `line`, `points`, `pgbox`, ...)
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

Interactive 3D **point-cloud** viewer built on `giza-server`. Intended for spatial
layouts such as EEG electrode montages — not a general 3D plotting API (no surface
or wireframe; see "What P:G:C does NOT do").

```perl
use PDL;
use PDL::Graphics::Cairo::Driver::GS3D;

my $drv = PDL::Graphics::Cairo::Driver::GS3D->new(
    scene  => { points => $pts,        # [N,3] world XYZ
                colors => $rgb,        # [N,3] 0..1
                labels => \@names },
    width  => 700, height => 700,
);
$drv->run;                              # blocks; drives the interactive loop
```

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

**Platforms:** macOS (Cocoa) and Linux (Xlib), at feature parity. Pan is not yet
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
├── Driver::GS3D            ← giza-server interactive 3D point cloud (trackball)
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

`PDLCAIRO_RENDER_SCALE` controls render resolution (default `0.75`): the figure
is rendered at a fraction of the window size and scaled up by the Cocoa/Xlib
viewer — no loss of interactivity.

---

## Status

Active development. matplotlib API coverage:

| Category | Status |
|---|---|
| Plot types | ✅ 20+ types incl. hexbin, specgram, contour/contourf, pcolormesh, plot_date |
| Axes decoration | ✅ tick_params, minor ticks, formatters, inset_axes |
| Layouts | ✅ GridSpec (height_ratios/width_ratios), subplot_mosaic, suptitle |
| Colormaps | ✅ 12 built-in + ListedColormap |
| Normalization | ✅ Normalize, LogNorm, BoundaryNorm, TwoSlopeNorm |
| Signal analysis | ✅ specgram (STFT, windowing, dB scale) |
| Interactive (2D) | ✅ giza-server (tabs, sliders, resize, cursor/pick, zoom/pan on macOS; zoom on Xlib — pan incomplete) |
| Interactive (3D) | ✅ `Driver::GS3D` — point cloud, trackball rotation, wheel zoom; macOS + Linux (pan not yet implemented) |
| Reactive controls | ✅ `param` / `button` / `on_change` bridge for App::PDL::Notebook |
| 3D surface / wireframe | 🔲 not planned (use PDL::Graphics::Gnuplot) — but interactive 3D **point clouds** are supported, see `Driver::GS3D` |
| streamplot | 🔲 low priority |
| spine control | 🔲 low priority |

---

## What P:G:C does NOT do

To set expectations clearly:

**Out of scope (by design):**
- **3D surface / wireframe plots** — `surf`, `mesh`, 3D contours → use `PDL::Graphics::Gnuplot` or `PDL::Graphics::TriD`.
  Note: interactive 3D **point clouds** (e.g. EEG electrode montages) *are* supported via `Driver::GS3D` — see the 3D section above.
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
