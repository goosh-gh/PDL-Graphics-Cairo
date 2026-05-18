package PDL::Graphics::Cairo::Transform::Linear;

use Moo;
use PDL;

has xmin   => (is => 'ro', required => 1);
has xmax   => (is => 'ro', required => 1);
has ymin   => (is => 'ro', required => 1);
has ymax   => (is => 'ro', required => 1);
has left   => (is => 'ro', required => 1);
has right  => (is => 'ro', required => 1);
has top    => (is => 'ro', required => 1);
has bottom => (is => 'ro', required => 1);

sub BUILD {
    my ($self) = @_;
    $self->{sx} = ($self->right  - $self->left)   / ($self->xmax - $self->xmin);
    $self->{sy} = ($self->bottom - $self->top)    / ($self->ymax - $self->ymin);
}

# data → screenPDL piddle 
sub x { $_[0]->left   + ($_[1] - $_[0]->xmin) * $_[0]->{sx} }
sub y { $_[0]->bottom - ($_[1] - $_[0]->ymin) * $_[0]->{sy} }

# screen → data
sub inv_x { ($_[1] - $_[0]->left)   / $_[0]->{sx} + $_[0]->xmin }
sub inv_y { ($_[0]->bottom - $_[1]) / $_[0]->{sy} + $_[0]->ymin }

1;
