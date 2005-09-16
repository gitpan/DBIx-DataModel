############################################################
package DBIx::DataModel;
############################################################
use strict;
use warnings;
use Carp;
use DBI;
use SQL::Abstract;

our $VERSION = '0.10';

=head1 NAME

DBIx::DataModel - Classes and UML-style Associations on top of DBI

=head1 SYNOPSIS

=head3 in file "MySchema.pm"

Declare the schema

  use DBIx::DataModel;
  DBIx::DataModel->Schema('MySchema'); # MySchema is now a Perl package

Declare the tables with 
C<< (Perl_name => DB_name => primary key column(s)) >>.
Each table then becomes a Perl package.

  MySchema->Table(Employee   => Employee   => qw/emp_id/);
  MySchema->Table(Department => Department => qw/dpt_id/);
  MySchema->Table(Activity   => Activity   => qw/act_id/);

Declare associations in UML style
( C<< [table1 role1 arity1 join1], [table2...] >>).

  MySchema->Association([qw/Activity   activities * emp_id/],
                        [qw/Employee   employee   1 emp_id/]);
  MySchema->Association([qw/Activity   activities * dpt_id/],
                        [qw/Department department 1 dpt_id/]);

Declare "column types" with some handlers ..

  # date conversion between database (yyyy-mm-dd) and user (dd.mm.yyyy)
  MySchema->ColumnType(Date => 
     fromDB   => sub {$_[0] =~ s/(\d\d\d\d)-(\d\d)-(\d\d)/$3.$2.$1/},
     toDB     => sub {$_[0] =~ s/(\d\d)\.(\d\d)\.(\d\d\d\d)/$3-$2-$1/},
     validate => sub {$_[0] =~ m/(\d\d)\.(\d\d)\.(\d\d\d\d)/});
  
  # 'percent' conversion between database (0.8) and user (80)
  MySchema->ColumnType(Percent => 
     fromDB   => sub {$_[0] *= 100 if $_[0]},
     toDB     => sub {$_[0] /= 100 if $_[0]},
     validate => sub {$_[0] =~ /1?\d?\d/});

.. and apply these "column types" so some of our columns

  Employee->ColumnType(Date    => qw/d_birth/);
  Activity->ColumnType(Date    => qw/d_begin d_end/);
  Activity->ColumnType(Percent => qw/employment_rate/);

Declare a column that will be filled automatically
at each update

  MySchema->AutoUpdateColumns(last_modif => 
    sub{$ENV{REMOTE_USER}.", ".scalar(localtime)});

For details that could not be expressed in a declarative way,
just add a new method into the table class (but in that case,
Schema and Table declarations should be in a BEGIN block, so that
the table class is defined before you start adding methods to it).

  package Activity; 
  
  sub activePeriod {
    my $self = shift;
    $self->{d_end} ? "from $self->{d_begin} to $self->{d_end}"
                   : "since $self->{d_begin}";
  }

Declare how to automatically expand objects into data trees

  Activity->AutoExpand(qw/employee department/);

=head3 in file "myClient.pl"

  use MySchema;

Search employees whose name starts with 'D'
(select API is taken from L<SQL::Abstract>)

  my $empl_D = Employee->select({lastname => {-like => 'D%'}});

idem, but we just want a subset of the columns

  my $empl_F = Employee->select([qw/firstname lastname emp_id/],
                                {lastname => {-like => 'F%'}});

Get a list of employee names in age order

  my $ageLst = Employee->select([qw/lastname firstname/], {}, ['d_birth']);

Print some info from employees, either by direct access to the
hashref, or by a method call (handled via AUTOLOAD). Because of the
'fromDB' handler associated with column type 'date', column 'd_birth'
has been automatically converted to display format.

  foreach my $emp (@$empl_D) {
    printf "%s (%s) : %s\n", 
      $emp->{firstname}, $emp->lastname, $emp->d_birth;
  }


Follow the joins through role methods

  foreach my $act (@{$emp->activities}) {
    printf "working for %s from $act->{d_begin} to $act->{d_end}", 
      $act->department->name;
  }

Export the data : external helper modules usually expect
a full data tree (instead of calling methods dynamically), so 
we need to expand the objects :

  $_->expand('activities') foreach @$empl_D;
  my $export = {employees => $empl_D};
  use Data::Dumper; print Dumper   ($export); # export as PerlDump
  use XML::Simple;  print XMLout   ($export); # export as XML
  use JSON;         print objToJson($export); # export as Javascript

Select associated tables directly from a database join, 
in one single SQL statement (instead of iterating through role methods).
  
  my $lst = MySchema->ViewFromRoles(qw/Employee activities department/)
                    ->select([qw/lastname dept_name d_begin/], 
                             {d_begin => {'>=' => '2000-01-01'}});

=head1 DESCRIPTION

This is yet, yet, yet another wrapper framework to build Perl classes
and objects around database tables and records. There are many other
CPAN modules in this area; perhaps the mere fact that they are so
numerous demonstrates that there is more than one way to do it, and
none is obviously the best, so why not propose another one ?
The L<SEE ALSO> section at the end of this documentation gives 
some pointers.

C<DBIx::DataModel> is written compactly as one single module,
and only depends on L<DBI> and L<SQL::Abstract>.
It is intended to help client applications in performing
common tasks such as data conversion and associations between tables,
while retaining an open access both to the base DBI layer and to the
basic Perl datastructures, whenever lower-level operations are needed.
The focus is on building trees of data which can then be passed to
external helper modules for generating XML, Perl dumps,
javascript JSON, templates of the Template Toolkit, etc. Such modules
need to walk on the data tree, so they cannot work if everything is
implemented as OO methods to be called on demand (because there is no
simple way to ask for all available methods, and even if you get
there, it is not possible to distinguish which of those methods
encapsulate relevant data). Therefore C<DBIx::DataModel> does not
insist on OO information hiding; on the contrary, direct access
to the object hash is encouraged for inspecting the data. In the
same spirit, transaction handling is left to the client code.

C<DBIx::DataModel> defines an API for accessing the database from Perl,
but will not create the database itself. So use your best
database administration tools to define your schemas, tables, keys, 
relationships and integrity rules;  then tell the bare minimum 
to C<DBIx::DataModel> so that Perl programs can work with the data.
To do so, you first declare your tables with their primary 
keys. Then you declare UML I<binary associations>, which will give
you a couple of methods to walk through the data,
possibly with some additional WHERE filters. From your associations, 
you can also generate some C<Views> to directly query 
a list of tables, with the appropriate joins between them.
At each method call, it is possible
to specify which subset of columns should be retrieved 
(or to rely on the default, namely '*').

Columns may have some associated I<handlers> for performing data transformation
of validation. You may also define I<column types> in your schema so that
every column of a given type inherits the same collection of handlers
(think for example of a 'date' type or a 'phoneNumber' type).

DISCLAIMER: this code is still in beta, the API may slightly
change in future versions.

=cut


my %classData; # {className => {classProperty => value, ...}}

=head1 METHODS

B<General convention> : method names starting with an uppercase letter
are meant to be compile-time class methods.  These methods will
typically be called when loading a module like 'MySchema.pm', and
therefore will be executed during the BEGIN phase of the Perl
compiler.  They instruct the compiler to create classes, methods and
datastructures for representing the elements of a database schema.

Method names starting with a lowercase letter are meant to be usual
run-time methods, either for classes or for instances.


=head2 Compile-time methods


=head3 Framework methods 

=head4 Schema

  DBIx::DataModel->Schema($schemaName [ => $dbh ] )

Creates a new Perl class of name C<$schemaName> that represents a 
database schema.
That class inherits from C<DBIx::DataModel>.
The connection to a DBI database handle can be set via the optional C<$dbh>
argument (but it can also be set or reset later) via the L<dbh> method.

=cut

sub Schema {
  my ($class, $pckName, $dbh) = @_;

  croak "'Schema' must be called on " . __PACKAGE__ if
    ref($class) or $class ne __PACKAGE__;

  # record some schema-specific global variables 
  $classData{$pckName} = {
    classKind  => 'Schema',
    schema     => $pckName,
    dbh        => $dbh,
    sqlAbstr   => new SQL::Abstract,
    columnType => {}, # {typeName => {handler1 => code1, ...}}
    noUpdateColumns => [],
    debug      => undef,
  };

  _createPackage($pckName => [__PACKAGE__]);
  return $dbh;
}

=head3 Schema methods

=head4 Table

  MySchema->Table($pckName, $dbTable, @primKey)

Creates a new Perl class of name C<$pckName> that represents a 
database Table. That class inherits from C<MySchema>.
C<< $dbTable >> should contain the name of the table in the database.
C<< @primKey >> should contain the name(s) of the column(s) holding the primary
key for that table. This info will be used for interpreting arguments
to the L<fetch> method, and for filling WHERE clauses in the SQL 
generated by the L<update> method.


=cut

sub Table {
  my ($schema, $pckName, $dbTable, @primKey) = @_;

  $schema->isSchema or croak "'Table' is a schema class method";
  
  # record some table-specific data
  $classData{$pckName} = {
    classKind => 'Table',
    schema    => $schema,
    table     => $dbTable,
    columns   => '*',
    primKey   => \@primKey,
  };

  _createPackage($pckName => [$schema]);
}


=head4 View

  MySchema->View($viewName =>$columns => $dbTables => \%where, @parentTables)

Creates a new Perl class of name C<$viewName> that represents a
SQL SELECT request. The only method of that class is the L<select> 
method, which will 

=over

=item *

select records from the database according to the criteria of the view, 
merged with the criteria of the request;

=item *

apply the 'fromDB' handlers of the parent tables to those records;

=item *

bless the results into objects of C<MyView> that inherit the
role methods of each of the @parentTables (see method
L<Association> below).

=back

Views are useful to build queries with specific SQL clauses like for example

  MySchema->View(MyView =>
     "DISTINCT column1 AS c1, t2.column2 AS c2",
     "Table1 AS t1 LEFT OUTER JOIN Table2 AS t2 ON t1.fk=t2.pk",
     {c1 => 'foo', c2 => {-like => 'bar%'}},
     @parentTables)

See L<SQL::Abstract> and the L<select> method below for a complete
description of what to put in the C<%where> argument. For the moment,
just consider the following example: 

  my $lst = MyView->select({c3 => 22});

would generate the SQL statement:

  SELECT DISTINCT column1 AS c1, t2.column2 AS c2
  FROM  Table1 AS t1 
        LEFT OUTER JOIN Table2 AS t2 ON t1.fk=t2.pk
  WHERE (c1 = 'foo' AND c2 LIKE 'bar%' AND c3 = 22)

The optional list of C<< @parentTables >> contains names of Perl 
table classes from which the view will inherit (so that 
role methods of these tables become available to instances
of C<MyView>).

Perl views as defined here have nothing to do with views declared in
the database itself. Perl views are totally unknown to the database,
they are just abstractions of SQL statements.  If you need to access
database views, just use the C<Table> declaration, like for a regular
table.

=cut

sub View {
  my ($schema, $pckName, $columns, $dbTables, $where, @parentTables) = @_;

  $schema->isSchema or croak "'View' is a schema class method";
  
  # record some table-specific data
  $classData{$pckName} = {
    classKind => 'View',
    schema    => $schema,
    table     => $dbTables,
    columns   => $columns,
    where     => $where,
    parentTables => \@parentTables,
  };


  # create a new package that inherits from @parentTables or from Schema
  no strict 'refs';
  @parentTables = ($schema) unless @parentTables;

  _createPackage($pckName => \@parentTables);
  _defineMethod ($pckName => applyColumnHandlers => \&_viewApplyColumnHandlers);
}


=head4 Association

  MySchema->Association([$table1, $role1, $arity1, @columns1], 
                        [$table2, $role2, $arity2, @columns2]);

Declares an association between two tables (or even two instances of
the same table), in a UML-like fashion. Each side of the association
specifies its table, the "rolename" of of this table in the
association, the arity (also called "multiplicity"), and the name of
the column or list of columns that technically implement the
association as a database join. Arities should be written in the UML form
'0..*', '1..*', '0..1', etc. (minimum .. maximum number of occurrences); this
will influence how role methods and views are implemented,
as explained below. Arity '*' is a shortcut for '0..*', and arity
'1' is a shortcut for '1..1'. Role names should be chosen so as 
to avoid conflicts with column names in the same table.

As a result of the association declaration, the Perl class
corresponding to C<< $table1 >> will get an additional method named
C<< $role2 >> for accessing the associated object(s) in C<< $table2 >>; 
that method normally returns an arrayref, unless C<< $arity2 >>
has maximum '1' (in that case the return value is a single object
ref).  Of course, C<< $table2 >> conversely gets a method named 
C<< $role1 >>.

Such role methods perform joins within Perl (as opposed to joins
directly performed within the database). That is, given a declaration

  MySchema->Association([qw/Activity   activities 0..* emp_id/],
                        [qw/Employee   employee   1 emp_id/]);

we can call

  my @acts = $anEmployee->activities

which will implicitly perform a 

  SELECT * FROM Activity WHERE emp_id = $anEmployee->{emp_id}

The role method can also accept additional parameters
in L<SQL::Abstract> format (see also the L<select> method
in this module). So for example

  my @acts = $anEmployee->activities([qw/act_name salary/], {isActive => 'Y'});

would perform the following SQL request :

  SELECT act_name, salary FROM Activity WHERE 
    emp_id = $anEmployee->{emp_id} AND
    isActive = 'Y'

To specify a unidirectional association, just supply 
0 or an empty string (or even the string C<"0"> or C<'""'> or C<"none">)
to one of the role names. In that case the corresponding role
method is not generated.

The C<Association> method only supports binary associations; however,
you can create a C<View> from a series of associations, in order
to simultaneously join many tables : see method L<ViewFromRoles>.

=cut


sub Association {
  my ($schema, $args1, $args2) = @_;

  $schema->isSchema or croak "'Association' is a schema class method";

  my ($table1, $role1, $arity1, @cols1) = @$args1;
  my ($table2, $role2, $arity2, @cols2) = @$args2;

  @cols1 == @cols2 or croak "Association: numbers of columns do not match";
  
  # build an accessor method for each side of the association
  for ([$table1, $role1, $arity1, \@cols1, $table2, $arity2, \@cols2],
       [$table2, $role2, $arity2, \@cols2, $table1, $arity1, \@cols1])
  {
    my ($t, $r, $a, $c, $foreign_t, $foreign_a, $foreign_c) = @$_;

    next if not $r or $r =~ /^(0|""|''|none)$/;

    $t->classData->{classKind} eq 'Table' or 
      croak "Association : $t is not a Table class";

    # build method as a closure 
    my $meth = sub {
      my ($self, @selectArgs) = @_; # $self will be  of class $foreign_t 
      ref($self) or croak "role $r cannot be called as class method";

      my %joinCols = ();
      @joinCols{@$c} = @{$self}{@$foreign_c};
      my $assoc = $t->select(@selectArgs, \%joinCols);

      if ($a =~ /^([01]\.\.)?1$/) { # if maximum arity 1 
	@$assoc <= 1 or 
	  carp "too many results for ${foreign_t}::$r of arity $a";
	return $assoc->[0];	    # return a single object
      }
      else {                        # if maximum arity n
	return $assoc;              # return an array ref 
      }
    };

    # install method
    _defineMethod($foreign_t => $r => $meth);

    # record join parameters in schema->classData
    my %where;
    foreach (0..$#$c) {
      $where{$foreign_t->table . "." . $foreign_c->[$_]} = 
	$t->table . "." . $c->[$_];
    }
    $schema->classData->{joins}{$foreign_t}{$r} = {
      arity => $a,
      table => $t,
      where => \%where
     };
  }
}


=head4 ViewFromRoles

  my $view = MySchema->ViewFromRoles($table => $role1 => $role2 => ..);

Creates a C<View> class, starting from a given Table Class and
following one or several associations through their role names.
It calls the L<View> method, with a collection of parameters
automatically inferred from the associations. So for example

  MySchema->ViewFromRoles(qw/Department activities employee/)

is equivalent to 

  MySchema->View(DepartmentActivitiesEmployee => '*' =>
                  'Department, Employee 
                       LEFT OUTER JOIN Activity
                       ON Department.dpt_id = Activity.dpt_id
                      WHERE
                        Activity.emp_id = Employee.emp_id',
                 qw/Department Activity Employee/);

For each pair of tables, the kind of join is chosen according to
the arity declared with the role : if the minimum arity is 0, 
the join will be LEFT OUTER JOIN; otherwise it will be a usual inner join.
Left outer joins are arranged to be a the end of the SELECT statement.

The view name will be composed by concatenating the table and 
the capitalized role names. Such names might be long and uncomfortable 
to use, so the view name is also returned as result of the method
call, so that the client code can store it in a variable and use
it as an alias.

The main purpose of C<ViewFromRoles> is to gain efficiency in
interacting with the database. If we write

  foreach my $dpt (Department->select) {
    foreach my $act ($dpt->activities) {
      my $emp = $act->employee;
      printf "%s works in %s since %s\n", 
         $emp->lastname, $dpt->dpt_name, $act->d_begin
    }
  }

many database calls are generated behind the scene. 
Instead we could write 

  my $view = MySchema->ViewFromRoles(qw/Department activities employee/);
  foreach my $row ($view->select) {
    printf "%s works in %s since %s\n", 
      $row->lastname, $row->dpt_name, $row->d_begin

  }

which generates one single call to the database.

Currently, C<ViewFromRoles> is stupidly linear.
It does not support multiple roles originating in the 
same table. Neither does it support multiple 
occurrences of the same table (through self-referential associations).
These restrictions will be removed in a future release, 
but will require a more sophisticated API (tree structure).

=cut

sub ViewFromRoles {
  my ($self, $table, @roles) = @_;
  
  my @innerJoins;
  my @outerJoins;
  my @parentTables = ($table);

  my $viewName = join "", $table, map(ucfirst, @roles);  
  return $viewName if defined (%{$viewName.'::'}); # view was already generated

  my $tName = $table->table;

  my $curTable = $table;
  foreach my $role (@roles) {
    my $joinData = $self->schema->classData->{joins}{$curTable}{$role} or
      croak "ViewFromRoles: role $role not found";
    
    my $which = ($joinData->{arity} =~ m/^(0|\*)/) ? \@outerJoins : \@innerJoins;
    push @$which, $joinData;

    $curTable = $joinData->{table};
    push @parentTables, $curTable;
  }

  my $tables = join(", ", $tName, map {$_->{table}->table} @innerJoins);
  foreach my $oj (@outerJoins) {
    my $on = join " AND ", map {"$_=$oj->{where}{$_}"} keys %{$oj->{where}};
    $tables .= " LEFT OUTER JOIN " . $oj->{table}->table . " ON $on";
  }

  # Here we play tricks with SQL::Abstract : we build a hashref where
  # all info is in the keys, and values are just refs to an empty string.
  # This is because we want ("t1.col=t2.col", []) and not
  # ("t1.col=?", ['t2.col']).
  my %where;
  my $noValue = \"";
  foreach my $ij (@innerJoins) {
    my $k = join " AND ", map {"$_=$ij->{where}{$_}"} keys %{$ij->{where}};
    $where{$k} = $noValue;
  }
  
  $self->View($viewName => '*' => $tables => \%where => @parentTables);
  return $viewName;
}




=head3 Hybrid methods (for Schema or Table classes)

=head4 ColumnType

  MySchema->ColumnType(typeName => handler1 => coderef1,
                                   handler2 => coderef2, ...)
  MyTable ->ColumnType(typeName => qw/column1 column2 .../)

When applied to a schema class, this method declares a
column type of name C<typeName>, to which a number of I<handlers> are
associated (see methods L<ColumnHandlers> and L<applyColumnHandlers>).

When applied to a table class, the handlers associated to 
C<< typeName >> are registered for each of the columns
C<< column1 >>, C<< column2 >> (throug a call to 
L<ColumnHandlers>).

Such column types can be used for example for automatic conversion of values
between database and memory, through 'fromDB' and 'toDB' handlers.

=cut

sub ColumnType {
  my ($self, $typeName, @args) = @_;

  croak "'ColumnType' is a class method" if ref($self);

  if ($self->isSchema) {
    $self->classData->{columnHandlers}{$typeName} = {@args};
  }
  else {
    my $handlers = $self->schema->classData->{columnHandlers}{$typeName} or 
      return;
    foreach my $column (@args) {
      $self->ColumnHandlers($column, %$handlers)
    }
  }
}


=head4 NoUpdateColumns

  MySchema->NoUpdateColumns( @columns );
  MyTable ->NoUpdateColumns( @columns );

Sets an array of column names that will be excluded from 
INSERT/UPDATE statements. This is useful for example when
some column are set up automatically by the database 
(like automatic time stamps or user identification).
It can also be useful if you want to temporarily add information
to memory objects, without passing it back to the database.

NoUpdate columns can be set for a whole Schema, or
for a specific Table class.

=cut

sub NoUpdateColumns {
  my $self = shift; 
  $self->classData->{noUpdateColumns} = \@_;
}


=head4 AutoUpdateColumns

  MySchema->AutoUpdateColumns( columnName1 => sub{...}, ... );
  MyTable ->AutoUpdateColumns( columnName1 => sub{...}, ... );

Declares handler code that will automatically fill column names
C<columnName1>, etc. at each update, either for a single table, or (if
declared at the Schema level), for every table. For example, each
record could remember who did the last modification with something
like

  MySchema->AutoUpdateColumns( last_modif => 
    sub{$ENV{REMOTE_USER} . ", " . localtime}
  );

The handler code will be called as 

  $handler->($record, $table)

so that it can know something about its calling context.  In most
cases, however, the handler will not need these parameters, because it just
returns global information such as current user or current date/time.

=cut

sub AutoUpdateColumns {
  my $self = shift; 
  $self->classData->{autoUpdateColumns} = \@_;
}


=head3 Table methods

=head4 ColumnHandlers

  Table->ColumnHandlers($columnName => handlerName1 => coderef1,
                                       handlerName2 => coderef2, ...)

Associates some handlers to a given column in the current table class.
Then, when you call C<< $obj->applyColumnHandlers('someHandler') >>,
each column having a handler of the corresponding name will execute the
associated code. This can be useful for all sorts of data manipulation :

=over

=item *

converting dates between internal database format and user presentation format

=item *

converting empty strings into null values

=item *

inflating scalar values into objects

=item *

column data validation

=back

Handlers receive the column value as usual through C<< $_[0] >>;
conversion handlers should modify the value in place (beware
not to modify a local copy, which would be a no-op).
Handlers also receive additional info in in the remaing arguments :

  sub myHandler {
    my ($columnValue, $obj, $columnName, $handlerName) = @;
    my $newVal = $obj->computeNewVal($columnValue, ...);
    $columnValue = $newVal; # WRONG : will be a no-op
    $_[0] = $newVal;        # OK    : value is converted
  }

The second argument C<< $obj >> is the object from where 
C<< $columnValue >> was taken ; it may be either a plain Perl hashref,
or an object of a Table or View class (it all depends on the client
application, so the handler cannot make any assumptions).

Handler names 'fromDB' and 'toDB' have a special
meaning : they are called automatically just after reading data from
the database, or just before writing into the database.
Handler name 'validate' is used by the method
L<hasInvalidColumns>.


=cut

sub ColumnHandlers {
  my ($self, $columnName, %handlers) = @_;

  while (my ($handlerName, $coderef) = each %handlers) {
    $self->classData->{columnHandlers}{$columnName}{$handlerName} = $coderef;
  }
}


=head4 AutoExpand

  Table->AutoExpand(qw/role1 role2 .../)

Generates an C<autoExpand> method for the class, that 
will autoexpand on the roles listed (i.e. will call
the appropriate method and store the result
in a local slot within the object). 
In other words, the object knows how to expand itself,
fetching information from associated tables, in order
to build a data tree in memory.

Be careful to avoid loops when specify autoexpands, otherwise
you will generate an infinite tree and break your program.
For example this would be problematic :


  Employee->Autoexpand(qw/activities/);
  Activity->Autoexpand(qw/employee/);


=cut

sub AutoExpand {
  my ($table, @roles) = @_;

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

  _defineMethod($table => autoExpand => $autoExpand);
}


=head2 Runtime methods

=head3 Utility methods common to the whole framework


=head4 isSchema

True if the invocant is a schema class.

=cut


sub isSchema { 
  my ($class) = @_;
  return $class->classData->{classKind} eq 'Schema';
}


=head4 classData

Returns a ref to a hash for storing class-specific data.
Each subclass has its own hashref, so class data is NOT propagated
along the inheritance tree.

=cut


sub classData {
  my $self = shift;
  my $class = ref($self) || $self;
  return $classData{$class};
}


=head4 schema

Returns the name of the schema class for the current object.

=cut

sub schema { shift->classData->{schema}; }


=head4 dbh

  Schema->dbh( [$dbh] );
  Table->dbh;
  $record->dbh;

Returns or sets the handle to a DBI database handle (see L<DBI>). 
This handle is schema-specific.
C<DBIx::DataModel> expects the handle to be opened with
C<< RaiseError => 1 >> 
(see below L<Transactions and error handling>).

=cut

sub dbh {
  my ($self, $dbh) = @_;
  if ($dbh) {
    $self->isSchema or croak "please call " . $self->schema . 
                             "->dbh(..) to set the dbh handle";
    $self->classData->{dbh} = $dbh;
  }
  return $self->schema->classData->{dbh};
}



=head4 debug

  Schema->debug( 1 );            # will warn for each SQL statement
  Schema->debug( $debugObject ); # will call $debugObject->debug($sql)
  Schema->debug( 0 );            # turn off debugging

=cut 

sub debug { 
  my ($self, $debug) = @_;
  $self->isSchema or croak "'debug' is a schema class method";
  $self->classData->{debug} = $debug; # will be used by internal _debug
}


=head4 noUpdateColumns

Returns the array of column names declared as noUpdate, either
in the Schema or in the Table class of the invocant.

=cut

sub noUpdateColumns {
  my $self = shift; 
  my @cols = @{$self->classData->{noUpdateColumns} || []};
  push @cols, @{$self->schema->classData->{noUpdateColumns} || []} 
    unless $self->isSchema;
  return @cols;
}

=head4 autoUpdateColumns

Returns the array of column names and associated handlers
declared as autoUpdate, either in the Schema or in the Table
class of the invocant.

=cut

sub autoUpdateColumns {
  my $self = shift; 
  my @cols = @{$self->classData->{autoUpdateColumns} || []};
  push @cols, @{$self->schema->classData->{autoUpdateColumns} || []} 
    unless $self->isSchema;
  return @cols;
}

=head3 Table class methods

=head4 table

Returns the database table name registered via C<< registerTable(..) >>.

=cut

sub table {
  my $self = shift; 
  $self->classData->{table};
}

=head4 primKey

Returns the list of primary keys registered via C<< registerTable(..) >>.

=cut

sub primKey {
  my $self = shift; 
  @{$self->classData->{primKey}};
}


=head4 blessFromDB

  Table->blessFromDB($record) 

Blesses C<< $record >> into an object of the current class,
and applies the C<fromDB> column handlers.

=cut


sub blessFromDB {
  my ($self, $record) = @_;
  my $class = ref($self) || $self;
  bless $record, $class;
  $record->applyColumnHandlers('fromDB');
  return $record;
}


=head4 select

  MyTable->select(\@columns, \%where, \@order)
  MyView ->select(\@columns, \%where, \@order)

Applies a SQL SELECT to the associated table (or view), and returns a ref to 
the array of resulting records, blessed into objects of the current class.
The API is borrowed from L<SQL::Abstract> :

=over

=item * 

the first argument C<< \@columns >>  is a reference to a list 
of column names. Actually, it can also be a string, such as 
C<< "column1 AS c1, column2 AS c2" >>. If omitted,
C<< \@columns >> takes the default C<< MyTable->columns >>, which
is usually '*'.

=item *

the second argument C<< \%where >> is a reference to a hash of 
criteria that will be translated into SQL clauses ; 
see L<SQL::Abstract::select> for a detailed description of the
structure of that hash. The argument can also be
a plain string like C<< "column1 IN (3, 5, 7, 11) OR column2 IS NOT NULL" >>;
but in that case you must supply something for the
first argument C<< \@columns >>, otherwise C<select> will get confused.

=item *

the third argument C<< \@order >> is a reference to a list 
of columns for sorting.

=back

No verification is done on C<< \@columns >>,
so it is OK if the list does not contain primary or foreign keys --- but then
later attempts to perform joins or updates will obviously fail.

Returns C<< undef >> if an error occurs; in that case the error can be 
retrieved from C<< DBI::err >> or C<< DBI::errstr >>. See also 
L<< DBI::PrintError >> and L<< DBI::RaiseError >> for more options about 
error handling.


=cut

sub select {
  my $sth = &selectSth  # efficiency hack : like selectSth(@_); see perlsub
    or return undef;

  my ($self) = @_;
  my $class = ref $self || $self;

  # fetch data records and bless them into objects
  my $records = $sth->fetchall_arrayref({});
  $class->blessFromDB($_) foreach @$records;

  return $records;
}



=head4 selectSth

  Table->selectSth(\@columns, \%where, \@order)

This exactly like the C<< select() >> method, except that 
it returns an executed DBI statement handle instead of an arrayref
of objects. Returns undef in case of error.

Use this method whenever you want to iterate yourself through the results :

  my $sth = MyTable->selectSth( ... ) or die DBI::errstr;
  while (my $row = $sth->fetchrow_hashref) {
    my $obj = MyTable->blessFromDB($row);
    workWith($obj);
  }

=cut


sub selectSth {
  my ($self, @args) = @_;
  my $class = ref $self || $self;
  my $classData = $class->classData;

  # 1) Do some magic with the argument list.

  #    In addition to the official arguments, we also handle a
  #    4th argument "moreWhere", used internally by role methods for
  #    passing join criteria. In that case we combine them with the 
  #    regular "where" argument.

  # if the first arg is a hashref, we guess that the 'columns' argument
  # was omitted, so we  take the default columns from the class (usually '*')
  unshift @args, $classData->{columns}  if ref($args[0]) eq 'HASH';

  # if the third arg is a hashref, we guess this is the "moreWhere"
  # argument and we insert an empty 'orderBy'
  splice(@args, 2, 0, undef) if ref($args[2]) eq 'HASH';

  # if we are in a View, the "moreWhere" comes from the class data
  $args[3] = $classData->{where} if $classData->{classKind} eq 'View';

  my ($columns, $where, $orderBy, $moreWhere) = @args;

  # combine $where and $moreWhere criteria
  $where ||= {};
  @{$where}{keys %$moreWhere} = values %$moreWhere;

  # 2) build SQL query and get data

  my $sqlA = $self->schema->classData->{sqlAbstr};
  my ($sql, @bind) = $sqlA->select($self->table, $columns, $where, $orderBy);
  $class->_debug($sql);
  my $sth;
  $sth = $self->dbh->prepare($sql) and $sth->execute(@bind) and return $sth;
  return undef; # in case of error
}



=head4 fetch

  Table->fetch(@keyValues) 

Searches the single record whose primary key is C<< @keyValues >>.
Returns undef if none is found or if an error is encountered
(check C<< DBI::err >> to find out which).

=cut 

sub fetch {
  my $self = shift;
  my %primKeys;
  @primKeys{$self->primKey} = @_;
  my $lst = $self->select(\%primKeys) or return undef;
  return $lst->[0];
}


=head4 insert

  Table->insert({col1 => $val1, col2 => $val2, ...}, {...})

Inserts new records into the database, after having applied 
the 'toDB' handlers.  Beware, this operation may modify the 
argument data (manipulating values through 'toDB' handlers, 
or deleting columns declared as 'noUpdate').
See also section L<Transactions and error handling> below.

=cut

sub insert {
  my ($self, @records) = @_;
  my $class = ref($self) || $self;
  my $sqlA = $self->schema->classData->{sqlAbstr};
  my $table = $self->table;

  foreach my $record(@records) {
    bless $record, $class;
    $record->applyColumnHandlers('toDB');

    delete $record->{$_} foreach $class->noUpdateColumns;

    # references to foreign objects should not be passed either (see 'expand')
    foreach (keys %$record) {
      delete $record->{$_} if ref($record->{$_});
    }

    # now unbless $record into just a hashref and perform the insert
    bless $record, 'HASH';
    my ($sql, @bind) = $sqlA->insert($table, $record);
    $class->_debug($sql);
    my $sth = $self->dbh->prepare($sql);
    $sth->execute(@bind);
  }
}



=head4 applyColumnHandlers

  Table->applyColumnHandlers($handlerName, \@objects);
  $record->applyColumnHandlers($handlerName);

This is both a class and an instance method.  It looks for all columns
having a handler named C<< $handlerName >> (see method L<ColumnHandlers>
for how to declare handlers, and for the special handler names
'fromDB', 'toDB' and 'validate'). Found handlers are then
applied, either to the current object, or to the list of objects
supplied in the optional second argument. The results of 
handler calls are collected into a hashref, with an entry for each column name.
The value of each entry depends on how C<< applyColumnHandlers >> was called :
if it was called as an instance method, then the result is something of shape

  {columnName1 => resultValue1, columnName2 => resultValue2, ... }

if it was called as a class method (i.e. if C<< \@objects >> is defined),
then the result is something of shape

  {columnName1 => [resultValue1forObject1, resultValue1forObject2, ...], 
   columnName2 => [resultValue2forObject1, resultValue2forObject2, ...], 
   ... }

If C<columnName> is not present in the target object(s), then the 
corresponding result value is  C<undef>.

=cut

sub applyColumnHandlers {
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

sub _viewApplyColumnHandlers { # specific implementation for Views
  my ($self, $handlerName, $objects) = @_;

  my $class = ref($self) || $self;
  my $targets = $objects || [$self];
  foreach my $table (@{$self->classData->{parentTables}}) {
    $table->applyColumnHandlers($handlerName, $targets);
  }

  $class->DBIx::DataModel::applyColumnHandlers($handlerName, $targets);
};


=head4 update

  MyTable->update({column1 => value1, ...});
  MyTable->update(@primKey, {column1 => value1, ...});
  $record->update;

This is both a class and an instance method.
It updates the database after having applied the 'toDB' handlers.
See also below L<Transactions and error handling>.

When called as a class method, the columns and values to update
are supplied as a hashref. The second syntax with 
C<< @primKey >> is an alternate way to supply the values
for the primary key (it may be more convenient because you don't
need to repeat the name of primary key columns). So if C<emp_id>
is the primary key of table C<Employee>, then the following
are equivalent :

  Employee->update({emp_id => $eid, address => $newAddr, phone => $newPhone});
  Employee->update($eid => {address => $newAddr, phone => $newPhone});

When called as an instance method, the columns and values to update
are taken from the object in memory. After the update, 
I<the memory for that object is destroyed> (to prevent any confusion,
because the 'toDB' handlers might have changed the values).
So to continue working with the same record, you must fetch it again 
from the database.

In either case, you have no control over the 'where' clause of the
SQL update statement, that will be based exclusively on primary key
columns. So if you need to simultaneously update several records
with a SQL request like 

  UPDATE myTable SET col='newVal' WHERE otherCol like 'criteria%'

then you should generate the SQL yourself and pass it directly to
C<< DBI->do($sql) >>.

The C<update> method only updates the columns received
as arguments : it knows nothing about other columns that may sit
in the database table. Therefore if you have two concurrent clients
doing

  (client1)  MyTable->update($id, {c1 => $v1, c2 => $v2});
  (client2)  MyTable->update($id, {c3 => $v3, c4 => $v4, c5 => $v5});

the final state of record C<$id> in the database is consistent.  This
would not be the case in an RDBMS-OO mapping framework that
systematically updates all columns.

=cut

sub update { _modifyData('update', @_); }


=head4 delete

  Table->delete({column1 => value1, ...});
  Table->delete(@primKey);
  $record->delete;

This is both a class and an instance method.
It deletes a record from the database.
See also below L<Transactions and error handling>.

When called as a class method, the primary key of the record 
to delete is supplied either as a hashref, or directly
as a list of values. Note that C<< MyTable->delete(11, 22) >>
does not mean "delete records with keys 11 and 22", but rather
"delete record having primary key (11, 22)"; in other words,
you only delete one record at a time. In order to 
simultaneously delete several records, you must generate 
the SQL yourself and go directly to the C<DBI> level.

When called as an instance method, the primary key is taken
from object columns in memory. After the delete, 
the memory for that object is destroyed.

=cut

sub delete { _modifyData('delete', @_); }


=head3 Methods for records only (instances of Tables)


=head4 hasInvalidColumns

Applies the 'validate' handler to all existent columns.
Returns a ref to the list of invalid columns, or
undef if there are none.

Note that this is validation at the column level, not at the record
level. As a result, your validation handlers can check if an existent
column is empty, but cannot check if a column is missing (because in
that case the handler would not be called).

Your 'validate' handlers, defined through L<ColumnHandlers>,
should return 0 or an empty string whenever the column value is invalid.
Never return C<undef>, because we would no longer be able to
distinguish between an invalid existent column and a missing column.

=cut

sub hasInvalidColumns {
  my ($self) = @_;
  my $results = $self->applyColumnHandlers('validate');
  my @invalid;			# names of invalid columns
  while (my ($k, $v) = each %$results) {
    push @invalid, $k if defined($v) and not $v;
  }
  return @invalid ? \@invalid : undef;
}


=head4 expand

  $record->expand($role [, @args] )

Executes the method C<< $role >> to follow an Association, and 
stores the result in the object itself under C<< $self->{$role} >>.
This is typically used to expand an object into a tree datastructure.
Optional C<< @args >> are passed to C<< $self->$role(@args) >>.

=cut

sub expand {
  my ($self, $role, @args) = @_;
  $self->{$role} = $self->$role(@args);
}


=head4 autoExpand

  $record->autoExpand( [$recurse] )

Asks the object to expand itself with some objects in foreign tables.
By default does nothing, should be redefined in subclasses.
If the optional argument C<$recurse> is true, then 
C<autoExpand> is recursively called on the expanded objects.


=cut

sub autoExpand {}


=head4 automatic column read accessors through AUTOLOAD

Columns have implicit read accessors through AUTOLOAD. 
So instead of C<< $record->{column} >> you can write
C<< $record->column >>. 

I know this is a bit slower than generating all accessors
in advance (through L<Class::Accessor> or something similar),
but the advantage is that you don't need to know all column
names in advance. This is how we support variable column lists
(two instances of the same Table do not necessarily hold
the same set of columns, it all depends on what you chose when
doing the SELECT).


=cut




#------------------------------------------------------------
# Internal utility functions
#------------------------------------------------------------

sub _debug { # internal method to send debug messages
  my ($self, $msg) = @_;
  my $debug = $self->schema->classData->{debug};
  if ($debug) {
    if (ref($debug)) { $debug->debug($msg) }
    else             { warn $msg; }
  }
}


sub _createPackage {
  my ($pckName, $isa) = @_;
  not defined(%{$pckName.'::'}) or croak "package $pckName is already defined";

  no strict 'refs';
  *{$pckName."::ISA"} = $isa;
}


sub _defineMethod {
  my ($pckName, $methName, $codeRef) = @_;
  my $fullName = $pckName.'::'.$methName;
  not defined(&{$fullName}) or croak "method $fullName is already defined";

  no strict 'refs';
  *{$fullName} = $codeRef;
}


sub _modifyData { # called by methods 'update' and 'delete'
  my $toDo = shift;
  my $self = shift;
  my $class = ref($self) || $self;
  my $table = $self->table;
  my $dbh = $self->dbh;
  my @primKey = $self->primKey;

  if (not ref($self)) {		# called as class method
    my $upd = pop @_;		# get list of values passed as last argument
    $self = { %$upd };		# take a copy
    @{$self}{@primKey} = @_ if @_;
    bless $self, $class;
  }
  elsif (@_) {
    croak "too many args for '$toDo' called as instance method";
  }

  $self->applyColumnHandlers('toDB');

  # move values of primary keys into a specific '%where' structure
  my %where;
  foreach my $col ($self->primKey) {
    $where{$col} = delete $self->{$col} or 
      croak "no value for primary column $col in table $table";
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
  my $sqlA = $self->schema->classData->{sqlAbstr};
  bless $self, 'HASH';
  my ($sql, @bind) = ($toDo eq 'update') ? 
                        $sqlA->update($table, $self, \%where) :
			$sqlA->delete($table, \%where);
  $class->_debug($sql);
  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);
}


sub AUTOLOAD {
   my $self = shift;
   our $AUTOLOAD;
   $AUTOLOAD =~ s/^.*:://;
   return if $AUTOLOAD eq 'DESTROY'; 

   ref($self) and exists $self->{$AUTOLOAD} and return $self->{$AUTOLOAD};

   croak "no method $AUTOLOAD";	# otherwise
}



=head1 OTHER CONSIDERATIONS

=head2 Namespaces, classes, methods

C<DBIx::DataModel> automatically generates Perl classes for Schemas,
Tables, Views, Associations. Before doing so, it checks that no Perl
package of the same name already exists.  A similar check is performed
before adding role methods into classes.

The client code can insert additional methods into the generated
classes : just switch to the package and define your code.  However,
because of the security checks just mentioned, C<DBIx::DataModel> must
create the package B<before> you start adding methods to it, and
therefore the declarations should be inside a BEGIN block :

  BEGIN { # make sure these declarations are immediately executed
  
    DBIx::DataModel->Schema('MySchema'); 
    MySchema->Table(Activity   => Activity   => qw/act_id/);
    ...
  }
  
  # now we can safely add new methods
  
  package Activity; 
  
  sub activePeriod {
    my $self = shift;
    $self->{d_end} ? "from $self->{d_begin} to $self->{d_end}"
                   : "since $self->{d_begin}";
  }
  
  package main;			# switch back to the 'main' package

See L<perlmod> for an explanation of BEGIN blocks.


=head2 Interaction with the DBI layer 

=head3 Transactions and error handling

C<DBIx::DataModel> follows the recommendations
of C<DBI> for transactions : it expects the database handle 
to be opened with C<< RaiseError => 1 >> and therefore does not check itself
for C<DBI> errors ; it is up to the client code
to catch the exceptions and deal with errors.

As explained in L<DBI/Transactions>,
C<AutoCommit> should be set off for databases that support transactions;
then atomic operations are enclosed in an C<eval>, followed by either
C<< $dbh->commit() >> (in case of success) or 
C<< $dbh->rollback() >> (in case of failure).


=head3 Calling DBI directly

Consider again the following excerpt from the SYNOPSIS :

  package Departement; 
  
  sub currentEmployees {
    my $self = shift;
    my $currentAct = $self->activities({d_end => [{-is  => undef},
                                                  {">" => $today}]});
    return map {$_->employee} @$currentAct;
  }


This code crosses two tables and generates I<n + 1> calls to the 
database , where I<n> is the number of current activities 
in the department. This can be optimized by performing the join
within the database, instead of doing it in Perl,
which reduces to one single call to the database.
So if we are ready to code directly at the DBI level, we could
write 

  package Departement; 
  
  sub currentEmployees {
    my $self = shift;
    my $sql = "SELECT Employee.* FROM Employee, Activity WHERE ".
              "Activity.emp_id = Employee.emp_id AND ".
              "(d_end is null or d_end <= '$today')";
    my $empl = $self->dbh->selectall_arrayref($sql, {Slice => {}});
    Employee->blessFromDB($_) foreach @$empl;
    return $empl;
  }

Actually, in this example there is an even simpler way to do it:

  package Departement; 
  
  sub currentEmployees {
    my $self = shift;
    
    MySchema->ViewFromRoles(qw/Activity employee/)
            ->select("Employee.*", {d_end => [{-is  => undef},
                                              {">" => $today}]});
  }

=head2 Self-referential associations

Associations can be self-referential, i.e. describing tree
structures :

  MySchema->Association([qw/OrganisationalUnit parent   1 ou_id/],
                        [qw/OrganisationalUnit children * parent_ou_id/],

However, when there are several self-referential associations,
we might get into problems : consider

  MySchema->Association([qw/Person mother   1 pers_id/],
                        [qw/Person children * mother_id/]);
  MySchema->Association([qw/Person father   1 pers_id/],
                        [qw/Person children * father_id/]);

This does not work because there are two definitions  of the "children"
role name in the same class "Person".
One solution is to distinguish these
roles, and then write by hand a general "children" role :

  MySchema->Association([qw/Person mother         1 pers_id/],
                        [qw/Person motherChildren * mother_id/]);
  MySchema->Association([qw/Person father         1 pers_id/],
                        [qw/Person fatherChildren * father_id/]);
  
  package Person;
  sub children {
    my $self = shift;
    my $id = $self->{pers_id};
    my $sql = "SELECT * FROM Person WHERE mother_id = $id OR father_id = $id";
    my $children = $self->dbh->selectall_arrayref($sql, {Slice => {}});
    Person->blessFromDB($_) foreach @$children;
    return $children;
  }

Alternatively, since rolenames C<motherChildren> and C<fatherChildren>
are most probably useless, we might just specify unidirectional
associations : 

  MySchema->Association([qw/Person mother  1 pers_id/],
                        [qw/Person none    * mother_id/]);
  MySchema->Association([qw/Person father  1 pers_id/],
                        [qw/Person none    * father_id/]);

=head1 SEE ALSO


Some alternative modules in this area are  L<Alzabo>, L<Tangram>,
L<SPOPS>, L<Class::PObject>, L<Class::DBI>, L<DBIx::RecordSet>,
L<DBIx::SQLEngine>,L<DBIx::Record>, L<DBIx::Class>, and a lot more 
in the C<DBIx::*> namespace, all with different approaches.
For various reasons, none of these did  fit nicely in my context, 
so I decided to write C<DBIx:DataModel>.
Of course there might be also many reasons why C<DBIx:DataModel>
will not fit in I<your> context, so just do your own shopping.
A good place to start would be the general discussion on RDBMS - Perl 
mappings at L<http://poop.sourceforge.net>. There are also some
pointers in the Perl 5 Enterprise Environment website at 
L<http://www.officevision.com/pub/p5ee/>.


=head1 TO DO 

  - autodeclare tables and associations from $dbh->table_info, etc.
  - 'hasInvalidColumns' : should be called automatically before insert/update ?
  - 'validate' record handler
  - 'normalize' handler : for ex. transform empty string into null
  - walk through WHERE queries and apply 'toDB' handler (not obvious!)
  - add a 'Column' method to tables, so they can declare which columns
    should be retrieved by default
  - add the UML notions of Aggregation and Composition (would mean 
    additional methods for adding and removing parts of an aggregate;
    automatic deletion of composite parts)
  - decide what to do with multiple inheritance of role methods in Views. 
    use NEXT ?
  - table aliases
  - keep track of all tables, views, assoc. in schema->classData ? useful ?
  - insert() method : return last_insert_id(s) from DBI
  - remove restrictions in ViewFromRoles

=head1 AUTHOR

Laurent Dami, E<lt>laurent.dami AT etat  geneve  chE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2005 by Laurent Dami.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

1;

