#----------------------------------------------------------------------
package DBIx::DataModel::AbstractTable;
#----------------------------------------------------------------------

# see POD doc at end of file

use warnings;
no warnings 'uninitialized';
use strict;
use Carp;
use base 'DBIx::DataModel::Base';
use DBIx::DataModel::Iterator;

our @CARP_NOT = qw/DBIx::DataModel         DBIx::DataModel::Schema
		   DBIx::DataModel::Table  DBIx::DataModel::View  
                   DBIx::DataModel::Iterator/;


#----------------------------------------------------------------------
# COMPILE-TIME PUBLIC METHODS
#----------------------------------------------------------------------


sub MethodFromRoles {
  my ($class, $meth_name, @roles) = @_;

  my $meth = sub {
    my ($self, @args) = @_;
    return $self->selectFromRoles(@roles)->(@args);
  };

  $class->schema->_defineMethod($class, $meth_name, $meth);
}

#----------------------------------------------------------------------
# RUNTIME PUBLIC METHODS
#----------------------------------------------------------------------

sub schema {
  my $self = shift;
  return $self->classData->{schema}; 
}


sub table {
  my $self = shift; 
  carp "the table() method is deprecated; call db_table() instead";
  return $self->db_table;
}

sub db_table {
  my $self = shift; 
  return $self->classData->{db_table};
}


sub selectImplicitlyFor {
  my $self = shift;

  if (@_) {
    not ref($self) 
      or croak "selectImplicitlyFor(value) should be called as class method";
    $self->classData->{selectImplicitlyFor} = shift;
  }
  return exists($self->classData->{selectImplicitlyFor}) ? 
    $self->classData->{selectImplicitlyFor} :  
    $self->schema->selectImplicitlyFor;
}



sub blessFromDB {
  my ($class, $record) = @_;
  not ref($class) or croak "blessFromDB should be called as class method";
  bless $record, $class;
  $record->applyColumnHandler('fromDB');
  return $record;
}


sub selectSth {
  carp "selectSth is deprecated; use select(..., -resultAs => 'sth')";
  my $self = shift;
  return $self->select(@_, -resultAs => 'sth');
}


sub _isValidSelectArg {
  return grep {$_[0] eq $_} qw/-distinct -columns -where -orderBy 
			       -groupBy  -having -for
			       -resultAs -postSQL -preExec -postExec/;
}


sub select {
  my $self      = shift;
  my $class     = ref $self || $self;
  my $classData = $class->classData;
  my $sqlA      = $self->schema->classData->{sqlAbstr};

  # parse and check arguments
  my $args = &_parseSelectArgs;	# implicitly passing @_
  my ($invalid_arg) = grep {not _isValidSelectArg($_)} keys %$args;
  croak "invalid arg to select(): $invalid_arg" if $invalid_arg;

  # complete arguments
  _addSelectCriteria($args, $classData->{where}) if $classData->{where};
  if ($args->{-distinct}) {
    not exists($args->{-columns}) or 
      croak "cannot specify both -distinct and -columns in select";
    my @clone = ref($args->{-distinct}) ? @{$args->{-distinct}} :
                                          ($args->{-distinct});
    $clone[0] =~ s/^/DISTINCT /;
    $args->{-columns} = \@clone;
  }
  else {
    $args->{-columns} ||= $classData->{columns}; # (default, usually '*')    
  }

  my $groupBy = ref($args->{-groupBy}) ? join(", ", @{$args->{-groupBy}})
                                       : $args->{-groupBy};

  my ($having, @bind_having) = $sqlA->where($args->{-having});
  $having =~ s[WHERE][HAVING];

  exists($args->{-for}) or $args->{-for} = $self->selectImplicitlyFor;


  # translate +/- prefixes to -orderBy args into SQL ASC/DESC
  my $orderBy = $args->{-orderBy};
  $orderBy = [$orderBy] unless ref $orderBy;
  my %direction = ('+' => 'ASC', '-' => 'DESC');
  $orderBy = [map {s/^([-+])(.*)/$2 $direction{$1}/} @$orderBy];

  # generate SQL
  my ($sql, @bind) = $sqlA->select($self->db_table, 
				   $args->{-columns}, 
				   $args->{-where}, 
				   $args->{-orderBy});
  if ($groupBy) {
    $sql =~ s[ORDER BY|$][ GROUP BY $groupBy $&]i;
  }
  if ($having) {
    $sql =~ s[ORDER BY|$][ $having $&]i;
    push @bind, @bind_having;
  }
  if ($args->{-for}) {
    $sql .= " FOR $args->{-for}";
  }

  $class->_debug($sql . " / " . join(", ", @bind));

  ($sql, @bind) = $args->{-postSQL}->($sql, @bind) if $args->{-postSQL};

 SWITCH:
  for ($args->{-resultAs} || "rows") {

    /sql/i           and do { return wantarray ? ($sql, @bind) : $sql; };

    # for all other cases, prepare and execute DBI statement 
    my $dbh = $self->schema->dbh or croak "Schema has no dbh";
    my $sth = $dbh->prepare($sql);
    $self->schema->classData->{lasth} = $sth  if $self->schema->keepLasth;
    $args->{-preExec}->($sth)                 if $args->{-preExec};
    $sth->execute(@bind); 
    $args->{-postExec}->($sth)                if $args->{-postExec};

    /sth|statement/i and do {return $sth; };

    /iterator/i      and do {return 
			       DBIx::DataModel::Iterator->new($sth, $class)};

    /rows/i          and do {# fetch data records and bless them into objects
                             my $records = $sth->fetchall_arrayref({});
                             $class->blessFromDB($_) foreach @$records;
			     return $records; };

    # otherwise
    croak "unknown -resultAs value: $_"; 
  }
}


sub preselectWhere {
  my ($class, $where, $multiplicity) = @_;

  return sub {

    my $selectArgs = &_parseSelectArgs; # implicitly passing @_ (from the internal sub, 
                                        # not from preselectWhere!!)
    _addSelectCriteria($selectArgs, $where);
    my $result = $class->select(%$selectArgs);
    if ($multiplicity and $multiplicity =~ /^([01]\.\.)?1$/) { # if maximum multiplicity 1 
      @$result <= 1 or 
	carp "too many results for multiplicity $multiplicity in class $class";
      return $result->[0];	   # return a single object
    }
    else {                         # if maximum multiplicity n
      return $result;              # return an array ref 
    }
  }
}




sub applyColumnHandlers {
  my $self = shift;
  carp "applyColumnHandlers is deprecated; please call 'applyColumnHandler'";
  $self->applyColumnHandler(@_);
}



sub applyColumnHandler {
  my ($self, $handlerName, $objects) = @_;

  my $targets = $objects || [$self];
  my $columnHandlers = $self->classData->{columnHandlers} || {};
  my $results = {};

  while (my ($columnName, $handlers) = each %$columnHandlers) {
    my $handler = $handlers->{$handlerName} or next;
    foreach my $obj (@$targets) {
      my $result = exists $obj->{$columnName} ? 
            $handler->($obj->{$columnName}, $obj, $columnName, $handlerName) :
            undef;
      if ($objects) { push(@{$results->{$columnName}}, $result); }
      else          { $results->{$columnName} = $result;         }
    }
  }
  return $results;
}


sub expand {
  my ($self, $role, @args) = @_;
  $self->{$role} = $self->$role(@args);
}

sub autoExpand {}


sub selectFromRoles {
  my ($self, $firstRole, @otherRoles) = @_;
  my $class = ref($self) or 
    croak "selectFromRoles called as class method ($self)";

  @otherRoles or croak "selectFromRoles : not enough arguments";

  my $schema = $self->schema;
  my $joins = $schema->classData->{joins};
  my $tableClasses = $class->isa('DBIx::DataModel::View') ?
                         $class->classData->{parentTables} : 
			 [$class];

  my ($joinData) = grep {$_} map {$joins->{$_}{$firstRole}} @$tableClasses or 
    croak "could not find role $firstRole in $class";
  my $firstTable = $joinData->{table};


  my $view = $schema->ViewFromRoles($firstTable, @otherRoles);

  my %criteria;
  while (my ($leftCol, $rightCol) = each %{$joinData->{where}}) {
    exists($self->{$leftCol}) or 
      croak "cannot follow role $firstRole if foreign key $leftCol is absent";
    $criteria{$rightCol} = $self->{$leftCol};
  }
  $view->preselectWhere(\%criteria);
}



#----------------------------------------------------------------------
# RUNTIME PRIVATE METHODS
#----------------------------------------------------------------------



sub _debug { # internal method to send debug messages
  my ($self, $msg) = @_;
  my $debug = $self->schema->classData->{debug};
  if ($debug) {
    if (ref($debug)) { $debug->debug($msg) }
    else             { carp $msg; }
  }
}


sub _parseSelectArgs { # named or positional args to the select() method
  my %args;

  if ($_[0] and not ref($_[0]) and $_[0] =~ /^-/) { # called with named args
    %args = @_;
  }
  else { # we were called with unnamed args (all optional!), so we try
         # to guess which is which from their datatypes.
    $args{-columns}   = shift unless UNIVERSAL::isa($_[0], 'HASH');
    $args{-where}     = shift unless UNIVERSAL::isa($_[0], 'ARRAY');
    $args{-orderBy}   = shift unless UNIVERSAL::isa($_[0], 'HASH');
    croak "too many args to select()" if @_;
  }
  return \%args;
}


sub _addSelectCriteria { # prepare appropriate structure for SQL::Abstract
  my ($args, @moreWhere) = @_;
  my %where;
  foreach my $crit ($args->{-where}, @moreWhere) {
    if    (ref($crit) eq 'HASH')  {
      @where{keys %$crit} = values %$crit
    }
    elsif (ref($crit) eq 'ARRAY') {
      $where{-nest} = $where{-nest} ? 
	                 [-and => [-nest => $where{-nest}, -nest => $crit]] :
			 $crit;
    }
    elsif ($crit) {
      $where{$crit} = \"";
    }
  }
  $args->{-where} = \%where;
}


1; # End of DBIx::DataModel::AbstractTable

__END__

=head1 NAME

DBIx::DataModel::AbstractTable - Abstract parent for Table and View 

=head1 DESCRIPTION

Abstract parent class for L<DBIx::DataModel::Table|DBIx::DataModel::Table> and
L<DBIx::DataModel::View|DBIx::DataModel::View>. For internal use only.


=head1 METHODS

Methods are documented in L<DBIx::DataModel|DBIx::DataModel>. This module
implements 

=over

=item L<MethodFromRoles|DBIx::DataModel/MethodFromRoles>

=item L<schema|DBIx::DataModel/schema>

=item L<db_table|DBIx::DataModel/db_table>

=item L<selectImplicitlyFor|DBIx::DataModel/selectImplicitlyFor>

=item L<blessFromDB|DBIx::DataModel/blessFromDB>

=item L<select|DBIx::DataModel/select>

=item L<preselectWhere|DBIx::DataModel/preselectWhere>

=item L<applyColumnHandler|DBIx::DataModel/applyColumnHandler>

=item L<expand|DBIx::DataModel/expand>

=item L<autoExpand|DBIx::DataModel/autoExpand>

=item L<selectFromRoles|DBIx::DataModel/selectFromRoles>

=back


=head1 AUTHOR

Laurent Dami, E<lt>laurent.dami AT etat  geneve  chE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2006 by Laurent Dami.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

