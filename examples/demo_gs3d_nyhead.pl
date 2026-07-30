#!/usr/bin/env perl
# demo_gs3d_nyhead.pl — real New York Head surfaces in the GS3D viewer (spin/grigri),
#                       now loaded through PDL::IO::NYHead 0.02.
#
# What changed vs the old ad-hoc loader version:
#   * All loading goes through PDL::IO::NYHead (surface/cortex/leadfield/atlas/
#     electrodes). The hand-rolled HDF5 readers, HO_labels.txt parsing and
#     V_fem_normal slurp are gone — NYHead does the axis-transpose, 1/0-based
#     face handling and in_from_cortex75K reconstruction with PDL fancy-index.
#   * --lod : adaptive level-of-detail. While you drag (rotate/zoom) the mesh
#     is drawn coarse (cortex2K solid) so the spin stays snappy; when you stop
#     for IDLE_SEC the viewer swaps once to a fine mesh (cortex10K solid) — the
#     spin speed is set by the coarse LOD, the still-image sharpness by the fine
#     LOD, so grigri never slows down but the picture refines the instant you
#     let go. pick/hover always resolve against the fine mesh (GS3D guarantees
#     this), so a picked vertex maps cleanly to its 75K index via in_from.
#
# The face pipeline (project -> cull -> painter sort -> flat Lambert -> scanline
# line-segments) is unchanged and needs no giza-server change. Convex /sa/head
# is clean; concave cortex has painter self-occlusion + scanline striping at high
# zoom (that ceiling is why LOD schedules quality rather than fighting it; exact
# occlusion is a GPU/z-buffer job).
#
# Usage:
#   perl tools/demo_gs3d_nyhead.pl                          # scalp head + real 19 electrodes
#   perl tools/demo_gs3d_nyhead.pl --no-electrodes          # mesh only
#   perl tools/demo_gs3d_nyhead.pl --surf cortex2K --no-electrodes   # one cortex LOD (speed probe)
#   perl tools/demo_gs3d_nyhead.pl --lod                    # adaptive LOD: drag=cortex2K / idle=cortex10K
#   perl tools/demo_gs3d_nyhead.pl --lod --coarse cortex2K --fine cortex5K
#   perl tools/demo_gs3d_nyhead.pl --lod --forward          # pick a source -> project leadfield topo onto 231 electrodes
#   perl tools/demo_gs3d_nyhead.pl --elc ~/src/NYHead/standard_1020.elc   # full montage overrides the built-in 19
#   PDLCAIRO_DEBUG=1 perl tools/demo_gs3d_nyhead.pl --surf cortex75K      # front-face / fill-line counts
#
# Controls: drag = rotate, wheel = zoom, click a face = add seed (colour + HO area
#   label), 'u' = undo last seed, 'c' = clear seeds, 'r' = reset view. Hovering a
#   face shows x,y,z + HO area name top-left (before you click).
#
# Deps: PDL::IO::NYHead 0.02 (which needs PDL::IO::HDF5 + the h5dump CLI for the
#   Harvard-Oxford area *names*; numeric atlas index works without h5dump).
#   --elc uses PDL::EEG::IO::ASA (only when given).

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use PDL;
use PDL::Primitive;                 # indadd (curvature accumulation)
use PDL::IO::NYHead;
use PDL::Graphics::Cairo::Driver::GS3D;

my %o = (
    mat        => "$ENV{HOME}/src/NYHead/sa_nyhead.mat",
    surf       => 'head',        # single-mesh mode: head | cortex75K | cortexNK
    lod        => 0,             # adaptive LOD (ignores --surf; uses --coarse/--fine)
    coarse     => 'cortex2K',    # LOD: mesh shown while dragging (kept light)
    fine       => 'cortex10K',   # LOD: mesh shown at idle (refined)
    elc        => undef,         # full electrode montage (.elc); overrides built-in 19
    electrodes => 1,             # overlay the real NY Head 19 (10-20); --no-electrodes to disable
    forward    => 0,             # pick source -> colour the 231 model electrodes by leadfield topo
    elec_orig  => 1,             # default = /sa/locs_3D_orig (true scalp positions). --no-elec-orig uses on-mesh locs_3D
    curv       => 0,             # curvature 2-tone shading on cortex (sulci dark / gyri light)
    curv_gain  => 1.0,           # curvature contrast (higher = stronger dark/light split)
    snap       => 0,             # snap electrodes to nearest scalp vertex + lift (display only)
    proud      => 3,             # snap lift outward (mm)
    zoom       => 1.0,
    fill_step  => 1,
    wire       => 0,
    thick_fill => 1,             # draw fill spans as bars (kills zoom striping); needs new giza-server
    zbuffer    => 0,             # z-buffer triangle rasteriser (Gouraud, correct occlusion); needs new giza-server
    recenter   => 0,             # opt-in view centering on a pivot (--pivot); off by default
    pivot      => 'mesh',        # pivot: mesh(cortex centroid) | head | electrodes | combined
    width      => 720,
    height     => 720,
);
GetOptions(
    'mat=s'       => \$o{mat},
    'surf=s'      => \$o{surf},
    'lod!'        => \$o{lod},
    'coarse=s'    => \$o{coarse},
    'fine=s'      => \$o{fine},
    'elc|elec=s'  => \$o{elc},
    'electrodes!' => \$o{electrodes},
    'forward!'    => \$o{forward},
    'elec-orig!'  => \$o{elec_orig},
    'curv!'       => \$o{curv},
    'curv-gain=f' => \$o{curv_gain},
    'snap!'       => \$o{snap},
    'proud=f'     => \$o{proud},
    'zoom=f'      => \$o{zoom},
    'fill-step=f' => \$o{fill_step},
    'wire'        => \$o{wire},
    'thick-fill!' => \$o{thick_fill},
    'zbuffer!'    => \$o{zbuffer},
    'recenter!'   => \$o{recenter},
    'pivot=s'     => \$o{pivot},
    'width=i'     => \$o{width},
    'height=i'    => \$o{height},
) or die "bad args\n";
-f $o{mat} or die "not found: $o{mat}\n  (--mat to point at sa_nyhead.mat)\n";

my $ny = PDL::IO::NYHead->new($o{mat});

# ---- Harvard-Oxford atlas: names need h5dump; numeric index does not ----------
my $ho_names = eval { $ny->ho_labels };            # 97 names, or undef if h5dump missing
warn "HO area names unavailable (h5dump?); showing numeric atlas index only\n"
    unless $ho_names;
my $atlas = eval { $ny->atlas_index };             # (74382) 1-based, 0=none (no h5dump needed)

# 0-based 75K vertex -> display string  e.g. "Precentral Gyrus (7)" or "HO#7"
sub area_of {
    my ($v75) = @_;
    return '' unless defined $v75 && defined $atlas;
    my $idx = $atlas->at($v75);                    # 1-based, 0 = outside atlas
    return sprintf('HO#%d', $idx) unless $ho_names && $idx > 0;
    my $name = $ho_names->[$idx - 1] // "HO#$idx";
    return "$name ($idx)";
}

# ---- curvature shading (server-free) -----------------------------------------
# Discrete mean-curvature proxy computed from the mesh itself (no shipped curv
# field needed; works at any LOD). >0 = convex (gyrus, light), <0 = concave
# (sulcus, dark). Verified on sphere (convex) and saddle (mixed). Returns per-
# face RGB (Nf,3) for GS3D's flat fill (mesh->{colors} x Lambert).
sub _cross3 {                                      # a,b : (N,3) -> (N,3)
    my ($a, $b) = @_;
    my ($ax,$ay,$az) = ($a->slice(':,(0)'),$a->slice(':,(1)'),$a->slice(':,(2)'));
    my ($bx,$by,$bz) = ($b->slice(':,(0)'),$b->slice(':,(1)'),$b->slice(':,(2)'));
    return cat($ay*$bz-$az*$by, $az*$bx-$ax*$bz, $ax*$by-$ay*$bx);
}
sub _norm3 {                                       # (N,3) -> unit (N,3)
    my ($v) = @_;
    my $l = sqrt(($v*$v)->slice(':,(0)') + ($v*$v)->slice(':,(1)') + ($v*$v)->slice(':,(2)'));
    return $v / ($l->dummy(1) + 1e-12);
}
sub curvature_face_colors {
    my ($V, $F, $gain) = @_;
    $gain ||= 1.0;
    my $Nv = $V->dim(0);
    my $a  = $F->slice(':,(0)')->flat->long;
    my $b  = $F->slice(':,(1)')->flat->long;
    my $c  = $F->slice(':,(2)')->flat->long;
    my ($Va,$Vb,$Vc) = ($V->dice_axis(0,$a), $V->dice_axis(0,$b), $V->dice_axis(0,$c));

    # vertex normals: accumulate face normals, then orient outward by a global
    # centroid vote (winding-independent, so sulci reliably come out dark).
    my $fn = _cross3($Vb-$Va, $Vc-$Va);
    my @vn;
    for my $k (0..2) {
        my $acc = zeroes($Nv); my $fk = $fn->slice(":,($k)")->sever;
        indadd($fk,$a,$acc); indadd($fk,$b,$acc); indadd($fk,$c,$acc);
        push @vn, $acc;
    }
    my $vn  = _norm3(cat(@vn));
    my $rad = $V - $V->average->dummy(0);
    my $al  = $vn->slice(':,(0)')*$rad->slice(':,(0)')
            + $vn->slice(':,(1)')*$rad->slice(':,(1)')
            + $vn->slice(':,(2)')*$rad->slice(':,(2)');
    $vn = $vn * (($al->avg < 0) ? -1 : 1);

    # uniform Laplacian (mean neighbour - v); curvature = -(lap . n)
    my $src = $a->glue(0,$b,$b,$c,$c,$a);
    my $dst = $b->glue(0,$a,$c,$b,$a,$c);
    my $Vd  = $V->dice_axis(0,$dst);
    my @ns;
    for my $k (0..2) {
        my $acc = zeroes($Nv);
        indadd($Vd->slice(":,($k)")->sever, $src, $acc);
        push @ns, $acc;
    }
    my $nsum = cat(@ns);
    my $cnt  = zeroes($Nv); indadd(ones($src->nelem), $src, $cnt);
    $cnt = $cnt->clip(1, undef);
    my $lap  = $nsum/$cnt->dummy(1) - $V;
    my $curv = -( $lap->slice(':,(0)')*$vn->slice(':,(0)')
                + $lap->slice(':,(1)')*$vn->slice(':,(1)')
                + $lap->slice(':,(2)')*$vn->slice(':,(2)') );

    # normalise by spread, map to grey albedo (sulcus ~.45, gyrus ~.95)
    my $mean = $curv->avg;
    my $sd   = (($curv-$mean)**2)->avg->sqrt; $sd = 1e-9 if $sd <= 0;
    my $t    = ($curv/(2*$sd*$gain))->clip(-1,1);
    my $g    = (0.70 + 0.25*$t)->clip(0.35,1.0);
    my $base = pdl(0.90, 0.86, 0.88);              # faint warm tint
    my $vcol = $g->dummy(1) * $base->dummy(0);      # (Nv,3)

    # per-vertex -> per-face (flat fill uses one colour per triangle)
    my $fcol = ($vcol->dice_axis(0,$a) + $vcol->dice_axis(0,$b) + $vcol->dice_axis(0,$c)) / 3;
    return $fcol;                                  # (Nf,3)
}

# ---- mesh builder: NYHead {vc, tri0(0-based)} straight into the GS3D contract --
# returns ($mesh_hashref, $in_from) where $in_from is a (M) 0-based 75K-index
# piddle for cortex meshes (undef for the scalp head, which has no cortical map).
my %RES_OK = map { $_ => 1 } $ny->cortex_resolutions;   # e.g. cortex1K/2K/5K/10K/75K
sub build_mesh {
    my ($res) = @_;
    $res =~ s{^/sa/}{};                            # tolerate old '/sa/cortex2K' spelling
    unless ($res eq 'head' || $RES_OK{$res}) {
        die "unknown surface '$res'. available: head, "
          . join(', ', sort keys %RES_OK) . "\n";
    }
    my $is_cx = ($res ne 'head');
    my $g = ($res eq 'head') ? $ny->surface('head')   # {vc, tri, tri0}
                             : $ny->cortex($res);      # {vc, tri, tri0, in_from}
    my $mesh = {
        verts     => $g->{vc},                     # (Nv,3)
        faces     => $g->{tri0},                   # (Nf,3) 0-based
        color     => $is_cx ? [0.82, 0.78, 0.80]   # cortex: pale grey-pink
                            : [0.86, 0.78, 0.70],   # scalp:  warm grey
        light     => [0.3, 0.45, 1.0],             # view space: front-up-right
        ambient   => 0.28,
        winding   => 'auto',                       # centroid-outward majority vote
        fill_step => $o{wire} ? 4 : $o{fill_step},
    };
    # curvature 2-tone shading (server-free): sulci dark / gyri light. Per-face
    # albedo goes in mesh->{colors}, which GS3D already multiplies by Lambert.
    # Same path the inverse-solution source colouring will later reuse.
    if ($o{curv} && $is_cx) {
        $mesh->{colors} = curvature_face_colors($g->{vc}, $g->{tri0}, $o{curv_gain});
    }
    return ($mesh, $g->{in_from});                 # in_from: cortex()=defined, surface(head)=undef
}

# ---- assemble scene + optional LOD -------------------------------------------
my ($scene, $lod, $in_from_pick);
if ($o{lod}) {
    my ($mc)      = build_mesh($o{coarse});
    my ($mf, $if) = build_mesh($o{fine});
    $lod          = { coarse => $mc, fine => $mf };
    $in_from_pick = $if;                           # picks resolve on the fine mesh
    $scene        = { mesh => $mf };               # idle look by default
    printf STDERR "LOD: drag=%s (%d faces) / idle=%s (%d faces)\n",
        $o{coarse}, $mc->{faces}->dim(0), $o{fine}, $mf->{faces}->dim(0);
} else {
    my ($m, $if)  = build_mesh($o{surf});
    $in_from_pick = $if;
    $scene        = { mesh => $m };
    printf STDERR "surface: %s (%d faces)\n", $o{surf}, $m->{faces}->dim(0);
}
printf STDERR "curvature shading: on (gain %.2f)\n", $o{curv_gain} if $o{curv};
printf STDERR "render: z-buffer triangle rasteriser (Gouraud); needs new giza-server\n" if $o{zbuffer};

# ---- electrodes ---------------------------------------------------------------
# --forward shows the 231 model electrodes (1:1 with the leadfield rows) and
# and recolours them on pick. Otherwise the labelled 19 (real MNI, not a sphere
# approximation) unless --elc gives a full montage. Points draw after the mesh
# (separate list) so they sit in front of the scalp = montage stays visible.
sub elec_pos_all {                                 # -> (231,3) MNI mm on the scalp
    my ($ny, $use_orig) = @_;
    return $ny->electrode_pos if $use_orig;        # /sa/locs_3D_orig (unregistered template)
    my $l3 = eval { $ny->_get('/sa/locs_3D') };    # (231,6) = [x y z nx ny nz], registered on scalp
    return (defined $l3 && ref $l3) ? $l3->slice(':,0:2')->sever : $ny->electrode_pos;
}

if ($o{forward}) {
    my $pos = elec_pos_all($ny, $o{elec_orig});    # (231,3) registered
    my $n   = $pos->dim(0);
    $scene->{points} = $pos;
    $scene->{colors} = pdl([ [(0.7)x$n], [(0.7)x$n], [(0.7)x$n] ]);   # start grey
    printf STDERR "forward: %d %s electrodes shown; pick a source to project its leadfield topo\n",
        $n, $o{elec_orig} ? 'template(locs_3D_orig)' : 'registered';
}
elsif ($o{electrodes} || defined $o{elc}) {
    my (@ex, @ey, @ez, @lab);
    if (defined $o{elc}) {
        -f $o{elc} or die "not found: $o{elc}\n";
        require PDL::EEG::IO::ASA; PDL::EEG::IO::ASA->import('read_elc');
        my $elc    = read_elc($o{elc});            # { coords => PDL [3,N], labels => [...] }
        my $coords = $elc->{coords};
        my @d      = $coords->dims;
        $coords    = $coords->transpose->copy if @d == 2 && $d[0] == 3;   # -> (N,3)
        @ex  = $coords->slice(':,(0)')->list;
        @ey  = $coords->slice(':,(1)')->list;
        @ez  = $coords->slice(':,(2)')->list;
        @lab = (ref $elc->{labels} eq 'ARRAY') ? @{$elc->{labels}} : map { "E$_" } 1 .. scalar(@ex);
    } else {
        my $p = elec_pos_all($ny, $o{elec_orig})->dice_axis(0, $ny->idx19);   # (19,3) registered
        @ex  = $p->slice(':,(0)')->list;
        @ey  = $p->slice(':,(1)')->list;
        @ez  = $p->slice(':,(2)')->list;
        @lab = @{ $ny->electrode_labels_19 };      # Fp1 Fp2 F3 F4 C3 C4 P3 P4 O1 O2 F7 F8 T7 T8 P7 P8 Fz Cz Pz
    }
    my $n = scalar @ex;

    # --snap: pull each electrode to the nearest scalp vertex and lift it 'proud'
    # mm outward (centroid->vertex). Display nicety (NY Head & 10-20 share the MNI
    # frame, so no coordinate alignment is needed) to keep electrodes off/above the
    # surface. Uses the head surface vertices.
    if ($o{snap}) {
        my $hv = $ny->surface('head')->{vc};       # (Nh,3)
        my @V  = map { [ $hv->at($_,0), $hv->at($_,1), $hv->at($_,2) ] } 0 .. $hv->dim(0)-1;
        my ($cx,$cy,$cz) = (0,0,0);
        $cx += $_->[0] for @V; $cy += $_->[1] for @V; $cz += $_->[2] for @V;
        my $nv = scalar @V; $cx/=$nv; $cy/=$nv; $cz/=$nv;
        for my $i (0 .. $n-1) {
            my ($bx,$by,$bz,$bd) = (0,0,0,1e30);
            for my $v (@V) {
                my $d = ($v->[0]-$ex[$i])**2 + ($v->[1]-$ey[$i])**2 + ($v->[2]-$ez[$i])**2;
                ($bx,$by,$bz,$bd) = (@$v,$d) if $d < $bd;
            }
            my ($rx,$ry,$rz) = ($bx-$cx, $by-$cy, $bz-$cz);
            my $rl = sqrt($rx*$rx+$ry*$ry+$rz*$rz) || 1;
            $ex[$i] = $bx + $o{proud}*$rx/$rl;
            $ey[$i] = $by + $o{proud}*$ry/$rl;
            $ez[$i] = $bz + $o{proud}*$rz/$rl;
        }
        printf STDERR "electrodes: snapped to nearest scalp vertex + %.1fmm proud\n", $o{proud};
    }

    $scene->{points} = pdl([ \@ex, \@ey, \@ez ]);                     # (N,3)
    $scene->{colors} = pdl([ [(1.0)x$n], [(0.35)x$n], [(0.2)x$n] ]);  # red-orange dots
    $scene->{labels} = \@lab;
    printf STDERR "electrodes: %d (%s)\n", $n,
        defined $o{elc} ? $o{elc} : ($o{elec_orig} ? 'NY Head 19, locs_3D_orig(template)' : 'NY Head 19, registered (locs_3D)');
}

# ---- forward projection: 231 values -> diverging colour map (blue<0<red) ------
sub topo_colors {
    my ($vals) = @_;                               # (231) piddle
    my @v = $vals->list;
    my $m = 0; for (@v) { my $a = abs $_; $m = $a if $a > $m } $m ||= 1;
    my (@R,@G,@B);
    for my $x (@v) {
        my $t = $x / $m;                           # [-1,1]
        if ($t >= 0) { push @R,1;        push @G,1-$t;  push @B,1-$t; }   # white->red
        else         { my $s=-$t; push @R,1-$s; push @G,1-$s; push @B,1; }   # white->blue
    }
    return pdl([ \@R, \@G, \@B ]);                 # (231,3)
}

# ---- pick / hover: fine-mesh local vertex -> 75K -> atlas name / leadfield -----
my $on_pick = sub {
    my ($idx, $x, $y, $z, $seedno) = @_;           # idx = local vertex on the fine mesh
    my $v75 = defined $in_from_pick ? $in_from_pick->at($idx) : undef;
    if (defined $v75) {
        if ($o{forward}) {
            my $topo = $ny->leadfield->slice(",($v75)");   # (231) this source's scalp topo
            $scene->{colors} = topo_colors($topo);         # live recolour (read each frame)
            printf STDERR "  -> forward: source 75K v%d projected onto %d electrodes\n",
                $v75, $topo->dim(0);
        }
        my $area = area_of($v75);
        printf STDERR "  -> cortex75K v%d, %s  (leadfield col %d)\n", $v75, $area, $v75;
        return $area;                              # seed label
    }
    return undef;                                  # scalp pick: no cortical atlas
};

my $on_hover = sub {
    my ($idx, $x, $y, $z) = @_;
    my $v75 = defined $in_from_pick ? $in_from_pick->at($idx) : undef;
    return defined $v75 ? area_of($v75) : undef;
};

# ---- run ----------------------------------------------------------------------
# recenter: pivot the view on the mesh centroid so the anatomy sits centred and
# rotation orbits the brain centre. Electrodes are co-registered (the leadfield
# is solved from these cortex sources to these scalp electrodes), so they stay on
# the scalp; true MNI coords are preserved in the readout (read from raw verts).
my $pivot;
if ($o{recenter}) {
    my $mc = ($lod ? $lod->{fine}{verts} : $scene->{mesh}{verts})->average;   # cortex centroid (3)
    my $ec = defined $scene->{points} ? $scene->{points}->average : undef;   # electrode centroid
    my $mode = $o{pivot};
    if    ($mode eq 'head')                     { $pivot = [ $ny->surface('head')->{vc}->average->list ] }
    elsif ($mode eq 'electrodes' && defined $ec){ $pivot = [ $ec->list ] }
    elsif ($mode eq 'combined'   && defined $ec){ $pivot = [ (($mc + $ec)/2)->list ] }
    else                                      { $pivot = [ $mc->list ]; $mode = 'mesh' }
    printf STDERR "recenter: pivot=%s (%.1f, %.1f, %.1f)\n", $mode, @$pivot;
}

my $drv = PDL::Graphics::Cairo::Driver::GS3D->new(
    scene    => $scene,
    ($lod ? (lod => $lod) : ()),
    ($pivot ? (pivot => $pivot) : ()),
    thick_fill => $o{thick_fill},
    render     => ($o{zbuffer} ? 'zbuffer' : 'line'),
    width    => $o{width},
    height   => $o{height},
    zoom     => $o{zoom},
    on_pick  => $on_pick,
    on_hover => $on_hover,
);
$drv->run;
