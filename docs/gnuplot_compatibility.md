# PDL::Graphics::Cairo — gnuplot-style API mapping

## Overview

If you are familiar with gnuplot, you can write plots using the
matplotlib-style API of PDL::Graphics::Cairo with similar intent.
This document maps common gnuplot commands to the equivalent
PDL::Graphics::Cairo calls.

PDL::Graphics::Cairo uses gnuplot as an optional **display backend**
(for interactive windows on Linux and macOS via AquaTerm/X11).
Rendering itself is always done by Cairo/Pango — gnuplot's coordinate
system, axes, and labels are never used.

---

## Basic example

**gnuplot script:**
```gnuplot
set xrange [-100:899]
set yrange [10:-10]           # negative up
set style line 1 lc rgb "green" lw 1.5
unset key
set label "Ch1" at 870, 9.5
plot "data.txt" with lines ls 1
```

**PDL::Graphics::Cairo equivalent:**
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
$fig->show(backend => 'osx');   # macOS native window
$fig->show();                   # gnuplot display (Linux/macOS)
$fig->save('output.png');       # set terminal png / set output
```

---

## Command mapping

| gnuplot | PDL::Graphics::Cairo |
|---------|---------------------|
| `set xrange [lo:hi]` | `$ax->xlim($lo, $hi)` |
| `set yrange [lo:hi]` | `$ax->ylim($lo, $hi)` |
| `set yrange [hi:lo]` (negative up) | `$ax->ylim($hi, $lo)` — lo > hi auto-reverses |
| `set xlabel "..."` | `$ax->xlabel("...")` |
| `set ylabel "..."` | `$ax->ylabel("...")` |
| `set title "..."` | `$ax->title("...")` |
| `set grid` | `$ax->set_grid(1)` |
| `unset grid` | `$ax->set_grid(0)` |
| `set label "..." at x,y` | `$ax->text($x, $y, "...", color=>'black')` |
| `set key` / `unset key` | `$ax->legend()` / (omit) |
| `set logscale x` | `$ax->set_xscale('log')` |
| `set logscale y` | `$ax->set_yscale('log')` |
| `plot ... with lines lc "green" lw 2` | `$ax->line($x,$y, color=>'green', lw=>2)` |
| `plot ... with points` | `$ax->scatter($x, $y)` |
| `plot ... with linespoints` | `$ax->line($x,$y)` + `$ax->scatter($x,$y)` |
| `plot ... with boxes` | `$ax->bar($x, $y)` |
| `plot ... with yerrorbars` | `$ax->errorbar($x,$y, yerr=>$err)` |
| `set terminal png; set output "f.png"` | `$fig->save('f.png')` |
| `set terminal pdf; set output "f.pdf"` | `$fig->save('f.pdf')` |
| `set multiplot layout 2,2` | `my ($fig,$axes) = subplots(2,2)` |
| `set arrow from x1,y1 to x2,y2` | `$ax->annotate("", xy=>[$x2,$y2], xytext=>[$x1,$y1])` |
| `set xtics (...)` | `$ax->xticks([...], [...])` |
| `set ytics (...)` | `$ax->yticks([...], [...])` |

---

## Margin control

gnuplot provides `set lmargin`, `set rmargin`, `set tmargin`, `set bmargin`
for margin adjustment. However, when using `set multiplot` with multiple
panels, each panel's margins must be set individually — there is no
automatic calculation that accounts for varying label lengths, titles,
or colorbars across panels.

PDL::Graphics::Cairo handles this automatically via `tight_layout()`:

```perl
my ($fig, $axes) = subplots(2, 2, width => 1000, height => 800);
# ... plot into each $axes->[i][j] ...
$fig->tight_layout();   # margins computed per-panel automatically
$fig->show();
```

`tight_layout()` calculates margins based on the presence of titles,
axis labels, colorbars, and twin axes for each panel independently.

---

## Display backends

PDL::Graphics::Cairo uses gnuplot only as a **display window provider**,
not for rendering. The plot is rendered by Cairo and passed to gnuplot
as a PNG image:

```
Cairo renders → PNG tempfile → gnuplot displays (unset border/tics/key)
```

This means gnuplot's own axis drawing, labels, and coordinate system
are suppressed — only the Cairo-rendered image is shown in the window.

### Supported display terminals

| Device string | Terminal | Platform |
|---------------|----------|----------|
| `/osx` | pdlcairo_viewer (native Cocoa) | macOS only |
| `/aqua` `/aqt` | gnuplot aqua (AquaTerm) | macOS |
| `/xw` `/xwin` `/x11` `/xserve` | gnuplot x11 | Linux, macOS+XQuartz |
| `/wxt` | gnuplot wxt (wxWidgets) | Linux, macOS |
| `/qt` | gnuplot qt | Linux, macOS |
| `file.png/PNG` | PNG file | all |
| `file.pdf/PDF` | PDF file | all |
| `file.svg/SVG` | SVG file | all |

---

## What gnuplot can do that PDL::Graphics::Cairo cannot

| Feature | gnuplot | PDL::Graphics::Cairo |
|---------|---------|---------------------|
| 3D surface plot (`splot`) | ✅ | ❌ |
| Animation (`set terminal gif`) | ✅ | ❌ |
| Interactive data fitting | ✅ | ❌ |
| Arbitrary terminal types | ✅ | PNG/PDF/SVG + display |
| Direct PDL ndarray input | ❌ (file/pipe) | ✅ |
| PGPLOT script migration | ❌ | ✅ drop-in layer |
| macOS native window | ❌ (AquaTerm/X11) | ✅ |
| Automatic margin layout | ⚠️ `set margins` available but no auto-calculation across multi-panel labels | ✅ `tight_layout()` computes per-panel margins automatically |
| Cairo/Pango text quality | ❌ | ✅ |

