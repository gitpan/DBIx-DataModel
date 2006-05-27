package DBIx::DataModel::View;

use warnings;
use strict;
use Carp;
use base 'DBIx::DataModel::AbstractTable';



# Redefines the method inherited from DBIx::DataModel::AbstractTable,
# calling handlers from every parent class.

sub applyColumnHandler { 
  my ($self, $handlerName, $objects) = @_;

  my $class = ref($self) || $self;
  my $targets = $objects || [$self];
  my %results;			# accumulates result from each parent table

  # recursive call to each parent table
  #   UNSOLVED POTENTIAL CONFLICT : what if several parents 
  #   have handlers for the same columnn ?
  foreach my $table (@{$self->classData->{parentTables}}) {
    my $result = $table->applyColumnHandler($handlerName, $targets);
    my @k = keys %$result;
    @results{@k} = @{$result}{@k};
  }

  return \%results;
};


1; # End of DBIx::DataModel::View

__END__

=head1 NAME

DBIx::DataModel::View - Parent for View classes


=head1 DESCRIPTION

This is the parent class for all view classes created through

  MySchema->View($classname, ...);

=head1 METHODS

Methods are documented in L<DBIx::DataModel|DBIx::DataModel>. This module
implements 

=over

=item L<applyColumnHandler|DBIx::DataModel/applyColumnHandler>

=back


=head1 AUTHOR

Laurent Dami, C<< <laurent.dami AT etat.ge.ch> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Laurent Dami.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
