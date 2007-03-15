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

  not ref($class) or croak "'AutoExpand' is a class method";

  # check that we only AutoExpand on composition roles
  my $joins = $class->schema->classData->{joins}{$class};
  foreach my $role (@roles) {
    $joins->{$role}{is_composition}
      or croak "cannot AutoExpand on $role: not a composition";
  }

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


sub autoInsertColumns {
  my $self = shift; 
  return $self->schema->autoInsertColumns,
         @{$self->classData->{autoInsertColumns} || []};
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

  # get primKey columns
  my @primKey = @{$self->classData->{primKey}};

  # if called as instance method, get primKey values
  @primKey = @{$self}{@primKey} if ref $self;

  # choose what to return depending on context
  return @primKey if wantarray;
  not(@primKey > 1) 
    or croak "cannot return a multi-column primary key in a scalar context";
  return $primKey[0];
}



sub componentRoles {
  my $self  = shift; 
  my $class = ref($self) || $self;
  my $join_info =  $class->schema->classData->{joins}{$class};
  return grep {$join_info->{$_}{is_composition}} keys %$join_info;
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

  my @ids;

  foreach my $record (@records) {
    bless $record, $class;
    $record->applyColumnHandler('toDB');

    # remove subtrees and noUpdateColumns
    delete $record->{$_} foreach $class->noUpdateColumns;
    my $subrecords = $record->_weed_out_subtrees;

    # do the insertion
    push @ids, $record->_singleInsert();

    # insert the subtrees
    $record->_insert_subtrees($subrecords);
  }

  # choose what to return according to context
  return @ids if wantarray;             # list context
  return      if not defined wantarray; # void context
  carp "insert({...}, {...}, ..) called in scalar context" if @records > 1;
  return $ids[0];
}


sub _singleInsert {
  my ($self) = @_; # assumes %$self only contains scalars, and noUpdateColumns
                   # have already been removed 
  my $class  = ref $self or croak "_singleInsert called as class method";

  $self->_rawInsert;

  # make sure the object has its own key
  my @primKeyCols = $class->primKey;
  unless (@{$self}{@primKeyCols}) {
    my $n_columns = @primKeyCols;
    not ($n_columns > 1) 
      or croak "cannot ask for last_insert_id: primary key in $class "
             . "has $n_columns columns";

   my ($dbh, %dbh_options) = $class->schema->dbh;

   # fill the primary key from last_insert_id returned by the DBMS
    $self->{$primKeyCols[0]}
      = $dbh->last_insert_id($dbh_options{catalog}, 
                             $dbh_options{schema}, 
                             $class->db_table, 
                             $primKeyCols[0]);
  }

  return $self->{$primKeyCols[0]};
}


sub _rawInsert {
  my ($self) = @_; 
  my $class  = ref $self or croak "_rawInsert called as class method";

  # need to clone into a plain hash because that's what SQL::Abstract wants...
  my %clone = %$self;

  for my $method (qw/autoInsertColumns autoUpdateColumns/) {
    my %autoColumns = $self->$method;
    while (my ($col, $handler) = each %autoColumns) {
      $clone{$col} = $handler->(\%clone, $class);
    }
  }

  # perform the insertion
  my ($sql, @bind) = $class->schema->classData->{sqlAbstr}
                           ->insert($class->db_table, \%clone);
  $class->_debug($sql . " / " . join(", ", @bind) );
  my $sth = $class->schema->dbh->prepare($sql);
  $class->schema->classData->{lasth} = $sth if $class->schema->keepLasth;
  $sth->execute(@bind);
}


sub _weed_out_subtrees {
  my ($self) = @_; 
  my $class = ref $self;

  my %is_component;
  $is_component{$_} = 1 foreach $class->componentRoles;
  my $subrecords = {};

  while (my ($k, $v) = each %$self) {
    if (ref $v) {
      $is_component{$k} ? $subrecords->{$k} = $v 
                        : carp "unexpected reference $k in record, deleted";
      delete $self->{$k};
    }
  }
  return $subrecords;
}


sub _insert_subtrees {
  my ($self, $subrecords) = @_;
  my $class = ref $self;
  if (keys %$subrecords) {  # if there are component objects to insert
    while (my ($role, $arrayref) = each %$subrecords) { # insert_into each role
      UNIVERSAL::isa($arrayref, 'ARRAY')
          or croak "Expected an arrayref for component role $role in $class";
      my $meth = "insert_into_$role";
      $self->$meth(@$arrayref);
    }
  }
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


sub _modifyData { # called by methods 'update' and 'delete'.
                  # .. actually the factorization of code is not so 
                  #    great, maybe should find another, better way
  my $toDo        = shift;
  my $self        = shift;
  my $class       = ref($self) || $self;
  my $db_table    = $class->db_table;
  my $dbh         = $class->schema->dbh or croak "Schema has no dbh";
  my @primKeyCols = $class->primKey;

  if (not ref($self)) {		# called as class method
    scalar(@_) or croak "not enough args for '$toDo' called as class method";

    # $self becomes a hashref to a copy of the values passed as last argument
    $self = ref($_[-1]) ? {%{pop @_}} : {};

    # if primary key is given as a first argument, add it into the hashref
    @{$self}{@primKeyCols} = @_ if @_;

    bless $self, $class;
  }
  else { # called as instance method
    croak "too many args for '$toDo' called as instance method" if @_;

    if ($toDo eq 'delete') {
      # cascaded delete
      foreach my $role ($class->componentRoles) {
        my $component_items = $self->{$role} or next;
        $_->delete foreach @$component_items;
      }
    }
  }

  # convert values into database format
  $self->applyColumnHandler('toDB');

  # move values of primary keys into a specific '%where' structure
  my %where;
  foreach my $col (@primKeyCols) {
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

=item L<_singleInsert|DBIx::DataModel/_singleInsert>

=item L<_rawInsert|DBIx::DataModel/_rawInsert>

=item L<update|DBIx::DataModel/update>

=item L<hasInvalidColumns|DBIx::DataModel/hasInvalidColumns>

=back


=head1 AUTHOR

Laurent Dami, C<< <laurent.dami AT etat.ge.ch> >>


=head1 COPYRIGHT & LICENSE

Copyright 2006 Laurent Dami.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.



