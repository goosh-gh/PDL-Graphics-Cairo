package PDL::Graphics::Cairo::Transform::Log;

# =============================================================
# Linear  Log 
# =============================================================

use Moo;
use PDL;
use POSIX qw(log10);

has xmin   => (is => 'ro', required => 1);
has xmax   => (is => 'ro', required => 1);
has ymin   => (is => 'ro', required => 1);
has ymax   => (is => 'ro', required => 1);
has left   => (is => 'ro', required => 1);
has right  => (is => 'ro', required => 1);
has top    => (is => 'ro', required => 1);
has bottom => (is => 'ro', required => 1);
has xscale => (is => 'ro', default => sub { 'linear' });  # 'log' or 'linear'
has yscale => (is => 'ro', default => sub { 'linear' });

sub BUILD {
    my ($self) = @_;
    # log
    $self->{lx_min} = $self->xscale eq 'log'
        ? log($self->xmin > 0 ? $self->xmin : 1e-10)
        : $self->xmin;
    $self->{lx_max} = $self->xscale eq 'log'
        ? log($self->xmax > 0 ? $self->xmax : 1e-10)
        : $self->xmax;
    $self->{ly_min} = $self->yscale eq 'log'
        ? log($self->ymin > 0 ? $self->ymin : 1e-10)
        : $self->ymin;
    $self->{ly_max} = $self->yscale eq 'log'
        ? log($self->ymax > 0 ? $self->ymax : 1e-10)
        : $self->ymax;

    my $dx = $self->{lx_max} - $self->{lx_min} || 1;
    my $dy = $self->{ly_max} - $self->{ly_min} || 1;
    $self->{sx} = ($self->right  - $self->left)   / $dx;
    $self->{sy} = ($self->bottom - $self->top)     / $dy;
}

sub x {
    my ($self, $xd) = @_;
    my $lx = $self->xscale eq 'log'
        ? log(($xd > 0) * $xd + ($xd <= 0) * 1e-10)
        : $xd;
    return $self->left + ($lx - $self->{lx_min}) * $self->{sx};
}

sub y {
    my ($self, $yd) = @_;
    my $ly = $self->yscale eq 'log'
        ? log(($yd > 0) * $yd + ($yd <= 0) * 1e-10)
        : $yd;
    return $self->bottom - ($ly - $self->{ly_min}) * $self->{sy};
}

sub inv_x {
    my ($self, $xp) = @_;
    my $lx = ($xp - $self->left) / $self->{sx} + $self->{lx_min};
    return $self->xscale eq 'log' ? exp($lx) : $lx;
}

sub inv_y {
    my ($self, $yp) = @_;
    my $ly = ($self->bottom - $yp) / $self->{sy} + $self->{ly_min};
    return $self->yscale eq 'log' ? exp($ly) : $ly;
}

1;
