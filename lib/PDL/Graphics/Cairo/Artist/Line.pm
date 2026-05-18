package PDL::Graphics::Cairo::Artist::Line;

use Moo;

has geometry => (is=>'ro');

has color => (is=>'ro', default => sub {[0,0,0]});
has linewidth => (is=>'ro', default => sub {1});

sub draw {
    my ($self,$backend,$tr)= @_;

    my $x = $self->geometry->x;
    my $y = $self->geometry->y;

    my $xd = $tr->x($x);
    my $yd = $tr->y($y);

    $backend->polyline($xd,$yd);
}

1;
