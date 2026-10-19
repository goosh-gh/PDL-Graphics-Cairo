use strict;
use warnings;
use Test::More;
use PDL::Graphics::Cairo;
use PDL::Graphics::Cairo::PGPLOT ();

# The names people write (matplotlib-, PGPLOT- and gnuplot-like methods, their
# aliases and the exported functions) stay available when the inside of the
# library is reorganised (P:G:C31: drawing code moved out of Axes.pm into
# Axes/Render/*.pm and Axes/Decor.pm, in the same package).
# The list below is every public name as of 0.42 + c379e6b, before the move:
# subs of Axes and Figure not starting with "_" and defined in that package
# (including Moo accessors), and the EXPORT_OK lists of PDL::Graphics::Cairo
# and PDL::Graphics::Cairo::PGPLOT. Add names here when the API grows.

my (%want, $n);
while (my $line = <DATA>) {
    chomp $line;
    next unless $line =~ /\S/;
    my ($where, $name) = split /\t/, $line;
    push @{ $want{$where} }, $name;
    $n++;
}
cmp_ok($n, '>', 200, "$n names listed");

for my $pkg ('PDL::Graphics::Cairo::Axes', 'PDL::Graphics::Cairo::Figure') {
    my @missing = grep { !$pkg->can($_) } @{ $want{$pkg} };
    is_deeply(\@missing, [], "$pkg: all " . scalar(@{ $want{$pkg} }) . ' methods present')
        or diag "missing: @missing";
}
for ([ 'PGPLOT-export', \@PDL::Graphics::Cairo::PGPLOT::EXPORT_OK, 'PDL::Graphics::Cairo::PGPLOT' ],
     [ 'Cairo-export',  \@PDL::Graphics::Cairo::EXPORT_OK,         'PDL::Graphics::Cairo' ]) {
    my ($key, $list, $pkg) = @$_;
    my %have = map { $_ => 1 } @$list;
    my @missing = grep { !$have{$_} || !$pkg->can($_) } @{ $want{$key} };
    is_deeply(\@missing, [], "$pkg: all " . scalar(@{ $want{$key} }) . ' exported names present')
        or diag "missing: @missing";
}

done_testing;

__DATA__
PDL::Graphics::Cairo::Axes	annotate
PDL::Graphics::Cairo::Axes	axes_to_pixel
PDL::Graphics::Cairo::Axes	axhline
PDL::Graphics::Cairo::Axes	axhspan
PDL::Graphics::Cairo::Axes	axis
PDL::Graphics::Cairo::Axes	axvline
PDL::Graphics::Cairo::Axes	axvspan
PDL::Graphics::Cairo::Axes	bar
PDL::Graphics::Cairo::Axes	barh
PDL::Graphics::Cairo::Axes	boxplot
PDL::Graphics::Cairo::Axes	cla
PDL::Graphics::Cairo::Axes	clear
PDL::Graphics::Cairo::Axes	clip_pad_top
PDL::Graphics::Cairo::Axes	colorbar
PDL::Graphics::Cairo::Axes	colorbar_label
PDL::Graphics::Cairo::Axes	colorbar_length
PDL::Graphics::Cairo::Axes	colorbar_location
PDL::Graphics::Cairo::Axes	colorbar_pad
PDL::Graphics::Cairo::Axes	colorbar_reserve
PDL::Graphics::Cairo::Axes	colorbar_tick_step
PDL::Graphics::Cairo::Axes	colorbar_width
PDL::Graphics::Cairo::Axes	contour
PDL::Graphics::Cairo::Axes	contourf
PDL::Graphics::Cairo::Axes	data_to_image_frac
PDL::Graphics::Cairo::Axes	data_to_pixel
PDL::Graphics::Cairo::Axes	draw
PDL::Graphics::Cairo::Axes	errorbar
PDL::Graphics::Cairo::Axes	errorbar_stats
PDL::Graphics::Cairo::Axes	eventplot
PDL::Graphics::Cairo::Axes	fig_x
PDL::Graphics::Cairo::Axes	fig_y
PDL::Graphics::Cairo::Axes	fill
PDL::Graphics::Cairo::Axes	fill_between
PDL::Graphics::Cairo::Axes	get_xlim
PDL::Graphics::Cairo::Axes	get_ylim
PDL::Graphics::Cairo::Axes	grid
PDL::Graphics::Cairo::Axes	grid_color
PDL::Graphics::Cairo::Axes	heatmap
PDL::Graphics::Cairo::Axes	height
PDL::Graphics::Cairo::Axes	hexbin
PDL::Graphics::Cairo::Axes	hist
PDL::Graphics::Cairo::Axes	hist_kde
PDL::Graphics::Cairo::Axes	histogram
PDL::Graphics::Cairo::Axes	hlines
PDL::Graphics::Cairo::Axes	image_frac_to_data
PDL::Graphics::Cairo::Axes	imshow
PDL::Graphics::Cairo::Axes	inset_axes
PDL::Graphics::Cairo::Axes	invert_xaxis
PDL::Graphics::Cairo::Axes	invert_yaxis
PDL::Graphics::Cairo::Axes	legend
PDL::Graphics::Cairo::Axes	line
PDL::Graphics::Cairo::Axes	loglog
PDL::Graphics::Cairo::Axes	margin_bottom
PDL::Graphics::Cairo::Axes	margin_left
PDL::Graphics::Cairo::Axes	margin_right
PDL::Graphics::Cairo::Axes	margin_top
PDL::Graphics::Cairo::Axes	margins
PDL::Graphics::Cairo::Axes	minorticks_off
PDL::Graphics::Cairo::Axes	minorticks_on
PDL::Graphics::Cairo::Axes	new
PDL::Graphics::Cairo::Axes	pcolor
PDL::Graphics::Cairo::Axes	pcolormesh
PDL::Graphics::Cairo::Axes	pie
PDL::Graphics::Cairo::Axes	plot
PDL::Graphics::Cairo::Axes	plot_date
PDL::Graphics::Cairo::Axes	polyline
PDL::Graphics::Cairo::Axes	qqplot
PDL::Graphics::Cairo::Axes	quiver
PDL::Graphics::Cairo::Axes	scatter
PDL::Graphics::Cairo::Axes	semilogx
PDL::Graphics::Cairo::Axes	semilogy
PDL::Graphics::Cairo::Axes	set_aspect
PDL::Graphics::Cairo::Axes	set_facecolor
PDL::Graphics::Cairo::Axes	set_grid
PDL::Graphics::Cairo::Axes	set_limits
PDL::Graphics::Cairo::Axes	set_major_formatter
PDL::Graphics::Cairo::Axes	set_minor_locator
PDL::Graphics::Cairo::Axes	set_position
PDL::Graphics::Cairo::Axes	set_right_ylabel
PDL::Graphics::Cairo::Axes	set_tight_layout
PDL::Graphics::Cairo::Axes	set_title
PDL::Graphics::Cairo::Axes	set_xlabel
PDL::Graphics::Cairo::Axes	set_xlim
PDL::Graphics::Cairo::Axes	set_xscale
PDL::Graphics::Cairo::Axes	set_xticklabels
PDL::Graphics::Cairo::Axes	set_xticks
PDL::Graphics::Cairo::Axes	set_ylabel
PDL::Graphics::Cairo::Axes	set_ylim
PDL::Graphics::Cairo::Axes	set_yscale
PDL::Graphics::Cairo::Axes	set_yticklabels
PDL::Graphics::Cairo::Axes	set_yticks
PDL::Graphics::Cairo::Axes	specgram
PDL::Graphics::Cairo::Axes	stackplot
PDL::Graphics::Cairo::Axes	stem
PDL::Graphics::Cairo::Axes	step
PDL::Graphics::Cairo::Axes	text
PDL::Graphics::Cairo::Axes	tick_params
PDL::Graphics::Cairo::Axes	title
PDL::Graphics::Cairo::Axes	twinx
PDL::Graphics::Cairo::Axes	twiny
PDL::Graphics::Cairo::Axes	violin
PDL::Graphics::Cairo::Axes	violinplot
PDL::Graphics::Cairo::Axes	vlines
PDL::Graphics::Cairo::Axes	width
PDL::Graphics::Cairo::Axes	xaxis_formatter
PDL::Graphics::Cairo::Axes	xlabel
PDL::Graphics::Cairo::Axes	xlim
PDL::Graphics::Cairo::Axes	xmax
PDL::Graphics::Cairo::Axes	xmin
PDL::Graphics::Cairo::Axes	xscale
PDL::Graphics::Cairo::Axes	xticks
PDL::Graphics::Cairo::Axes	yaxis_formatter
PDL::Graphics::Cairo::Axes	ylabel
PDL::Graphics::Cairo::Axes	ylabel_rotation
PDL::Graphics::Cairo::Axes	ylim
PDL::Graphics::Cairo::Axes	ymax
PDL::Graphics::Cairo::Axes	ymin
PDL::Graphics::Cairo::Axes	yscale
PDL::Graphics::Cairo::Axes	yticks
PDL::Graphics::Cairo::Figure	add_axes
PDL::Graphics::Cairo::Figure	add_connection
PDL::Graphics::Cairo::Figure	add_gridspec
PDL::Graphics::Cairo::Figure	add_subplot
PDL::Graphics::Cairo::Figure	add_text
PDL::Graphics::Cairo::Figure	ax
PDL::Graphics::Cairo::Figure	axes
PDL::Graphics::Cairo::Figure	axes_list
PDL::Graphics::Cairo::Figure	button
PDL::Graphics::Cairo::Figure	clf
PDL::Graphics::Cairo::Figure	dpi
PDL::Graphics::Cairo::Figure	height
PDL::Graphics::Cairo::Figure	label_only
PDL::Graphics::Cairo::Figure	label_outer
PDL::Graphics::Cairo::Figure	new
PDL::Graphics::Cairo::Figure	on_change
PDL::Graphics::Cairo::Figure	param
PDL::Graphics::Cairo::Figure	save
PDL::Graphics::Cairo::Figure	savefig
PDL::Graphics::Cairo::Figure	set_facecolor
PDL::Graphics::Cairo::Figure	set_suptitle
PDL::Graphics::Cairo::Figure	show
PDL::Graphics::Cairo::Figure	subplot
PDL::Graphics::Cairo::Figure	subplot_mosaic
PDL::Graphics::Cairo::Figure	subplots
PDL::Graphics::Cairo::Figure	subplots_adjust
PDL::Graphics::Cairo::Figure	suptitle
PDL::Graphics::Cairo::Figure	tight_layout
PDL::Graphics::Cairo::Figure	to_inline
PDL::Graphics::Cairo::Figure	to_png
PDL::Graphics::Cairo::Figure	to_svg
PDL::Graphics::Cairo::Figure	width
PGPLOT-export	cpgbox
PGPLOT-export	pgarro
PGPLOT-export	pgask
PGPLOT-export	pgaxis
PGPLOT-export	pgband
PGPLOT-export	pgbbuf
PGPLOT-export	pgbeg
PGPLOT-export	pgbegin
PGPLOT-export	pgbin
PGPLOT-export	pgbox
PGPLOT-export	pgcirc
PGPLOT-export	pgclos
PGPLOT-export	pgclose
PGPLOT-export	pgconb
PGPLOT-export	pgconf
PGPLOT-export	pgcons
PGPLOT-export	pgcont
PGPLOT-export	pgctab
PGPLOT-export	pgcurs
PGPLOT-export	pgdraw
PGPLOT-export	pgebuf
PGPLOT-export	pgend
PGPLOT-export	pgenv
PGPLOT-export	pgeras
PGPLOT-export	pgerr1
PGPLOT-export	pgerrb
PGPLOT-export	pgerrx
PGPLOT-export	pgerry
PGPLOT-export	pggray
PGPLOT-export	pghist
PGPLOT-export	pgiden
PGPLOT-export	pgimag
PGPLOT-export	pglab
PGPLOT-export	pglabel
PGPLOT-export	pglcur
PGPLOT-export	pgline
PGPLOT-export	pgmove
PGPLOT-export	pgmtxt
PGPLOT-export	pgncur
PGPLOT-export	pgnumb
PGPLOT-export	pgopen
PGPLOT-export	pgpage
PGPLOT-export	pgpap
PGPLOT-export	pgpoint
PGPLOT-export	pgpoints
PGPLOT-export	pgpoly
PGPLOT-export	pgpt
PGPLOT-export	pgpt1
PGPLOT-export	pgptxt
PGPLOT-export	pgqah
PGPLOT-export	pgqcf
PGPLOT-export	pgqch
PGPLOT-export	pgqci
PGPLOT-export	pgqcr
PGPLOT-export	pgqcs
PGPLOT-export	pgqfs
PGPLOT-export	pgqhs
PGPLOT-export	pgqinf
PGPLOT-export	pgqls
PGPLOT-export	pgqlw
PGPLOT-export	pgqvp
PGPLOT-export	pgqvsz
PGPLOT-export	pgqwin
PGPLOT-export	pgrect
PGPLOT-export	pgrnd
PGPLOT-export	pgrnge
PGPLOT-export	pgsah
PGPLOT-export	pgsave
PGPLOT-export	pgscf
PGPLOT-export	pgsch
PGPLOT-export	pgsci
PGPLOT-export	pgscr
PGPLOT-export	pgscrl
PGPLOT-export	pgsfs
PGPLOT-export	pgshls
PGPLOT-export	pgsitf
PGPLOT-export	pgsls
PGPLOT-export	pgslw
PGPLOT-export	pgsubp
PGPLOT-export	pgsvp
PGPLOT-export	pgsvp
PGPLOT-export	pgswin
PGPLOT-export	pgtext
PGPLOT-export	pgtick
PGPLOT-export	pgunsa
PGPLOT-export	pgupdt
PGPLOT-export	pgvect
PGPLOT-export	pgvp
PGPLOT-export	pgvsiz
PGPLOT-export	pgvstd
PGPLOT-export	pgwedg
PGPLOT-export	pgwnad
Cairo-export	BoundaryNorm
Cairo-export	ListedColormap
Cairo-export	LogNorm
Cairo-export	Normalize
Cairo-export	TwoSlopeNorm
Cairo-export	figure
Cairo-export	imread
Cairo-export	rcParams
Cairo-export	style
Cairo-export	subplot_mosaic
Cairo-export	subplots
