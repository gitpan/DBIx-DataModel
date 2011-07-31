package DBIx::DataModel::Meta::Source::Table;
use strict;
use warnings;
use parent "DBIx::DataModel::Meta::Source";
use DBIx::DataModel::Meta::Utils;

use Carp;
use Params::Validate qw/HASHREF ARRAYREF SCALAR/;
use List::MoreUtils  qw/any/;
use namespace::autoclean;

{no strict 'refs'; *CARP_NOT = \@DBIx::DataModel::CARP_NOT;}

sub new {
  my $class = shift;

  # the real work occurs in parent class
  my $self = $class->_new_meta_source(

    # more spec for Params::Validate
    { column_types        => {type => HASHREF, default => {}},
      column_handlers     => {type => HASHREF, default => {}},
      db_name             => {type => SCALAR},
      where               => {type => HASHREF|ARRAYREF, optional => 1},

      auto_insert_columns => {type => HASHREF, default => {}},
      auto_update_columns => {type => HASHREF, default => {}},
      no_update_columns   => {type => HASHREF, default => {}},

    },

    # method to call in schema for building @ISA
    'table_parent',

    # original args
    @_
   );

  my $types = delete $self->{column_types};
  while (my ($type_name, $columns_aref) = each %$types) {
    $self->define_column_type($type_name, @$columns_aref);
  }

  return $self;
}


sub db_from {
  my $self = shift;
  return $self->{db_name};
}


sub where {
  my $self  = shift;

  return $self->{where};
}

sub components {
  my $self  = shift; 

  return @{$self->{components} || []};
}



sub define_column_type {
  my ($self, $type_name, @columns) = @_;

  my $type = $self->{schema}->type($type_name) 
    or croak "unknown column type : $type_name";

  foreach my $column (@columns) {
    $self->define_column_handlers($column, %{$type->{handlers}})
  }

  return $self;
}


sub define_column_handlers {
  my ($self, $column_name, %handlers) = @_;

  while (my ($handler_name, $body) = each %handlers) {
    $self->{column_handlers}{$column_name}{$handler_name} = $body;
  }

  return $self;
}


sub define_auto_expand {
  my ($self, @component_names) = @_;

  # check that we only auto_expand on components
  my @components = $self->components;
  foreach my $component_name (@component_names) {
    any {$component_name eq $_} @components
      or croak "cannot auto_expand on $component_name: not a composition";
  }

  # closure to iterate on the components
  my $body = sub {
    my ($self, $recurse) = @_;
    foreach my $component_name (@component_names) {
      my $r = $self->expand($component_name); # result can be an object ref 
                                              # or an array ref
      if ($r and $recurse) {
	$r = [$r] unless ref($r) eq 'ARRAY';
	$_->auto_expand($recurse) foreach @$r;
      }
    }
  };

  # install the method
  DBIx::DataModel::Meta::Utils->define_method(
    class          => $self->{class},
    name           => 'auto_expand',
    body           => $body,
    check_override => 0,
   );

  return $self;
}


1;

