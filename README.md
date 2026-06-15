# PDL::Graphics::Cairo

**matplotlib-style scientific plotting for Perl/PDL, built on Cairo.**

PDL::Graphics::Cairo (P:G:C) is a high-level 2D plotting library for [PDL](https://pdl.perl.org/) that provides a matplotlib-compatible API. It handles axis scaling, tick placement, labels, legends, colormaps, and complex layouts — so you don't have to.

> Cairo is a low-level drawing API: "draw a line here", "place text there", one command at a time.  
> PDL::Graphics::Cairo is the high-level layer on top: axes, ticks, data transforms, color mapping, and layout — all done for you.

---

## Features

### Plot types
`line` · `scatter` · `bar` / `barh` · `hist` · `errorbar` · `fill_between` · `step` · `stem` · `imshow` · `contour` · `contourf` · `pie` · `boxplot` · `violin` · `quiver` · `heatmap` · `stackplot` · `eventplot` · `hexbin` · `specgram` · and more

### Axes & decoration
- Auto-scaling with `tight_layout`; `uniform_margins => 1` option ensures all panels have identical plot-area dimensions in multi-panel grids (avoids the default asymmetry where edge panels receive larger margins)
- Linear / log scale (`set_xscale`, `set_yscale`, `semilogy`, `loglog`)
- Tick control: `tick_params`, minor ticks, `xaxis_formatter` / `yaxis_formatter`
- Twin axes: `twinx`, `twiny`
- Inset axes: `inset_axes`
- Annotations: `annotate`, `axhline`, `axvline`, `axhspan`, `axvspan`, `text`

### Layouts
- `subplots(M, N)` — uniform grid
- `GridSpec` — non-uniform spanning panels, now with **`height_ratios`/`width_ratios`** for per-row/column size control
- `subplot_mosaic("AAB\nCDB")` — string-defined layouts
- `suptitle` — figure-level title

### Color
- Built-in colormaps: `viridis`, `plasma`, `jet`, `hot`, `cool`, `gray`, `RdBu`, `inferno`, `magma`, `coolwarm`
- `ListedColormap` — discrete color lists
- `Normalize`, `LogNorm`, `BoundaryNorm`, `TwoSlopeNorm` — data-to-color mapping

### Output
- PNG (via `PDL::IO::PNG` or Cairo), PDF, SVG
- Interactive display via `giza-server` (persistent window with tabs, sliders)
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

### Spectrogram ( audio analysis)

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
| `example_gridspec.pl` | GridSpec, subplot_mosaic layouts |
| `eeg_viewer_raw.pl` | MNE `raw.plot()`-style multi-channel EEG viewer; real-time LTTB, channel scroll, time window, page buttons |
| `example_hexbin.pl` | 2D density, scatter vs hexbin comparison |
| `example_colormap.pl` | ListedColormap, LogNorm, TwoSlopeNorm, BoundaryNorm |
| `specgram_demo.pl` | Chirp, EEG-like, multi-tone spectrograms |
| `example_contour.pl` | contour/contourf: sincos overlay, 4-panel gallery, topographic map |
| `example_stats.pl` | Statistical plots (boxplot, violin, histogram) |
| `example_png.pl` | Basic plotting quickstart |
| `example_gs.pl` | Interactive display via giza-server |
| `example_gs_cursor_overlay.pl` | Cursor coordinate overlay with mouse tracking |

---

## Architecture

```
PDL::Graphics::Cairo        ← this library
├── Figure                  ← canvas, layout (subplots, GridSpec, mosaic)
├── Axes                    ← one subplot: plots, axes, ticks, legends
├── Driver::Cairo           ← Cairo surface rendering (PNG/PDF/SVG)
├── Driver::GS              ← giza-server interactive display
├── ColorMap                ← built-in colormaps
├── ListedColormap          ← discrete color lists
├── GridSpec                ← non-uniform subplot layout
├── Transform::Linear/Log   ← data→pixel coordinate transforms
├── Scale::Log              ← log-scale tick placement
└── Tick                    ← tick generation (nice_ticks, minor_ticks)
```

---

## Performance (interactive EEG viewer, Apple Silicon M-series)

Profiled with `eeg_viewer_raw.pl` (8 ch × 10 s × 1 kHz, 1100×900 window):

| Step | Before | After | Change |
|------|--------|-------|--------|
| LTTB (8 ch) | 230 ms | 17 ms | `lttb_minmax` replaces Perl loop |
| PNG compress | 40 ms | 5–7 ms | `PDL::IO::PNG` level 1 + FILTER_NONE |
| Cairo render | 60 ms | 12–22 ms | `PDLCAIRO_RENDER_SCALE=0.5–0.75` |
| **Total/frame** | **~330 ms** | **~46 ms** | **~7× faster** |

`PDLCAIRO_RENDER_SCALE` env var controls the render resolution (default 0.75):
the viewer renders at a fraction of the window size; the Cocoa/Xlib viewer
scales up automatically with no loss of interactivity.

## Status

Active development. matplotlib API coverage:

| Category | Status |
|---|---|
| Plot types | ✅ 20+ types incl. hexbin, specgram, contour/contourf |
| Axes decoration | ✅ tick_params, minor ticks, formatters, inset_axes |
| Layouts | ✅ GridSpec, subplot_mosaic, suptitle |
| Colormaps | ✅ 12 built-in + ListedColormap |
| Normalization | ✅ Normalize, LogNorm, BoundaryNorm, TwoSlopeNorm |
| Signal analysis | ✅ specgram (STFT, windowing, dB scale) |
| Interactive | ✅ giza-server (tabs, sliders, resize, cursor/pick, zoom/pan) |
| 3D plots | 🔲 not planned (use PDL::Graphics::Gnuplot) |
| streamplot | 🔲 low priority |
| spine control | 🔲 low priority |

---

## What P:G:C does NOT do

To set expectations clearly:

**Out of scope (by design):**
- **3D plots** — surface, 3D scatter, wireframe → use `PDL::Graphics::Gnuplot` or `PDL::Graphics::TriD`
- **Interactive pan/zoom** — mouse-driven navigation (giza-server sliders are separate)
- **Real-time animation** — frame-by-frame output is possible, but no animation API
- **pandas-style DataFrames** — Perl has no DataFrame equivalent; use PDL ndarrays directly

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
