# PDL::Graphics::Cairo

**matplotlib-style scientific plotting for Perl/PDL, built on Cairo.**

PDL::Graphics::Cairo (P:G:C) is a high-level 2D plotting library for [PDL](https://pdl.perl.org/) that provides a matplotlib-compatible API. It handles axis scaling, tick placement, labels, legends, colormaps, and complex layouts — so you don't have to.

> Cairo is a low-level drawing API: "draw a line here", "place text there", one command at a time.  
> PDL::Graphics::Cairo is the high-level layer on top: axes, ticks, data transforms, color mapping, and layout — all done for you.

---

## Features

### Plot types
`line` · `scatter` · `bar` / `barh` · `hist` · `errorbar` · `fill_between` · `step` · `stem` · `imshow` · `contourf` · `pie` · `boxplot` · `violin` · `quiver` · `heatmap` · `stackplot` · `eventplot` · `hexbin` · `specgram` · and more

### Axes & decoration
- Auto-scaling with `tight_layout`
- Linear / log scale (`set_xscale`, `set_yscale`, `semilogy`, `loglog`)
- Tick control: `tick_params`, minor ticks, `xaxis_formatter` / `yaxis_formatter`
- Twin axes: `twinx`, `twiny`
- Inset axes: `inset_axes`
- Annotations: `annotate`, `axhline`, `axvline`, `axhspan`, `axvspan`, `text`

### Layouts
- `subplots(M, N)` — uniform grid
- `GridSpec` — non-uniform spanning panels
- `subplot_mosaic("AAB\nCDB")` — string-defined layouts
- `suptitle` — figure-level title

### Color
- Built-in colormaps: `viridis`, `plasma`, `jet`, `hot`, `cool`, `gray`, `RdBu`, `inferno`, `magma`
- `ListedColormap` — discrete color lists
- `Normalize`, `LogNorm`, `BoundaryNorm`, `TwoSlopeNorm` — data-to-color mapping

### Output
- PNG (via `PDL::IO::PNG` or Cairo), PDF, SVG
- Interactive display via `giza-server` (persistent window with tabs, sliders)
- Inline display in `App::PDL::Notebook`

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

### Spectrogram (EEG / audio analysis)

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
| `example_hexbin.pl` | 2D density, scatter vs hexbin comparison |
| `example_colormap.pl` | ListedColormap, LogNorm, TwoSlopeNorm, BoundaryNorm |
| `specgram_demo.pl` | Chirp, EEG-like, multi-tone spectrograms |
| `example_stats.pl` | Statistical plots (boxplot, violin, histogram) |
| `example_png.pl` | Basic plotting quickstart |
| `example_gs.pl` | Interactive display via giza-server |

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

## Status

Active development. matplotlib API coverage:

| Category | Status |
|---|---|
| Plot types | ✅ 20+ types |
| Axes decoration | ✅ tick_params, minor ticks, formatters |
| Layouts | ✅ GridSpec, subplot_mosaic, inset_axes |
| Colormaps | ✅ 10 built-in + ListedColormap |
| Normalization | ✅ Normalize, LogNorm, BoundaryNorm, TwoSlopeNorm |
| Signal analysis | ✅ specgram (STFT) |
| Interactive | ✅ giza-server (tabs, sliders, resize) |
| 3D plots | 🔲 not planned (use PDL::Graphics::Gnuplot) |

---

## License

Same as Perl itself (Artistic License 2.0 / GPL).

## Author

goosh-gh
