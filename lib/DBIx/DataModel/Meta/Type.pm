package DBIx::DataModel::Meta::Type;
use strict;
use warnings;
use parent "DBIx::DataModel::Meta";

use Scalar::Util         qw/weaken/;
use Params::Validate     qw/validate OBJECT SCALAR HASHREF/;
use POSIX                qw//;
use Carp;
use namespace::autoclean;

{no strict 'refs'; *CARP_NOT = \@DBIx::DataModel::CARP_NOT;}

sub new {
  my $class = shift;

  # parse arguments and create $self
  my $self = validate(@_, {
    schema   => {type => OBJECT, isa  => "DBIx::DataModel::Meta::Schema"},
    name     => {type => SCALAR},
    handlers => {type => HASHREF},
  });

  while (my ($name, $body) = each %{$self->{handlers}}) {
    ref $body eq 'CODE' 
      or croak "handler body for $name is not a code reference";
  }

  # avoid circular references
  weaken $self->{schema};

  bless $self, $class;
}


# accessor methods
DBIx::DataModel::Meta::Utils->define_readonly_accessors(
  __PACKAGE__, qw/schema name handlers/
);



1;

__END__

=head1 NAME

DBIx::DataModel::Meta::Type - registered collection of column handlers

=head1 SYNOPSIS

  my $type = DBIx::DataModel::Meta::Type->new(
    schema   => $meta_schema,
    name     => $type_name,
    handlers => {
      $handler_name_1 => sub { ... },
      $handler_name_2 => sub { ... },
      ...
    },
  );

=head1 DESCRIPTION

A I<type> is just a hashref of handler names and
handler bodies (coderefs). The type can then be applied to some
columns in some tables; this is usually done in the Table declaration
(C<column_types> argument), or can be applied later through the
L<DBIx::DataModel::Doc::Reference/define_column_type> method.








