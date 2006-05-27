#----------------------------------------------------------------------
package DBIx::DataModel::Iterator;
#----------------------------------------------------------------------


# see POD doc at end of file

use warnings;
use strict;
use Carp;

sub new {
  my ($class, $sth, $iter_class) = @_;
  not ref($class) or croak "DBIx::DataModel::Iterator->new is a class method";

  my $self = {sth => $sth, iter_class => $iter_class};
  return bless $self, $class;
}

sub next {
  my $self = shift;
  my $row = $self->{sth}->fetchrow_hashref or return undef;
  return $self->{iter_class}->blessFromDB($row);
}

1;

__END__

=head1 NAME

DBIx::DataModel::Iterator - Internal class for iterators over data rows

=head1 DESCRIPTION

Implements iterators returned by 
L<DBIx::DataModel::select|DBIx::DataModel/select>.
For internal use only.

=head1 METHODS

=head2 new

  my $iterator = DBIx::DataModel::Iterator->new($sth, $iter_class)};

=head2 next

  while (my $row = $iterator->next) {...}

Returns the next data row, blessed into an object of C<$iter_class>

=head1 AUTHOR

Laurent Dami, E<lt>laurent.dami AT etat  geneve  chE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2006 by Laurent Dami.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 
