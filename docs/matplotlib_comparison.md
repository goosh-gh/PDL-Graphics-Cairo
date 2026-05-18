# PDL::Graphics::Cairo vs matplotlib — API Comparison

## Overview

PDL::Graphics::Cairo is a Perl plotting library designed as a matplotlib-equivalent
for PDL (Perl Data Language). It also provides a PGPLOT compatibility layer
(`PDL::Graphics::Cairo::PGPLOT`) for legacy code migration.

---

## Quick Comparison

| Feature | matplotlib (Python) | PDL::Graphics::Cairo (Perl) |
|---------|--------------------|-----------------------------|
| Backend | Agg, Cairo, Qt, etc. | Cairo + Pango |
| Output | PNG, PDF, SVG, screen | PNG, PDF, SVG, gnuplot interactive |
| Figure/Axes model | `fig, ax = plt.subplots()` | `$fig = figure(); $ax = $fig->axes()` |
| Subplot | `plt.subplot(2,3,1)` | `$ax = $fig->subplot(2,3,1)` |
| Line plot | `ax.plot(x, y)` | `$ax->line($x, $y)` |
| Scatter | `ax.scatter(x, y)` | `$ax->scatter($x, $y)` |
| Histogram | `ax.hist(data)` | `$ax->hist($data)` |
| Image | `ax.imshow(data)` | `$ax->imshow($data)` |
| Colorbar | `plt.colorbar()` | `$ax->colorbar()` |
| Color cycle | tab10 (default) | tab10 (same default) |
| PGPLOT compat | — | `PDL::Graphics::Cairo::PGPLOT` |

---

## Code Examples

### Line Plot

**matplotlib:**
```python
import matplotlib.pyplot as plt
import numpy as np

x = np.linspace(0, 10, 100)
fig, ax = plt.subplots()
ax.plot(x, np.sin(x), color='blue', label='sin')
ax.plot(x, np.cos(x), color='red',  label='cos')
ax.set_xlabel('x'); ax.set_ylabel('y'); ax.set_title('sin/cos')
ax.legend()
fig.savefig('output.png')
```

**PDL::Graphics::Cairo:**
```perl
use PDL;
use PDL::Graphics::Cairo qw(figure);

my $x   = sequence(100) / 10;
my $fig = figure(width=>600, height=>400);
my $ax  = $fig->axes();
$ax->line($x, sin($x), color=>'blue', label=>'sin');
$ax->line($x, cos($x), color=>'red',  label=>'cos');
$ax->xlabel('x'); $ax->ylabel('y'); $ax->title('sin/cos');
$ax->legend();
$fig->save('output.png');
```

---

### Subplots

**matplotlib:**
```python
fig, axes = plt.subplots(2, 3, figsize=(12, 8))
for i, ax in enumerate(axes.flat):
    ax.plot(x, np.sin(x + i))
```

**PDL::Graphics::Cairo:**
```perl
my $fig = figure(width=>1200, height=>800);
for my $i (1..6) {
    my $ax = $fig->subplot(2, 3, $i);
    $ax->line($x, sin($x + $i - 1));
}
$fig->save('output.png');
```

---

### Colormaps

Both support the same colormap names:

| Colormap | Description |
|----------|-------------|
| `viridis` | Perceptually uniform (default for imshow) |
| `plasma` | Perceptually uniform, warm |
| `jet` | Rainbow (legacy) |
| `hot` | Black→red→yellow→white |
| `cool` | Cyan→magenta |
| `gray` | Grayscale |
| `RdBu` | Red-White-Blue diverging |

---

### Statistical Plots

**matplotlib:**
```python
ax.boxplot(data)
ax.violinplot(data)
```

**PDL::Graphics::Cairo:**
```perl
$ax->boxplot(\@data);
$ax->violinplot(\@data);
$ax->errorbar_stats(\@data, type=>'sem');  # SEM error bars
$ax->hist_kde($data);                       # histogram + KDE overlay
$ax->qqplot($data);                         # Q-Q plot vs normal
```

---

## PGPLOT Migration

For existing PGPLOT scripts, use the compatibility layer:

```perl
# Original PGPLOT code (unchanged):
use PDL::Graphics::Cairo::PGPLOT qw(:all);

pgbegin(0, "output.png/PNG", 1, 1);
pgenv(0, 10, -1, 1, 0, 1);
pgsci(3);
pgline($n, $x, $y);
pgend();
```

Key differences from original PGPLOT:
- No X11/libgiza required
- `PGPLOT_BACKGROUND=black` for dark background
- `/XW`, `/X11`, `/AQT` devices route through gnuplot
- `pgbox("ANST","ANTV")` draws axes on x=0/y=0 lines (not border)
- Negative ymin/ymax in `pgenv` reverses Y axis (EEG convention)

---

## Performance Notes

- Cairo rendering is done entirely in Perl/C — no gnuplot subprocess for file output
- For interactive display (`/XW`, `/AQT`), gnuplot is called as a subprocess
- NDArray (PDL) data is passed directly — no Python-style array copies
- 6×6 multi-panel layout (36 panels, 1000 points each): < 1 second on modern hardware

---

## Dependencies

```
# Required
Cairo          (perl Cairo bindings)
Pango          (text rendering)
Moo            (object system)
PDL            (array operations)

# Optional
gnuplot        (interactive display)
PDL::Stats     (boxplot, violinplot, errorbar_stats)
```

Install:
```bash
cpanm Cairo Pango Moo
# gnuplot via system package manager
```
