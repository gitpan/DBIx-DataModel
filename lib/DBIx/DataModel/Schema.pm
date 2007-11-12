#----------------------------------------------------------------------
package DBIx::DataModel::Schema;
#----------------------------------------------------------------------

# see POD doc at end of file
# version : see DBIx::DataModel

use warnings;
use strict;
use Carp;
use base 'DBIx::DataModel::Base';
use SQL::Abstract;
use DBIx::DataModel::Table;
use DBIx::DataModel::View;

our @CARP_NOT = qw/DBIx::DataModel         DBIx::DataModel::AbstractTable
		   DBIx::DataModel::Table  DBIx::DataModel::View         /;

#----------------------------------------------------------------------
# PACKAGE DATA
#----------------------------------------------------------------------

my $sqlDialects = {
 Default => {
   innerJoin         => "%s INNER JOIN %s ON %s",
   leftJoin          => "%s LEFT OUTER JOIN %s ON %s",
   joinAssociativity => "left",
   columnAlias       => "%s AS %s",
 },
 MsAccess => {
   innerJoin         => "%s INNER JOIN (%s) ON %s",
   leftJoin          => "%s LEFT OUTER JOIN (%s) ON %s",
   joinAssociativity => "right",
   columnAlias       => "%s AS %s",
 },
 BasisODBC => {
   innerJoin         => undef, 
   leftJoin          => "%s LEFT OUTER JOIN %s ON %s",
   joinAssociativity => "left",
   columnAlias       => "%s AS %s",
 },
 BasisJDBC => {
   innerJoin         => "%s INNER JOIN %s ON %s",
   leftJoin          => "%s LEFT OUTER JOIN %s ON %s",
   joinAssociativity => "left",
   columnAlias       => "%s %s",
 },
};


#----------------------------------------------------------------------
# COMPILE-TIME METHODS
#----------------------------------------------------------------------


sub _subclass { # this is the implementation of DBIx::DataModel->Schema(..)
  my ($class, $pckName, @args) = @_;

  my %params = (@args == 1)      # if only one arg ..
             ? (dbh => $args[0]) # .. then old API (positional arg : dbh)
             : @args;            # .. otherwise, named args

  my ($bad_param) = grep {$_ !~ /^(dbh|sqlDialect|tableParent|viewParent)$/}
                         keys %params;
  croak "Schema(): invalid parameter: $bad_param" if $bad_param;

  # record some schema-specific global variables 
  my $classData = {
    sqlAbstr        => SQL::Abstract->new(),
    columnType      => {}, # {typeName => {handler1 => code1, ...}}
    noUpdateColumns => [],
    debug           => undef,
  };
  for my $key (qw/tableParent viewParent/) {
    my $parent = $params{$key} or next;
    ref $parent or $parent = [$parent];
    $classData->{$key} = $parent;
  }

  $class->_setClassData($pckName => $classData);
  $class->_createPackage($pckName => [$class]);

  $pckName->dbh($params{dbh}) if $params{dbh};

  # _SqlDialect : needs some reshuffling of args, for backwards compatibility :
  # input : scalar or hashref; output : array
  my @dialect_args = 
    UNIVERSAL::isa($params{sqlDialect}, 'HASH') 
	? %{$params{sqlDialect}}
	: ( $params{sqlDialect} || 'Default' );

  $pckName->_SqlDialect(@dialect_args);

  return $pckName;
}




sub SqlDialect {
  carp "SqlDialect() is deprecated. Instead, pass dialect as argument to Schema() creation";
  goto &_SqlDialect;
}


sub _SqlDialect {
  my $class = shift;

  my $args = (@_ == 1) ?
    $sqlDialects->{$_[0]} || croak "invalid SQL dialect: $_[0]" :
    {@_};

  while (my ($k, $v) = each %$args) {
    $k =~ /^(innerJoin|leftJoin|joinAssociativity|columnAlias)$/
      or croak "invalid argument to SqlDialect: $k";
    $class->classData->{sqlDialect}{$k} = $v;
  }
}


sub Table {
  my ($class, $table, $db_table, @primKey) = @_;

  push @{$class->classData->{tables}}, $table;

  $class->_setClassData($table => {
    schema    => $class,
    db_table  => $db_table,
    columns   => '*',
    primKey   => \@primKey,
  });

  my $isa = $class->classData->{tableParent}
         || ['DBIx::DataModel::Table'];
  return $class->_createPackage($table, $isa);
}

sub View {
  my ($class, $view, $columns, $db_tables, $where, @parentTables) = @_;
  push @{$class->classData->{views}}, $view;

  $class->_setClassData($view => {
    schema    	 => $class,
    db_table  	 => $db_tables,
    columns   	 => $columns,
    where     	 => $where,
    parentTables => \@parentTables,
  });

  my $isa = $class->classData->{viewParent}
         || ['DBIx::DataModel::View'];
  push @$isa, @parentTables;
  return $class->_createPackage($view, $isa);
}





sub Association {
  my ($schema, $args1, $args2) = @_;

  my ($table1, $role1, $multipl1, @cols1) = @$args1;
  my ($table2, $role2, $multipl2, @cols2) = @$args2;

  my $implement_assoc = "_Assoc_normal";

  my $many1 = _multipl_max($multipl1) > 1 ? "T" : "F";
  my $many2 = _multipl_max($multipl2) > 1 ? "T" : "F";

  # handle implicit column names
  for ($many1 . $many2) {
    /^TT/ and do {$implement_assoc = "_Assoc_many_many"; 
                  last};
    /^TF/ and do {@cols2 or @cols2 = $table2->primKey;
                  @cols1 or @cols1 = @cols2;
                  last};
    /^FT/ and do {@cols1 or @cols1 = $table1->primKey;
                  @cols2 or @cols2 = @cols1;
                  last};
    /^FF/ and do {@cols1 && @cols2 
                         or croak "Association: columns must be explicit "
                                . "with multiplicities $multipl1 / $multipl2";};
  }
  @cols1 == @cols2 or croak "Association: numbers of columns do not match";

  $schema->$implement_assoc($table1, $role1, $multipl1, \@cols1, 
			    $table2, $multipl2, \@cols2);
  $schema->$implement_assoc($table2, $role2, $multipl2, \@cols2, 
			    $table1, $multipl1, \@cols1);
}

# Normal Association implementation, when one side is of multiplicity one
sub _Assoc_normal { 
  my ($schema, $table, $role, $multipl, $cols_ref, 
               $foreign_table, $foreign_multipl, $foreign_cols_ref) = @_;

  return if not $role or $role =~ /^(0|""|''|none)$/; 

  $table->isa('DBIx::DataModel::Table') or 
    croak "Association : $table is not a Table class";

  # build select method as a closure, and install it into foreign table
  my $select_meth = sub {
    my $self = shift; 
    ref($self) or croak "role $role cannot be called as class method";

    # if called without args, and that role was previously expanded,
    # then return the cached version
    return $self->{$role} if $self->{$role} and not @_;

    my ($missing_fk) = grep {not exists $self->{$_}} @$foreign_cols_ref;
    croak "cannot follow role $role if foreign key $missing_fk is absent" 
      if $missing_fk;
    my %joinCols = ();
    @joinCols{@$cols_ref} = @{$self}{@$foreign_cols_ref};
    $table->preselectWhere(\%joinCols, $multipl)->(@_);
  };
  $schema->_defineMethod($foreign_table, $role, $select_meth);


  if (_multipl_max($multipl) > 1) { # one to many

    my $m_name = "insert_into_$role";

    # build insert method as a closure, and install it into foreign table
    my $insert_meth = sub {

      my $self = shift;	# remaining @_ contains refs to records for insert()
      ref($self) or croak "$m_name cannot be called as class method";

      # add join information into records that will be inserted
      foreach my $record (@_) {
	not (grep {$record->{$_}} @$cols_ref) or
	  croak "args to $m_name should not contain values in @$cols_ref";
	@{$record}{@$cols_ref} = @{$self}{@$foreign_cols_ref};
      }

      return $table->insert(@_);
    };
    $schema->_defineMethod($foreign_table, $m_name, $insert_meth);
  }

  # record join parameters in schema->classData
  my %where;
  @where{@$foreign_cols_ref} = @$cols_ref;
  $schema->classData->{joins}{$foreign_table}{$role} = {
    multiplicity => $multipl,
    table        => $table,
    where        => \%where,
  };
}


# special implementation for many-to-many Association
sub _Assoc_many_many {
  my ($schema, $table, $role, $multipl, $cols_ref, 
               $foreign_table, $foreign_multipl, $foreign_cols_ref) = @_;

  scalar(@$cols_ref) == 2 or 
    croak "improper number of roles in many-to-many association";
  $foreign_table->MethodFromRoles($role => @$cols_ref);
}


sub Composition {
  my ($schema, $args1, $args2) = @_;

  my ($table1, $role1, $multipl1, @cols1) = @$args1;
  my ($table2, $role2, $multipl2, @cols2) = @$args2;
  _multipl_max($multipl1) == 1
    or croak "max multiplicity of first class in a composition must be 1";
  _multipl_max($multipl2) > 1
    or croak "max multiplicity of second class in a composition must be > 1";

  # check for conflicting compositions
  my $component_of = $table2->classData->{component_of} || {};
  while (my ($composite, $multipl) = each %$component_of) {
    _multipl_min($multipl) == 0 
      or croak "$table2 can't be a component of $table1 "
             . "(already component of $composite)";
  }
  $table2->classData->{component_of}{$table1} = $multipl1;

  # implement the association
  $schema->Association($args1, $args2);
  $schema->classData->{joins}{$table1}{$role2}{is_composition} = 1;
}


sub ViewFromRoles {
  my ($class, $table, @roles) = @_;

  croak "ViewFromRoles: improper argument (ref)" 
    if ref($table) or grep {ref $_} @roles;

  foreach (@roles) {
    s[^(INNER|<=>)$] [_INNER_];
    s[^(LEFT|=>)$]   [_LEFT_];
  }

  my $viewName = join "", "${class}::AutoView::", $table, map(ucfirst, @roles);  

  # 0) do nothing if view was already generated
  {
    no strict 'refs';
    return $viewName if defined (%{$viewName.'::'});
  }

  # 1) go through the roles and accumulate information 

  my @parentTables = ($table);
  my @innerJoins;
  my @leftJoins;
  my $joinInto = \@innerJoins; # initially; might change later to \@leftJoins

#  my $curTable = $table;
 
  my @seenTables = ($table);


  my $forcedJoin;

 ROLE:
  foreach my $role (@roles) {

    for ($role) {
      /^_INNER_$/ and do {$forcedJoin = \@innerJoins; next ROLE;};
      /^_LEFT_$/  and do {$forcedJoin = \@leftJoins;  next ROLE;};
    }

    my ($curTable, $joinData);
    foreach (@seenTables) {
      $curTable = $_;
      $joinData = $class->classData->{joins}{$curTable}{$role};
      last if $joinData;
    }
    $joinData or croak "ViewFromRoles: role $role not found";

    if ($forcedJoin) { 
      $joinInto = $forcedJoin;
      # THINK : maybe should not allow forced _INNER_ after an initial _LEFT_
      $forcedJoin = undef;
    }
    elsif (_multipl_min($joinData->{multiplicity}) == 0) {
      $joinInto = \@leftJoins;
    }

    my $nextTable = $joinData->{table};
    unshift @seenTables, $nextTable;

    my $where = $joinData->{where};
    my $dbTableLeft  = $curTable ->db_table;
    my $dbTableRight = $nextTable->db_table;
    my @criteria = map {"$dbTableLeft.$_=$dbTableRight.$where->{$_}"} 
                       keys %$where;
    push @$joinInto, [$nextTable->db_table => join(" AND ", @criteria)];
    push @parentTables, $nextTable;
  }

  # 2) build SQL, following the joins (first inner joins, then left joins)

  my $sqlDialect = $class->classData->{sqlDialect};
  my $where = {};
  my $sql = "";

  if (not @innerJoins) {
    $sql = $table->db_table;
  } elsif ($sqlDialect->{innerJoin}) {
    $sql = _sqlJoins($table->db_table, 
		     \@innerJoins, 
		     $sqlDialect->{innerJoin},
		     $sqlDialect->{joinAssociativity});
  } else {
    $sql = join ", ", $table->db_table, map {$_->[0]} @innerJoins;
    $where = join " AND ", map {$_->[1]} @innerJoins;
  }
  
  $sql = _sqlJoins($sql,
		   \@leftJoins, 
		   $sqlDialect->{leftJoin},
		   $sqlDialect->{joinAssociativity}) if @leftJoins;

  # 3) install the View

  return $class->View($viewName, '*', $sql, $where, @parentTables);
}




sub ColumnType {
  my ($class, $typeName, @args) = @_;

  $class->classData->{columnHandlers}{$typeName} = {@args};
}



sub Autoload { # forward to AbstractTable so that Tables and Views inherit it
  my ($class, $toggle) = @_;
  DBIx::DataModel::AbstractTable->Autoload($toggle);
}


#----------------------------------------------------------------------
# RUNTIME METHODS
#----------------------------------------------------------------------

sub dbh {
  my ($class, $dbh, %options) = @_;
  my $classData = $class->classData;
  if ($dbh) {
    $dbh->{RaiseError} or croak "arg to dbh(..) must have RaiseError=1";
    $classData->{dbh}         = $dbh;
    $classData->{dbh_options} = \%options;
  }
  return wantarray ? ($classData->{dbh}, %{$classData->{dbh_options} || {}})
                   : $classData->{dbh};
}

sub debug { 
  my ($class, $debug) = @_;
  $class->classData->{debug} = $debug; # will be used by internal _debug
}


sub autoInsertColumns {
  my $class = shift; 
  return @{$class->classData->{autoInsertColumns} || []};
}

sub autoUpdateColumns {
  my $class = shift; 
  return @{$class->classData->{autoUpdateColumns} || []};
}

sub noUpdateColumns {
  my $class = shift; 
  return @{$class->classData->{noUpdateColumns} || []};
}


sub selectImplicitlyFor {
  my $class = shift;

  if (@_) {
    $class->classData->{selectImplicitlyFor} = shift;
  }
  return $class->classData->{selectImplicitlyFor};
}


sub tables {
  my $class = shift;
  return @{$class->classData->{tables}};
}


sub views {
  my $class = shift;
  return @{$class->classData->{views}};
}


sub doTransaction { 
  my ($class, $coderef) = @_;

  my $dbh = $class->dbh or croak "no database handle for transaction";

  # how to call and how to return will depend on context
  my $want = wantarray ? "array" : defined(wantarray) ? "scalar" : "void";
  my ($return_scalar, @return_array);
  my $call_in_context = {
    array  => sub {@return_array  = $coderef->()},
    scalar => sub {$return_scalar = $coderef->()},
    void   => sub {                 $coderef->()},
   }->{$want};
  my $return_in_context = {
    array  => sub {return @return_array },
    scalar => sub {return $return_scalar},
    void   => sub {return               },
   }->{$want};

  if (! $dbh->{AutoCommit}) { # if already within a transaction, just execute
    $call_in_context->();
  }
  else {                      # else try to execute and commit
    $dbh->begin_work;
    eval { $call_in_context->(); $dbh->commit; 1};
    my $errstr = $@;
    if ($errstr) { # the transaction failed
      my $rollback_status = 'OK';
      eval {$dbh->rollback; 1} # "1" needed because some drivers (JDBC) do 
                               # not return true upon rollback
        or $rollback_status = "FAILED $@";
      croak "FAILED TRANSACTION: $errstr (rollback: $rollback_status)";
    };
  }

  return $return_in_context->();
}


sub keepLasth {
  my $class = shift;

  if (@_) {
    $class->classData->{keepLasth} = shift;
  }
  return $class->classData->{keepLasth};
}


sub lasth {
  my ($class) = @_;
  return $class->classData->{lasth};
}



sub _sqlJoins { # connect a sequence of joins according to SQL dialect
  my ($leftmost, $joins, $joinSyntax, $associativity) = @_;

  my $sql;

  if ($associativity eq "right") {
    my $joinOn;
    ($sql, $joinOn) = @{pop @$joins};
    foreach my $operand (reverse(@$joins), [$leftmost, undef]) {
      $sql = sprintf $joinSyntax, $operand->[0], $sql, $joinOn;
      $joinOn = $operand->[1];
    }
  } else {			# left associativity
    $sql = $leftmost;
    foreach my $operand (@$joins) {
      $sql = sprintf $joinSyntax, $sql, $operand->[0], $operand->[1];
    }
  }
  return $sql;
}


#----------------------------------------------------------------------
# UTILITY METHODS (PRIVATE)
#----------------------------------------------------------------------


sub _createPackage {
  my ($schema, $pckName, $isa_arrayref) = @_;
  no strict 'refs';

  not defined(%{$pckName.'::'}) or croak "package $pckName is already defined";
  *{$pckName."::ISA"} = $isa_arrayref;
  return $pckName;
}



sub _defineMethod {
  my ($schema, $pckName, $methName, $coderef) = @_;
  my $fullName = $pckName.'::'.$methName;

  no strict 'refs';

  if ($coderef) {
    not defined(&{$fullName}) or 
      croak "method $fullName is already defined";
    *{$fullName} = $coderef;
  }
  else {
    delete ${$pckName.'::'}{$methName};
  }
}


#----------------------------------------------------------------------
# UTILITY FUNCTIONS (PRIVATE)
#----------------------------------------------------------------------


sub _multipl_min {
  my $multiplicity = shift;
  for ($multiplicity) {
    /^(\d+)/ and return $1;
    /^[*n]$/ and return 0;
  }
  croak "illegal multiplicity : $multiplicity";
}

use constant LARGE_NUMBER => 9999;

sub _multipl_max {
  my $multiplicity = shift;
  for ($multiplicity) {
    /(\d+)$/ and return $1;
    /[*n]$/  and return LARGE_NUMBER;
  }
  croak "illegal multiplicity : $multiplicity";
}



1; # End of DBIx::DataModel::Schema

__END__

=head1 NAME

DBIx::DataModel::Schema - Factory for DBIx::DataModel Schemas

=head1 DESCRIPTION

This is the parent class for all schema classes created through

  DBIx::DataModel->Schema($schema_name, ...);

=head1 METHODS

Methods are documented in L<DBIx::DataModel|DBIx::DataModel>. This module
implements 

=over

=item L<Schema|DBIx::DataModel/Schema>

=item L<Table|DBIx::DataModel/Table>

=item L<View|DBIx::DataModel/View>

=item L<Association|DBIx::DataModel/Association>

=item L<ViewFromRoles|DBIx::DataModel/ViewFromRoles>

=item L<ColumnType|DBIx::DataModel/ColumnType>

=item L<dbh|DBIx::DataModel/dbh>

=item L<debug|DBIx::DataModel/debug>

=item L<noUpdateColumns|DBIx::DataModel/noUpdateColumns>

=item L<autoUpdateColumns|DBIx::DataModel/autoUpdateColumns>

=item L<selectImplicitlyFor|DBIx::DataModel/selectImplicitlyFor>

=item L<tables|DBIx::DataModel/tables>

=item L<views|DBIx::DataModel/views>

=item L<doTransaction|DBIx::DataModel/doTransaction>

=item L<keepLasth|DBIx::DataModel/keepLasth>

=item L<lasth|DBIx::DataModel/lasth>

=item L<_createPackage|DBIx::DataModel/_createPackage>

=item L<_defineMethod|DBIx::DataModel/_defineMethod>

=back



=head1 AUTHOR

Laurent Dami, E<lt>laurent.dami AT etat  geneve  chE<gt>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Laurent Dami.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.




