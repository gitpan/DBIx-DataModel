package DBIx::DataModel::Table;

use warnings;
no warnings 'uninitialized';
use strict;
use Carp;
use base 'DBIx::DataModel::AbstractTable';


sub DefaultColumns {
  my ($class, $columns) = @_;
  $class->classData->{columns} = $columns;
}




sub ColumnType {
  my ($class, $typeName, @args) = @_;

  not ref($class) or croak "'ColumnType' is a class method";

  my $handlers = $class->schema->classData->{columnHandlers}{$typeName} or 
    croak "unknown ColumnType : $typeName";

  foreach my $column (@args) {
    $class->ColumnHandlers($column, %$handlers)
  }
}


sub ColumnHandlers {
  my ($class, $columnName, %handlers) = @_;

  not ref($class) or croak "'ColumnHandlers' is a class method";

  while (my ($handlerName, $coderef) = each %handlers) {
    $class->classData->{columnHandlers}{$columnName}{$handlerName} = $coderef;
  }
}



sub AutoExpand {
  my ($class, @roles) = @_;

  not ref($class) or croak "'ColumnHandlers' is a class method";

  # closure to iterate on the roles
  my $autoExpand = sub {
    my ($self, $recurse) = @_;
    foreach my $role (@roles) {
      my $r = $self->expand($role); # can be an object ref or an array ref
      if ($r and $recurse) {
	$r = [$r] unless ref($r) eq 'ARRAY';
	$_->autoExpand($recurse) foreach @$r;
      }
    }
  };

  $class->schema->_defineMethod($class => autoExpand => $autoExpand);
}


sub autoUpdateColumns {
  my $self = shift; 
  return $self->schema->autoUpdateColumns,
         @{$self->classData->{autoUpdateColumns} || []};
}


sub noUpdateColumns {
  my $self = shift; 
  return $self->schema->noUpdateColumns, 
         @{$self->classData->{noUpdateColumns} || []};
}



sub primKey {
  my $self = shift; 
  @{$self->classData->{primKey}};
}




sub fetch {
  my $class = shift;
  not ref($class) or croak "fetch should be called as class method";
  my %select_args;

  if (UNIVERSAL::isa($_[-1], 'HASH')) {
    %select_args = %{pop @_};
  }
  
  my %where;
  @where{$class->primKey} = @_;
  $select_args{-where} = \%where;
  my $rows = $class->select(%select_args) or return;
  carp "${class}->fetch(): too many results" if @$rows > 1;
  return $rows->[0]; # could be undef
}


sub insert {
  my ($class, @records) = @_;
  not ref($class) or croak "insert() should be called as class method";
  @records        or croak "missing arguments to insert()";

  my $dbh      = $class->schema->dbh or croak "Schema has no dbh";
  my $sqlA     = $class->schema->classData->{sqlAbstr};
  my $db_table = $class->db_table;
  my @prim_keys;

  foreach my $record (@records) {
    bless $record, $class;
    $record->applyColumnHandler('toDB');

    delete $record->{$_} foreach $class->noUpdateColumns;

    # references to foreign objects should not be passed either (see 'expand')
    foreach (keys %$record) {
      delete $record->{$_} if ref($record->{$_});
    }

    # now unbless $record into just a hashref and perform the insert

    bless $record, 'HASH';
    my ($sql, @bind) = $sqlA->insert($db_table, $record);
    $class->_debug($sql . " / " . join(", ", @bind) );
    my $sth = $dbh->prepare($sql);
    $class->schema->classData->{lasth} = $sth if $class->schema->keepLasth;
    $sth->execute(@bind);

    # TODO : pass proper parameters to last_insert_id(). Code below
    # works for MySQL, but not for Postgres.
    push @prim_keys, $dbh->last_insert_id(undef, undef, undef, undef);
  }

  return @prim_keys;
}



sub update { _modifyData('update', @_); }

sub delete { _modifyData('delete', @_); }

sub hasInvalidColumns {
  my ($self) = @_;
  my $results = $self->applyColumnHandler('validate');
  my @invalid;			# names of invalid columns
  while (my ($k, $v) = each %$results) {
    push @invalid, $k if defined($v) and not $v;
  }
  return @invalid ? \@invalid : undef;
}





#------------------------------------------------------------
# Internal utility functions
#------------------------------------------------------------




sub _modifyData { # called by methods 'update' and 'delete'
  my $toDo     = shift;
  my $self     = shift;
  my $class    = ref($self) || $self;
  my $db_table = $class->db_table;
  my $dbh      = $class->schema->dbh or croak "Schema has no dbh";
  my @primKey  = $self->primKey;

  if (not ref($self)) {		# called as class method
    scalar(@_) or croak "not enough args for '$toDo' called as class method";

    # $self becomes a hashref to a copy of the values passed as last argument
    $self = ref($_[-1]) ? {%{pop @_}} : {};

    # if primary key is given as a first argument, add it into the hashref
    @{$self}{@primKey} = @_ if @_;

    bless $self, $class;
  }
  elsif (@_) {
    croak "too many args for '$toDo' called as instance method";
  }

  # convert values into database format
  $self->applyColumnHandler('toDB');

  # move values of primary keys into a specific '%where' structure
  my %where;
  foreach my $col ($self->primKey) {
    $where{$col} = delete $self->{$col} or 
      croak "no value for primary column $col in table $class";
  }

  if ($toDo eq 'update') {
    delete $self->{$_} foreach $self->noUpdateColumns;

    # references to foreign objects should not be passed either (see 'expand')
    foreach (keys %$self) {
      delete $self->{$_} if ref($self->{$_});
    }

    my %autoUpdate = $self->autoUpdateColumns;
    while (my ($col, $handler) = each %autoUpdate) {
      $self->{$col} = $handler->($self, $class);
    }
  }

  # unbless $self into just a hashref and perform the update
  my $schemaClassData = $self->schema->classData;
  my $sqlA            = $schemaClassData->{sqlAbstr};
  my $keepLasth       = $self->schema->keepLasth;
  bless $self, 'HASH';
  my ($sql, @bind) = ($toDo eq 'update') ? 
                        $sqlA->update($db_table, $self, \%where) :
			$sqlA->delete($db_table, \%where);
  $class->_debug($sql . " / " . join(", ", @bind) );
  my $sth = $dbh->prepare($sql);
  $schemaClassData->{lasth} = $sth if $keepLasth;
  $sth->execute(@bind);
}



1; # End of DBIx::DataModel::Table

__END__




=head1 NAME

DBIx::DataModel::Table - Parent for Table classes

=head1 DESCRIPTION

This is the parent class for all table classes created through

  MySchema->Table($classname, ...);

=head1 METHODS

Methods are documented in L<DBIx::DataModel|DBIx::DataModel>. This module
implements 

=over

=item L<DefaultColumns|DBIx::DataModel/DefaultColumns>

=item L<ColumnType|DBIx::DataModel/ColumnType>

=item L<ColumnHandlers|DBIx::DataModel/ColumnHandlers>

=item L<AutoExpand|DBIx::DataModel/AutoExpand>

=item L<autoUpdateColumns|DBIx::DataModel/autoUpdateColumns>

=item L<noUpdateColumns|DBIx::DataModel/noUpdateColumns>

=item L<primKey|DBIx::DataModel/primKey>

=item L<fetch|DBIx::DataModel/fetch>

=item L<insert|DBIx::DataModel/insert>

=item L<update|DBIx::DataModel/update>

=item L<hasInvalidColumns|DBIx::DataModel/hasInvalidColumns>

=back


=head1 AUTHOR

Laurent Dami, C<< <laurent.dami AT etat.ge.ch> >>


=head1 COPYRIGHT & LICENSE

Copyright 2006 Laurent Dami.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.



