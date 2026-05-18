package PDL::Graphics::Cairo::Geometry::Polyline;

use Moo;
use PDL;

has x => (is=>'ro');
has y => (is=>'ro');

sub BUILD {
    my ($self)= @_;

    die "x must be PDL"
        unless UNIVERSAL::isa($self->x,'PDL');

    die "y must be PDL"
        unless UNIVERSAL::isa($self->y,'PDL');
}

1;
