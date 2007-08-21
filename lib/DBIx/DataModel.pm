#----------------------------------------------------------------------
package DBIx::DataModel;
#----------------------------------------------------------------------
# see POD doc at end of file

use warnings;
use strict;
use DBIx::DataModel::Schema;

our $VERSION = '0.32';


sub Schema {	
  my $class = shift;

  return DBIx::DataModel::Schema->_subclass(@_);
}


1; # End of DBIx::DataModel

__END__

=head1 NAME

DBIx::DataModel - Classes and UML-style Associations on top of DBI

=head1 SYNOPSIS

=head2 in file "MySchema.pm"

Declare the schema

  use DBIx::DataModel;
  DBIx::DataModel->Schema('MySchema'); # MySchema is now a Perl package

Declare the tables with 
C<< (Perl name, DB name, primary key column(s)) >>.
Each table then becomes a Perl package.

  MySchema->Table(qw/Employee   Employee   emp_id/);
  MySchema->Table(qw/Department Department dpt_id/);
  MySchema->Table(qw/Activity   Activity   act_id/);

Declare associations or compositions in UML style
( C<< [table1 role1 multiplicity1 join1], [table2...] >>).

  MySchema->Composition([qw/Employee   employee   1 /],
                        [qw/Activity   activities * /]);
  MySchema->Association([qw/Department department 1 /],
                        [qw/Activity   activities * /]);

Declare a n-to-n association, on top of the linking table

  MySchema->Association([qw/Department departments * activities department/]);
                        [qw/Employee   employees   * activities employee/]);

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

.. and apply these "column types" to some of our columns

  Employee->ColumnType(Date    => qw/d_birth/);
  Activity->ColumnType(Date    => qw/d_begin d_end/);
  Activity->ColumnType(Percent => qw/activity_rate/);

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

=head2 in file "myClient.pl"

  use MySchema;

Search employees whose name starts with 'D'
(select API is taken from L<SQL::Abstract>)

  my $empl_D = Employee->select({lastname => {-like => 'D%'}});

idem, but we just want a subset of the columns, and order by age.

  my $empl_F 
     = Employee->select(-columns => [qw/firstname lastname d_birth/],
                        -where   => {lastname => {-like => 'F%'}},
                        -orderBy => 'd_birth');

Print some info from employees. Because of the
'fromDB' handler associated with column type 'date', column 'd_birth'
has been automatically converted to display format.

  foreach my $emp (@$empl_D) {
    print "$emp->{firstname} $emp->{lastname}, born $emp->{d_birth}\n";
  }

Same thing, but using method calls instead of direct access to the
hashref (must enable AUTOLOAD in the table or the whole schema)

  Employee->Autoload(1); # or MySchema->Autoload(1)
  foreach my $emp (@$empl_D) {
    printf "%s %s, born %s\n", $emp->firstname, $emp->lastname, $emp->d_birth;
  }

Follow the joins through role methods

  foreach my $act (@{$emp->activities}) {
    printf "working for %s from $act->{d_begin} to $act->{d_end}", 
      $act->department->name;
  }

Role methods can take arguments too, like C<select()>

  my $recentAct  = $dpt->activities({d_begin => {'>=' => '2005-01-01'}});
  my @recentEmpl = map {$_->employee([qw/firstname lastname/])} @$recentAct;

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

=head2 Introduction

C<DBIx::DataModel> is a wrapper framework for building Perl
abstractions (classes, objects and datastructures) that interact
with relational database management systems (RDBMS).  
Of course the ubiquitous L<DBI|DBI> module is used as
a basic layer for communicating with databases; on top of that,
C<DBIx::DataModel> provides facilities for generating SQL queries,
joining tables automatically, navigating through the results,
converting values, and building complex datastructures so that other
modules can conveniently exploit the data.

There are many other CPAN modules offering similar features, like
L<Class::DBI|Class::DBI>,
L<DBIx::Class|DBIx::Class>,
L<Alzabo|Alzabo>,
L<Tangram|Tangram>,
L<Rose::DB::Object|Rose::DB::Object>,
just to name a few well-known alternatives.
Module frameworks in this family are called
I<object-relational mappings> (ORMs).
The mere fact that they are so numerous demonstrates that there is
more than one way to do it, and therefore it is quite unlikely that
any ORM would ever cover all possible needs. 


A brief discussion of the design space and of other Perl ORMs
is provided in section  L</"SEE ALSO"> of this
manual; for the moment, we will concentrate on introducing
the main concepts and features of C<DBIx::DataModel>.


=head2 Index to the documentation

Although the basic principles are quite simple, there are many
details to discuss, so the documentation is quite long.
In an attempt to accomodate for different needs of readers,
it has been structured as follows :

=over

=item * 

The L</"DESIGN PRINCIPLES"> section covers the main
distinctive features of C<DBIx::DataModel>; it is mainly
of interest if you are comparing various ORMs.

=item * 

The L</"QUICKSTART"> section summarizes the main
steps to get started with the framework. 

=item *

The L</"METHOD REFERENCE"> section is a complete reference 
to all methods, divided according to usage steps:
creating a schema, populating it with table and associations, 
parameterizing the framework, and finally data retrieval and
manipulation methods.

=item *

The L</"OTHER CONSIDERATIONS"> section discusses
how this framework interacts with its context 
(Perl namespaces, DBI layer, etc.).

=item *

The L</"INTERNALS"> section documents the internal
structure of the framework, for programmers who might
be interested in extending it.

=item *

The L</"SEE ALSO"> section briefly discusses
other ORMs.

=item *

The L</"TO DO"> section lists some features that hopefully
will be implemented in a future release.


=back

DISCLAIMER: although already in production in our organization, 
this code is still in beta, so the API may slightly
change in future versions.


=head1 DESIGN PRINCIPLES

This section covers the main motivating principles for proposing yet
another ORM. Read it if you are currently evaluating whether
C<DBIx::DataModel> is suitable for your context.  Skip it and jump to 
the L</"QUICKSTART"> section if you  want to directly
start using the framework.

=head2 Help lower-level layers, do not hide them

C<DBIx::DataModel> provides abstractions that help client applications
to automate some common tasks; however, access to lower-level 
layers remains open, for cases where detailed operations are needed :

=over

=item * 

The generated classes contain methods that can return polymorphic
results. By default, the return value is an object or a list
of objects corresponding to data rows; however, these methods
can also return a handle to the underlying DBI statement,
or even just the generated SQL code. Hence, the client code
can take control whenever any fine tuning is needed.

=item *

Data rows exploit the dual nature of Perl objects : on one hand they
can be seen as objects, with methods to walk through the data and
access related rows from other tables, but on the other hand they can
also be seen as hashrefs, with usual Perl idioms for extracting keys,
values or slices of data. 
This dual nature is important for passing data to external helper 
modules, such as XML generators, Perl dumps, javascript JSON, 
templates of the Template Toolkit, etc. Such
modules need to walk on the data tree, exploring keys, values and 
subtrees; so they cannot work if
data columns are implemented as object-oriented methods 
(because there is no simple way to ask for all available methods, and
even if you get there, it is not possible to distinguish which of
those methods encapsulate relevant data).

=back


=head2 Let the database do the work

=head3 Use RDBMS tools to create the schema

Besides basic SQL data definition statements, 
RDBMS often come with their own helper tools for creating or modifying
a database schema (interactive editors for tables,
columns, datatypes, etc.). Therefore 
C<DBIx::DataModel> provides no support in this area, 
and assumes that the database schema is pre-existent.

To talk to the database, the framework only needs to know a bare minimum
about the schema, namely the table names, primary keys, and UML associations;
but no details are required about column names or their datatypes.


=head3 Let the RDBMS check data integrity

Most RDBMS have facilities for checking or ensuring integrity rules :
foreign key constraints, restricted ranges for values, cascaded
deletes, etc. C<DBIx::DataModel> can also do some validation 
tasks, by setting up column types with a C<validate> handler;
however, it is better advised to exploit data integrity 
checks within the RDBMS whenever possible.

=head3 Exploit database projections through variable-size objects

Often in ORMs, columns in the table are in 1-to-1 correspondance
with attributes in the class; so any transfer between
database and memory systematically includes all the columns, both 
for selects and for updates. Of course this has the advantage
of simplicity for the programmer. However, it may be very inefficient 
if the client program only wants to read two columns from 
a very_big_table.

Furthermore, unexpected concurrency problems may occur : in a scenario such as

  client1                            client2                       
  =======			     =======                      
  my $obj = MyTable->fetch($key);    my $obj = MyTable->fetch($key);
  $obj->set(column1 => $val1);	     $obj->set(column2 => $val2); 
  $obj->update;                	     $obj->update;                

the final state of the row should theoretically 
be consistent for any concurrent execution of C<client1> and C<client2>.
However, if the ORM layer blindly updates I<all> columns, instead of just
the changed columns, then the final value of C<column1> or 
C<column2> is unpredictable.

To diminish the efficiency problem, some ORMs offer the possibility
to partition columns into several I<column groups>. The ORM layer
then transparently fetches the appropriate groups in several steps,
depending on which columns are requested from the client. However,
this might be another source of inefficiency, if the client
frequently needs one column from the first group and one from the
second group.


With C<DBIx::DataModel>, the client code has very precise control over
which columns to transfer, because these can be specified separately at
each method call. Whenever efficiency is not an issue, one
can be lazy and specify nothing, in which case the SELECT columns will
default to "*". Actually, the schema 
I<does not know about column names>, except for primary and
foreign keys, and therefore would be unable to transparently
decide which columns to retrieve. Consequently, objects from a 
given class may be of I<variable size> :

  my $objs_A = MyTable->select(-columns => [qw/c1 c2/], 
		 	       -where   => {name => {-like => "A%"}};
  
  my $objs_B = MyTable->select(-columns => [qw/c3 c4 c5/], 
			       -where   => {name => {-like => "B%"}};
  
  my $objs_C = MyTable->select(# nothing specified : defaults to '*'
                               -where   => {name => {-like => "C%"}};

Therefore the programmer has much more freedom and control, but of
course also more responsability : in this example, attempts to access
column C<c1> in members of C<@$objs_B> would yield an error.


=head3 Exploit database products (joins) through multiple inheritance

ORMs often have difficulties to exploit database joins, because
joins contain columns from several tables at once.
If tables are mapped to classes, and rows are mapped
to objects of those classes, then what should be the 
class of a joined row ? Three approaches can be taken

=over

=item *

ignore database joins altogether : all joins are performed
within the ORM, on the client side. This is of course the
simplest way, but also the less efficient, because many 
database queries are needed in order to gather all the data.

=item * 

ask a join from the database, then perform some reverse
engineering to split each resulting row into several objects
(partitioning the columns). 


=item * 

create on the fly a new subclass that inherits from all joined tables :
data rows then simply become objects of that new subclass.
This is the approach taken by C<DBIx::DataModel>.

=back


=head2 High-level declarative statements


=head3 Relationships expressed as UML associations 

Relationships are expressed in a syntax
designed to closely reflect how they would be pictured
in a Unified Modelling Language (UML) diagram. The general
form is :

  MySchema->Association([$class1, $role1, $multiplicity1, @columns1], 
                        [$class2, $role2, $multiplicity2, @columns2]);

yielding for example the following declaration

  MySchema->Association([qw/Department department 1 /],
                        [qw/Activity   activities * /]);


which corresponds to UML diagram

  +------------+                         +------------+
  |            | 1                  0..* |            |
  | Department +-------------------------+ Activities |
  |            | department   activities |            |
  +------------+                         +------------+


This states that there is an association between classes C<Department>
and C<Activity>, with the corresponding role names (roles are used
to navigate through the association in both directions), and with the 
corresponding multiplicities (here an activity corresponds to exactly 
one employee, while an employee may have many activities). 

In the UML specification, role names and multiplicities are 
optional (as a matter of fact, many UML diagrams use 
association names, or even anonymous associations, 
instead of role names). Here, both role names and multiplicities 
are mandatory, because they are needed for code generation.

The association declaration is bidirectional, so it will
simultaneously add features in both participating classes.

In order to generate the appropriate SQL join statements, the
framework needs to know the join column names on both sides; these
can be either given explicitly in the declaration, or they are guessed
from the primary key of the table with multiplicity 1.

Role names declared in the association are used for a number of
purposes : implementing methods for direct navigation, implementing
methods for inserting new members into owner objects, and implementing
multi-step navigation paths through several assocations, such as in :

   $myDepartment->selectFromRoles(qw/activities employee spouse/)
                ->(-columns => \@someColumns,
		   -where   => \%someCriteria);

Information known by the schema about the associations will be used to
automatically generate the appropriate database joins. The kinds of
joins (INNER JOIN, LEFT OUTER JOIN) are inferred from the multiplicities
declared in the association. These can also be explicitly overridden
by writing 

   ...->selectFromRoles(qw/activities <=> employee <=> spouse/) # inner joins

   ...->selectFromRoles(qw/activities  => employee  => spouse/) # left joins


If referential integrity rules are declared within the RDBMS, then
there is some overlap with what is declared here on the Perl
side. However, it would not be possible to automatically deduce all
association information from database metadata, because the database
does not know about role names and multiplicities. Therefore
C<DBIx::DataModel> has no "loader" facility to automatically
generate a schema.


=head3 UML compositions for handling data trees

Compositions are specific kinds of associations, pictured in UML
with a black diamond on the side of the I<composite> class; 
in C<DBIx::DataModel>, those are expressed by calling the
schemas's  L</"Composition"> method instead of L</"Association">.
As a result, the composite class will be able to perform
cascaded insertions and deletions on data trees (for example 
from structured data received through an external XML or JSON file, and
inserted into the database in a single method call).

The reverse is also true : the composite class is able 
to automatically call its own methods to gather data from associated
classes and build a complete data tree in memory. This is declared through
the L</"AutoExpand"> method and is useful for passing structured data
to external modules, like for example XML or JSON exports.


=head3 ColumnTypes

A C<DBIx::DataModel> schema can declare some I<column types> : these
are collections of I<handlers> (callback functions) for 
performing tasks such as data validation or transformation. 
Handlers are then attached to specific columns belonging to that column 
type.

The handler concept is generic and can be exploited by client programs
according to the application domain. However, some handler names
have a special meaning within the framework : 
for example, handlers named C<fromDB> or C<toDB> are automatically 
called when transfering  data from or to the database. 
Take for example the "Percent" column type shown in the  Synopsis :

  # 'percent' conversion between database (0.8) and user (80)
  MySchema->ColumnType(Percent => 
     fromDB   => sub {$_[0] *= 100 if $_[0]},
     toDB     => sub {$_[0] /= 100 if $_[0]},
     validate => sub {$_[0] =~ /1?\d?\d/});

Note that this notion of "type" is independent from the actual
datatypes defined within the database (integer, varchar, etc.).
From the Perl side, these are all seen as scalar values. So 
a column type as defined here is just a way to specify some
operations, programmed in Perl, that can be performed on the
scalar values.


=head3 Autoload on demand

The default mechanism to access columns within a row is 
the hashref API:

  do_something_with($my_row->{column_name});

However, a method call API can be turned on, which would
then yield:

  do_something_with($my_row->column_name());

=head3 Views within the ORM

A schema can contain C<View> declarations, which are
abstractions of SQL statements. This is exactly the
same idea as database views, except that they are implemented
within the ORM, not within the database. Such views
can join several tables, or can specify WHERE
clauses to filter the data. ORM views are useful to 
implement application-specific or short-lived requests, 
that would not be worth registering persistently within
the database model. They can also be useful if you have
no administration rights in the database.
Of course it is also possible to access database views, 
because the ORM sees them as ordinary tables.


=head2 Extended SQL::Abstract API

Every method involving a SELECT in the database (either when 
searching rows from a table or collection of tables, or when
following associations from an existing row) accepts an number
of optional parameters that closely correspond to SQL clauses.
The programming interface reuses what is defined in the excellent 
L<SQL::Abstract|SQL::Abstract> module, with some extensions.
Therefore it is possible for example to specify

=over

=item *

which columns to retrieve

=item *

which restriction criteria to apply (WHERE clause)

=item *

how to order the results

=item *

whether or not to retrieve distinct rows

=item * 

etc.

=back

All these parameters are specified at the I<statement level>, and
therefore may vary between subsequent calls to the same class.
This is in contrast with many other ORMs where the set of columns
or the ordering criteria are specified at schema definition time. 
As already stated above, C<DBIx::DataModel> gives more 
freedom to client programs, but also more responsability.


=head2 Minimize dependencies for easy installation

C<DBIx::DataModel> only depends on L<DBI|DBI> and 
L<SQL::Abstract|SQL::Abstract>, so
it should be very easy to install even without help of tools
like C<ppm>, C<cpan> or C<cpanp>.



=head1 QUICKSTART

This section will show the main steps to get started
with C<DBIx::DataModel>. The goal here is conciseness, not
completeness; a full reference will be given in the next sections.
The tutorial is a gentle expansion of the examples given 
in the SYNOPSIS, namely a small human resources management
system.

=head2 Basic assumptions

Before starting with C<DBIx::DataModel>, you should have 
installed CPAN modules L<DBI|DBI> and L<SQL::Abstract|SQL::Abstract>.
You also need a database management system with a L<DBD|DBD> driver. 

Use your database modeling tool to create some tables for employees,
departments, activities (an employee working in a department from
a start date to an end date), and employee skills. If you have
no modeling tool, you can also feed something like the following
SQL code to the database

  CREATE TABLE t_employee (
    emp_id     INTEGER AUTO_INCREMENT PRIMARY KEY,
    lastname   TEXT    NOT NULL,
    firstname  TEXT,
    d_birth    DATE 
  ); 
  CREATE TABLE t_department (
    dpt_code   VARCHAR(5) PRIMARY KEY,
    dpt_name   TEXT    NOT NULL 
  );
  CREATE TABLE t_activity (
    act_id     INTEGER AUTO_INCREMENT PRIMARY KEY,
    emp_id     INTEGER NOT NULL REFERENCES t_employee(emp_id),
    dpt_code   VARCHAR(5) NOT NULL REFERENCES t_department(dpt_code),
    d_begin    DATE    NOT NULL,
    d_end      DATE
  );
  CREATE TABLE t_skill (
    skill_code VARCHAR(2) PRIMARY KEY,
    skill_name TEXT    NOT NULL 
  );
  CREATE TABLE t_employee_skill (
    emp_id         INTEGER NOT NULL REFERENCES t_employee(emp_id),
    skill_code     VARCHAR(2)  NOT NULL REFERENCES t_skill(skill_code),
    CONSTRAINT PRIMARY KEY (emp_id, skill_code)
  );

As can be seen from this SQL, we assume that the primary keys 
for C<t_employee> and C<t_activity> are generated
automatically by the RDBMS. Primary keys for other tables
are character codes and therefore should be supplied by
the client program. We decided to use the suffixes
C<_id> for auto-generated keys, and C<_code> for user-supplied
codes.

=head2 Declare schema and tables

C<DBIx::DataModel> needs to acquire some knowledge about 
the datamodel. So we first declare a I<schema> :

  use DBIx::DataModel;
  DBIx::DataModel->Schema('HR');

Here we have chosen a simple acronym C<HR> as the schema name, but it 
could as well have been something like C<Human::Resources>.

The schema now is a Perl class, so we invoke its C<Table>
method to declare the first table within the schema :

  HR->Table(qw/HR::Employee   	 t_employee   	   emp_id/);

This creates a new Perl class named C<HR::Employee>. It could as well
have been simply named C<Employee>, or any other legal Perl package
name; here the use of the schema name as a prefix is just a design
choice, not an obligation. The second argument C<t_employee> is the
database table, and the third argument C<emp_id> is the primary key.
So far nothing is declared about other columns in the table.

Other tables are declared in a similar fashion :

  HR->Table(qw/HR::Department 	 t_department 	   dpt_code/);
  HR->Table(qw/HR::Activity   	 t_activity   	   act_id/);
  HR->Table(qw/HR::Skill      	 t_skill      	   skill_code/);
  HR->Table(qw/HR::EmployeeSkill t_employee_skill  emp_id  skill_code/);

This last declaration has 4 arguments because the primary key
ranges over 2 columns.

=head2 Declare column types

RDBMS will usually require that dates be in ISO format of shape
C<yyyy-mm-dd>. Let's assume our users are European and want
to see and enter dates of shape C<dd.mm.yyyy>. Insert of converting
back and forth within the client code, it's easier to do it at the ORM
level. So we define conversion routines within a "Date" column type

  HR->ColumnType(Date => 
     fromDB => sub {$_[0] =~ s/(\d\d\d\d)-(\d\d)-(\d\d)/$3.$2.$1/   if $_[0]},
     toDB   => sub {$_[0] =~ s/(\d\d)\.(\d\d)\.(\d\d\d\d)/$3-$2-$1/ if $_[0]},
     validate => sub {$_[0] =~ m/\d\d\.\d\d\.\d\d\d\d/});

and then apply this type to the appropriate columns

  HR::Employee->ColumnType(Date => qw/d_birth/);
  HR::Activity->ColumnType(Date => qw/d_begin d_end/);

Here we just perform scalar conversions; another design choice 
could be to "inflate" the data to some kind of Perl objects.

Observe that C<ColumnType> is overloaded : when invoked on a schema, it
I<defines> a column type; when invoked on a class, it
I<applies> the column type to some columns.

=head2 Declare associations

=head3 Basic associations

Now we will declare a binary association between departements
and activities:

  HR->Association([qw/HR::Department department  1 /],
                  [qw/HR::Activity   activities  * /]);

The C<Association> method takes two references to lists of arguments;
in each of them, we find : class name, role name, multiplicity, and
optionally the names of columns participating in the join. Here
column names are not specified, so the method assumes that the join
is on C<dpt_code> (from the primary key of the class
with multiplicity 1 in the association). Since associations
are symmetric, you could as well supply the two lists in the
reverse order.  

The declaration should be read crosswise, like when reading a UML
class diagram : here we are stating that a department may be associated
with several activities; therefore the C<HR::Department> class will
contain an C<activities> method which returns an arrayref. Conversely,
an activity is associated with exactly one department, so the
C<HR::Activity> class will contain a C<department> method which returns a
single instance of C<HR::Department>.


=head3 Compositions

The second association could be defined in a similar way; but here
we will introduce the new concept of I<composition>. 

  HR->Composition([qw/HR::Employee   employee    1 /],
                  [qw/HR::Activity   activities  * /]);

This looks exactly like an association declaration; but it states
that an activity somehow "belongs" to an employee (cannot exist
without being attached to an employee, and is often created and 
deleted together with the employee). In a UML class diagram, this
would be pictured with a black diamond on the Employee side.
Using a composition instead of an association in this particular
example would perhaps be debated by some data modelers; but at least
it allows us to illustrate the concept.

A composition declaration behaves in all respects like an association.
The main difference is in C<insert> and C<delete> methods, which will
be able to perform more complex operations on data trees : for example 
it will be possible in one method call to insert an employee together
with its activities. Compositions also support auto-expansion 
of data trees through the L<AutoExpand|/"AutoExpand"> method.


=head3 Many-to-many associations

Now comes the association between employees and skills, which
is a many-to-many association. This happens in two steps: first
we declare as usual the associations with the linking table :

  HR->Association([qw/HR::Employee      employee   1 /],
                  [qw/HR::EmployeeSkill emp_skills * /]);

  HR->Association([qw/HR::Skill         skill      1 /],
                  [qw/HR::EmployeeSkill emp_skills * /]);

Then we declare the many-to-many association:

  HR->Association([qw/HR::Employee  employees  *  emp_skills employee/],
                  [qw/HR::Skill     skills     *  emp_skills skill   /]);

This looks almost exactly like the previous declarations, except that
the last arguments are no longer column names, but rather I<role names>:
these are the sequences of roles to follow in order to implement the 
association. This example is just an appetizer; more explanations are 
provided in the reference section.

=head2 Use the schema

To use the schema, we first need to supply it with a database
connection :

  my $dbh = DBI->connect(...); # parameters according to your RDBMS
  HR->dbh($dbh);               # give $dbh handle to the schema

Now we can start populating the database:

  my ($bach_id, $berlioz_id, $monteverdi_id) = 
    HR::Employee->insert({firstname => "Johann",  lastname => "Bach"      },
                         {firstname => "Hector",  lastname => "Berlioz"   },
                         {firstname => "Claudio", lastname => "Monteverdi"});

Observe that several rows can be created at once (of course you get the
same result by calling C<insert()> several times). According to our
earlier assumptions, keys are generated automatically within the 
database, so they need not be supplied here. The return value of the 
method is the list of generated ids (provided that your database driver
supports DBI's L<last_insert_id|DBI/last_insert_id> method).

Similarly, we create some departments and skills (here with 
explicit primary keys) :

  HR::Department->insert({dpt_code => "CPT",  dpt_name => "Counterpoint" },
			 {dpt_code => "ORCH", dpt_name => "Orchestration"});

  HR::Skills->insert({skill_code => "VL",  skill_name => "Violin"  },
                     {skill_code => "KB",  skill_name => "Keyboard"},
                     {skill_code => "GT",  skill_name => "Guitar"},

To perform updates, there is either a class method or an object method.
Here is an example with the class method :

  HR::Employee->update($bach_id => {firstname => "Johann Sebastian"});

Associations have their own insert methods, named C<insert_into_*> :

  my $bach = HR::Employee->fetch($bach_id); # get single record from prim.key
  
  $bach->insert_into_activities({d_begin => '01.01.1695',
			         d_end   => '18.07.1750',
			         dpt_code => 'CPT'});
  
  $bach->insert_into_emp_skills({skill_code => 'VL'},
			        {skill_code => 'KB'});

Compositions implement cascaded inserts from a given data tree :

  HR::Employee->insert({firstname  => "Richard",  
                        lastname   => "Strauss",
                        activities => [ {d_begin  => '01.01.1874',
                                         d_end    => '08.09.1949',
                                         dpt_code => 'ORCH'      } ]});


The C<select()> method retrieves several records from a class :

  my $all_employees = HR::Employee->select; 
  foreach my $emp (@$all_employees) {
    do_something_with($emp);
  }

or maybe we want something more specific :

  my @columns  = qw/firstname lastname/;
  my %criteria = (lastname => {-like => 'B%'});
  my $some_employees 
     = HR::Employee->select(-columns => \@columns,
                            -where   => \%criteria,
                            -orderBy => 'd_birth');

From a given object, role methods allow us to get associated
objects :

  foreach my $emp (@$all_employees) {
    print "$emp->{firstname} $emp->{lastname} ";
    my @skill_names = map {$_->{skill_name}  }} @{$emp->skills};
    print " has skills ", join(", ", @skill_names) if @skill_names;
  }

Passing arguments to role methods, we can restrict to 
specific columns or specific rows, exactly like the 
C<select()> method :

  my @columns = qw/d_begin d_end/;
  my %criteria = (d_end => undef);
  my $current_activities = $someEmp->activities(-columns => \@columns,
                                                -where   => \%criteria);

And it is possible to join on several roles at once:

  my $result = $someEmp->selectFromRoles(qw/activities department/)
                       ->(-columns => \@columns,
                          -where   => \%criteria);

This concludes our short tutorial. More examples are given
in the reference section below.


=head1 METHODS REFERENCE

=head2 General convention

Method names starting with an uppercase letter
are meant to be compile-time class methods.  These methods will
typically be called when loading a module like 'MySchema.pm', and
therefore will be executed during the BEGIN phase of the Perl
compiler.  They instruct the compiler to create classes, methods and
datastructures for representing the elements of a database schema.

Method names starting with a lowercase letter are meant to be usual
run-time methods, either for classes or for instances.


=head2 Creating a schema

=head3 Schema

  DBIx::DataModel->Schema($schemaName, %options)

Creates a new Perl class of name C<$schemaName> that represents a 
database schema. That class inherits from 
C<DBIx::DataModel::Schema>.
Possible options are :

=over

=item C<< dbh => $dbh >>

Connects the schema to a DBI database handle.
This can also be set or reset later via the 
L</dbh> method.

=item C<< sqlDialect => $dialect >>

SQL has no standard syntax for performing joins, so if your
database wants a particular syntax you will need to declare it.
Current builtin dialects are either C<'MsAccess'>, C<'BasisODBC'>,
C<'BasisJDBC'> or C<'Default'> (contributions to enrich this list 
are welcome). Otherwise C<$dialect> can also be a hashref in which you
supply the following information :

=over

=item innerJoin

a string in L<sprintf|perlfunc/"sprintf"> format, with placeholders
for the left table, the right table and the join criteria.
Default is C<%s INNER JOIN %s ON %s>.
If your database does not support inner joins, set this to C<undef>
and the generated SQL will be in the form C<T1, T2, ... Tn WHERE ... AND ... >.

=item leftJoin

a string for left outer joins.
Default is C<%s LEFT OUTER JOIN %s ON %s>.

=item joinAssociativity

either C<left> or C<right>

=item columnAlias

a string for generating column aliases. 
Default is C<%s AS %s>.

=back

=back

For backwards compatibility with the previous API, you can specify the dbh 
as second argument, instead of a named option, i.e. 
C<< Schema($schemaName, $dbh) >> instead of 
C<< Schema($schemaName, dbh => $dbh) >>.


=head2 Populating a schema

=head3 Table

  MySchema->Table($pckName, $dbTable, @primKey);

Creates a new Perl class of name C<$pckName> that represents a 
database table. That class inherits from 
C<DBIx::DataModel::Table>.
C<< $dbTable >> should contain the name of the table in the database.
C<< @primKey >> should contain the name of the column
(or names of columns) holding the primary
key for that table. This info will be used for interpreting arguments
to the L</"fetch"> method, and for filling WHERE clauses in the SQL 
generated by the L</"update"> method.



=head3 View

  MySchema->View($viewName, $columns, $dbTables, \%where, @parentTables);

Creates a new Perl class of name C<$viewName> that represents a
SQL SELECT request of shape 

  SELECT $columns FROM $dbTables [ WHERE %where ]

Therefore arguments C<$columns> and C<$dbTables> should be strings;
the optional C<\%where> argument should be a hashref, as explained below.

C<View()> is seldom called explicitly from client code; it is mainly 
useful internally for implementing other methods like
L</ViewFromRoles> or L</selectFromRoles>. However, it could also 
be used to build queries with specific SQL clauses like for example

  MySchema->View(MyView =>
     "DISTINCT column1 AS c1, t2.column2 AS c2",
     "Table1 AS t1 LEFT OUTER JOIN Table2 AS t2 ON t1.fk=t2.pk",
     {c1 => 'foo', c2 => {-like => 'bar%'}},
     qw/Table1 Table2/);

The class generated by C<View()> has a  L<select()|/"select"> 
method, which will 

=over

=item *

select records from the database according to the criteria of the view, 
merged with the criteria of the request;

=item *

apply the 'fromDB' handlers of the parent tables to those records;

=item *

bless the results into objects of C<$viewName>.

=back

See L<SQL::Abstract> and the L<select()|/"select"> method for a
complete description of what to put in the C<\%where> argument. For the
moment, just consider the following example:

  my $lst = MyView->select({c3 => 22});

This would generate the SQL statement:

  SELECT DISTINCT column1 AS c1, t2.column2 AS c2
  FROM  Table1 AS t1 
        LEFT OUTER JOIN Table2 AS t2 ON t1.fk=t2.pk
  WHERE (c1 = 'foo' AND c2 LIKE 'bar%' AND c3 = 22)

The C<\%where> argument can of course be C<undef>.

The optional list of C<< @parentTables >> contains names of Perl 
table classes from which the view will also inherit.
If the SQL code in C<$dbTables> is a join between
several tables, then it is a good idea to mention these 
tables in C<< @parentTables >>, so that their
role methods become available to instances
of C<MyView>. Be careful about table names : 
the SQL code in C<$dbTables> should contain database table names,
whereas the members of C<< @parentTables >> should be 
Perl table classes (might be the same, but not necessarily).


Perl views as defined here have nothing to do with views declared in
the database itself. Perl views are totally unknown to the database,
they are just abstractions of SQL statements.  If you need to access
I<database views>, just use the C<Table> declaration, like for a regular
table.



=head3 Association

  MySchema->Association([$class1, $role1, $multiplicity1, @columns1], 
                        [$class2, $role2, $multiplicity2, @columns2]);

Declares an association between two tables (or even two instances of
the same table), in a UML-like fashion. Each side of the association
specifies its table, the "rolename" of of this table in the
association, the multiplicity, and the name of the column or list of
columns that technically implement the association as a database
join. 

Role names should be chosen so as to avoid
conflicts with column names in the same table.

Multiplicities should be written in the UML form '0..*', '1..*',
'0..1', etc. (minimum .. maximum number of occurrences); this will
influence how role methods and views are implemented, as explained
below. The '*' for "infinite" may also be written 'n',
i.e. '1..n'. Multiplicity '*' is a shortcut for '0..*', and
multiplicity '1' is a shortcut for '1..1'. Other numbers may be given
as multiplicity bounds, but this will be just documentary :
technically, all that matters is

=over

=item *

whether the lower bound is 0 or more (if 0, generated
joins will be left joins, otherwise inner joins)

=item *

whether the upper bound is 1 or more (if 1, the associated
method returns a single object, otherwise it returns an arrayref)

=back

If C<@columns1> or C<@columns2> are omitted, they are guessed 
as follows : for the table with multiplicity C<1> or C<0..1>,
the default is the primary key; for the other table, the default
is to take the same column names as the other side of the association.


=head4 Roles as additional methods in table classes

As a result of the association declaration, the Perl class
C<< $table1 >> will get an additional method named
C<< $role2 >> for accessing the associated object(s) in C<< $table2 >>; 
that method normally returns an arrayref, unless C<< $multiplicity2 >>
has maximum '1' (in that case the return value is a single object
ref).  Of course, C<< $table2 >> conversely gets a method named 
C<< $role1 >>. 

To understand why tables and roles are crossed, look at the UML picture :

  +--------+                     +--------+
  |        | *              0..1 |        |
  | Table1 +---------------------+ Table2 |
  |        | role1         role2 |        |
  +--------+                     +--------+

so from an object of C<Table1>, you need a method C<role2> to access
the associated object of C<Table2>. In your diagrams, be careful to
get the role names correctly according to the UML
specification. Sometimes we see diagrams where role names are on the
wrong side, mainly because modelers have a background in
Entity-Relationship or Merise methods, where it is the other way
around.


Role methods perform joins within Perl (as opposed to joins
directly performed within the database). That is, given a declaration

  MySchema->Association([qw/Employee   employee   1   /],
                        [qw/Activity   activities 0..*/]);

we can call

  my activities = $anEmployee->activities

which will implicitly perform a 

  SELECT * FROM Activity WHERE emp_id = $anEmployee->{emp_id}

The role method can also accept additional parameters
in L<SQL::Abstract> format, exactly like the 
L<select()|/"select"> method. So for example

  my $activities = $anEmployee->activities(-columns => [qw/act_name salary/],
                                           -where   => {is_active => 'Y'});

would perform the following SQL request :

  SELECT act_name, salary FROM Activity WHERE 
    emp_id = $anEmployee->{emp_id} AND
    is_active = 'Y'

If the role method is called without any parameters, and
if that role was previously expanded (see L</"expand"> method), 
i.e. if the object hash contains an entry C<< $obj->{$role} >>, 
then this data is reused instead of calling the database again.

To specify a unidirectional association, just supply 
0 or an empty string (or even the string C<"0"> or C<'""'> or C<"none">)
to one of the role names. In that case the corresponding role
method is not generated.

=head4 Methods C<insert_into_...>

When a role has multiplicity '*', another method
named C<insert_into_...> is also installed, that will
create new objects of the associated class, taking care
of the linking automatically :

  $anEmployee->insert_into_activities({d_begin => $today, 
                                       dpt_id  => $dpt});

This is equivalent to

  Activity->insert({d_begin => $today, 
                    dpt_id  => $dpt, 
                    emp_id  => $anEmployee->{emp_id}});

=head4 Many-to-many associations

UML conceptual models may contain associations where
both roles have multiplicity '*' (so-called 
B<many-to-many> associations). However, when it comes to 
actual database implementation, such associations
need an intermediate linking table to collect 
couples of identifiers from both tables. 

C<DBIx::DataModel> supports many-to-many associations
as a kind of syntactic sugar, translated into 
low-level associations with the linking table. 
The linking table needs to be declared first :

  MySchema->Table(qw/link_table link_table prim_key1 prim_key2/);

  MySchema->Association([qw/table1     role1  0..1/],
                        [qw/link_table links    * /]);

  MySchema->Association([qw/table2     role2  0..1/],
                        [qw/link_table links    * /]);

This describes a diagram like this :

  +--------+               +-------+                 +--------+
  |        | 0..1        * | Link  | *          0..1 |        |
  | Table1 +---------------+  --   +-----------------+ Table2 |
  |        | role1  linksA | Table | linksB    role2 |        |
  +--------+               +-------+                 +--------+

Then we can declare the  many-to-many association, very much like
ordinary associations, except that the last items in the argument
lists are names of roles to follow, instead of names of columns to join.
In the diagram above, we must follow roles C<linksA> and C<role2>
in order to obtain the rows of C<Table2> related to an instance
of C<Table1>; so we write

  MySchema->Association([qw/table1  roles1  *  linksB role1/],
                        [qw/table2  roles2  *  linksA role2/]);

which describes a diagram like this :

              +--------+                    +--------+
              |        | *                * |        |
              | Table1 +--------------------+ Table2 |
              |        | roles1      roles2 |        |
              +--------+                    +--------+

The declaration has created a new method C<roles2> in 
C<Table1>; that method is implemented by following roles
C<linksA> and C<role2>. So for an object C<obj1> of C<Table1>,
the call

  my $obj2_arrayref = $obj1->roles2();

will generate the following SQL :

  SELECT * FROM link_table INNER JOIN table2
            ON link_table.prim_key2=table2.prim_key2
    WHERE link_table.prim_key1 = $obj->{prim_key1}


Observe that C<roles2()> returns rows from a I<join>, 
so these rows will belong both to C<Table2> I<and> to 
C<Link_Table>.

Many-to-many associations do not have an
automatic C<insert_into_*> method : you must 
explicitly insert into the link table.



=head4 Following multiple associations

In the previous section we were following two roles at once
in order to implement a many-to-many association. More generally,
it may be useful to follow several roles at once, joining
the tables in a single SQL query. This can be done through the
following methods :

=over

=item *

L</"ViewFromRoles"> : create a new C<View> that selects 
from several tables, filling the joins automatically

=item *

L</"selectFromRoles"> :
from a given object, follow a list of roles to get information
from associated tables.

=item *

L</"MethodFromRoles"> :
add a new method in a table, that will follow a list of roles 
(shortcut for repeated calls to C<selectFromRoles>).


=back



=head3 Composition

  MySchema->Composition([$class1, $role1, $multiplicity1, @columns1], 
                        [$class2, $role2, $multiplicity2, @columns2]);

Declares a composition between two tables, i.e an association with
some additional semantics. In UML class diagrams, compositions are
pictured with a black diamond on one side : this side will be called
the I<composite> class, while the other side will be called the
I<component> class. In C<DBIx::DataModel>, the diamond (the composite
class) corresponds to the first arrayref argument, and the component
class corresponds to the second arrayref argument, so the order of
both arguments is important (while for associations the order makes no
difference).

The UML intended meaning of a composition is that objects of the
component classes cannot exist outside of their composite class. Within
C<DBIx::DataModel>, the additional semantics for compositions is to
support cascaded insertions and deletions and auto-expansion :

=over

=item *

the argument to an C<insert> may contain references to subrecords.
The main record will be inserted in the composite class, and within
the same operation, subrecords will be inserted into the 
component classes, with foreign keys automatically filled with
appropriate values.


=item *

the argument to a C<delete> may contain lists of component records to
be deleted together with the main record of the composite class.

=item *

roles declared through a Composition may then be supplied
to L<AutoExpand|/"AutoExpand"> so that the composite class
can automatically fetch its component parts.


=back

See the documentation of L</"insert">, L</"delete"> and 
L</"AutoExpand"> methods below for more details.

Note that compositions add nothing to the semantics of update operations.

Even though the arguments to a C<Composition> look exactly like for
C<Association>, there are some more constraints : the maximum
C<$multiplicity1> must be  1 (which is coherent with the notion of composition),
and the maximum C<$multiplicity2> must be greater than 1 (because
one-to-one compositions are not common and we don't know
exactly how to implement cascaded inserts or deletes in such a case).
Furthermore, a class cannot be component of several composite classes,
unless the corresponding multiplicities are all C<0..1> instead of the
usual C<1>.


=head3 ViewFromRoles

  my $view = MySchema->ViewFromRoles($table, $role1, $role2, ..);

Creates a C<View> class, starting from a given table class and
following one or several associations through their role names.
It calls the L</"View"> method, with a collection of parameters
automatically inferred from the associations. So for example

  MySchema->ViewFromRoles(qw/Department activities employee/);

is equivalent to 

  my $sql = <<_EOSQL_
  Department 
    LEFT OUTER JOIN Activity ON Department.dpt_id = Activity.dpt_id
    LEFT OUTER JOIN Employee ON Activity.emp_id   = Employee.emp_id
  _EOSQL_
  
  MySchema->View(DepartmentActivitiesEmployee => '*', $sql, 
                 qw/Department Activity Employee/);

For each pair of tables, the kind of join is chosen according to
the multiplicity declared with the role : if the minimum multiplicity is 0, 
the join will be LEFT OUTER JOIN; otherwise it will be a usual inner join
(exception : after a first left join, all remaining tables are also
 connected through additional left joins). The default kind of join 
chosen by this rule may be overriden by inserting pseudo-roles
in the list, namely C<< '<=>' >> or C<< INNER >> for inner joins 
and C<< '=>' >> or C<< LEFT >> for left joins. So for example 

  MySchema->ViewFromRoles(qw/Department <=> activities <=> employee/);

becomes equivalent to 

  my $sql = <<_EOSQL_
  Department 
    INNER JOIN Activity ON Department.dpt_id = Activity.dpt_id
    INNER JOIN Employee ON Activity.emp_id   = Employee.emp_id
  _EOSQL_

All tables participating in a C<ViewFromRoles> are stacked,
and further roles are found by walking up the stack. So in

  ..->ViewFromRoles(qw/FirstTable role1 role2 role3/)

we must find a C<role1> in C<FirstTable>, from which we 
know what will be the C<Table2>. Then, we must find 
a C<role2> in in C<Table2>, or otherwise in C<FirstTable>,
in order to know C<Table3>. In turn, C<role3> must be 
found either in C<Table3>, or in C<Table2>, or in C<FirstTable>, etc.

The resulting view name will be composed by concatenating the table
and the capitalized role names. If join kinds were explicitly
set, these also belong to the view name, like
C<< Department_INNER_Activities >>.
Since such names might be long and uncomfortable 
to use, the view name is also returned as result of the method
call, so that the client code can store it in a variable and use
it as an alias.

The main purpose of C<ViewFromRoles> is to gain efficiency in
interacting with the database. If we write

  foreach my $dpt (@{Department->select}) {
    foreach my $act ($dpt->activities) {
      my $emp = $act->employee;
      printf "%s works in %s since %s\n", 
         $emp->{lastname}, $dpt->{dpt_name}, $act->{d_begin};
    }
  }

many database calls are generated behind the scene. 
Instead we could write 

  my $view = MySchema->ViewFromRoles(qw/Department activities employee/);
  foreach my $row (@{$view->select}) {
    printf "%s works in %s since %s\n", 
      $row->{lastname}, $row->{dpt_name}, $row->{d_begin};
  }

which generates one single call to the database.

Caveat : C<ViewFromRoles> does not know about SQL table aliases.
Therefore, if the role list contains several occurrences of the
same table (for example through self-referential associations),
the generated SQL will be incorrect because of ambiguous table names.

=head3 selectFromRoles

  my $lst = $obj->selectFromRoles(qw/role1 role2 .../)
                ->(-columns => [...], -where => {...}, -orderBy=>[...]);

Starting from a given object, returns a reference to a function that
selects a collection of data rows from associated tables, performing
the appropriate joins.  Internally this is implemented throught the
L</ViewFromRoles> 
method, with an additional join criteria to constrain
on the primary key(s) of C<$obj>.  The returned function takes the
same arguments as the L</select> method. So for example if 
C<< $emp->{emp_id} == 987 >>, then

  $emp->selectFromRoles(qw/activities department/)
      ->(-where => {d_end => undef})

will generate

  SELECT * FROM Activity INNER JOIN Department 
                         ON Activity.dpt_id = Department.dpt_id
           WHERE  emp_id = 987 AND d_end IS NULL


=head3 MethodFromRoles

  TableOrView->MethodFromRoles($meth_name => qw/role1 role2 .../);

Inserts into the class a new method named C<$meth_name>,
that will automatically call L</"selectFromRoles"> and
pass arguments to the resulting function.
This is useful for joining several tables at once, so for
example with 

  Department->MethodFromRoles(employees => qw/activities employee/);

we can then write 

  my $empl_ref = $someDept->employees(-where   => {gender => 'F'},
                                      -columns => [qw/firstname lastname]);

This method is used internally to implement many-to-many associations;
so if you have only two roles to follow, you would probably be better
off by defining the association, which is a more abstract notion.
Direct calls to C<MethodFromRoles> are still useful if you want
to follow three or more roles at once.


=head2 Schema or Table parameterization

=head3 DefaultColumns

  MyTable->DefaultColumns($columns);

Sets the default value for the C<-columns> argument to 
L<select()|/select>. If nothing else is stated, the
default value for all tables is 'C<*>'.


=head3 ColumnHandlers

  MyTable->ColumnHandlers($columnName => handlerName1 => coderef1,
                                         handlerName2 => coderef2, ...);

Associates some handlers to a given column in the current table class.
Then, when you call C<< $obj->applyColumnHandler('someHandler') >>,
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

Handlers receive the column value as usual through C<< $_[0] >>.
If the value is to be modified (for example for scalar
conversions or while inflating values into objects), 
the result should be put back into C<< $_[0] >>.
In addition to the column value, other info is passed to the
handler :

  sub myHandler {
    my ($columnValue, $obj, $columnName, $handlerName) = @;
    my $newVal = $obj->computeNewVal($columnValue, ...);
    $columnValue = $newVal; # WRONG : will be a no-op
    $_[0] = $newVal;        # OK    : value is converted
  }

The second argument C<< $obj >> is the object from where 
C<< $columnValue >> was taken -- most probably an instance 
of a Table or View class.  Use this if you need to read some contextual
information, but avoid modifying C<< $obj >> : you would most
probably get unexpected results, since the collection of 
available columns may vary from one call to the other.

Other arguments C<< $columnName >> and
C<< $handlerName >> are obvious.

Handler names B<fromDB> and B<toDB> have a special
meaning : they are called automatically just after reading data from
the database, or just before writing into the database.
Handler name B<validate> is used by the method
L</"hasInvalidColumns">.



=head3 ColumnType

  MySchema->ColumnType(type_name => handler_name1 => coderef1,
                                    handler_name2 => coderef2, ...);

Declares a collection of column handlers under name C<type_name>.

  MyTable->ColumnType(type_name => qw/column1 column2 .../);

Retrieves all column handlers defined under C<type_name> in the schema
and calls L</"ColumnHandlers"> to register those handlers to 
C<< column1 >>, C<< column2 >>, etc.


=head3 Autoload 

  MySchema->Autoload(1); # turn on AUTOLOAD 
  MySchema->Autoload(0); # turn it off
  MyClass ->Autoload(1); # turn it on, just for one class

If AUTOLOAD is turned on (default is off), 
then columns have implicit read accessors through AUTOLOAD. 
So instead of C<< $record->{column} >> you can write
C<< $record->column >>. 

Of course this is a bit slower than generating all accessors explicitly 
at compile time
(through L<Class::Accessor|Class::Accessor> or something similar),
but the advantage is that you don't need to know all column
names in advance. This is how we support variable column lists
(two instances of the same Table do not necessarily hold
the same set of columns, it all depends on what you chose when
doing the SELECT).

Caveat : AUTOLOAD is a global feature, so 
C<< MySchema->Autoload(1) >> actually turns it on 
for all schemas.


=head3 AutoInsertColumns

  MySchema->AutoInsertColumns( columnName1 => sub{...}, ... );
  MyTable ->AutoInsertColumns( columnName1 => sub{...}, ... );

Declares handler code that will automatically fill column names
C<columnName1>, etc. at each insert, either for a single table, or (if
declared at the Schema level), for every table. For example, each
record could remember who created it and when with something
like

  MySchema->AutoInsertColumns( created_by => 
    sub{$ENV{REMOTE_USER} . ", " . localtime}
  );

The handler code will be called as 

  $handler->(\%record, $table)

so that it can know something about its calling context.  In most
cases, however, the handler will not need these parameters, because it just
returns global information such as current user or current date/time.


=head3 AutoUpdateColumns

  MySchema->AutoUpdateColumns( columnName1 => sub{...}, ... );
  MyTable ->AutoUpdateColumns( columnName1 => sub{...}, ... );

Just like C<AutoInsertColumns>, but will be called automatically
at each update B<and> each insert. This is typically used to 
remember the author and/or date and time of the last modification
of a record. If you use both C<AutoInsertColumns> and 
C<AutoUpdateColumns>, make sure that the column names are not 
the same.

When doing an I<update> (i.e. not an insert), the
handler code will be called as 

  $handler->(\%record, $table, \%where)

where C<%record> contains the columns to be updated and
C<%where> contains the primary key (column name(s) and value(s)).

=head3 NoUpdateColumns

  MySchema->NoUpdateColumns(@columns);
  MyTable ->NoUpdateColumns(@columns);

Defines an array of column names that will be excluded from 
INSERT/UPDATE statements. This is useful for example when
some column are set up automatically by the database 
(like automatic time stamps or user identification).
It can also be useful if you want to temporarily add information
to memory objects, without passing it back to the database.

NoUpdate columns can be set for a whole Schema, or
for a specific Table class.


=head3 AutoExpand

  Table->AutoExpand(qw/role1 role2 .../)

Generates an L</"autoExpand"> method for the class, that 
will autoexpand on the roles listed (i.e. will call
the appropriate method and store the result
in a local slot within the object). 
In other words, the object knows how to expand itself,
fetching information from associated tables, in order
to build a data tree in memory.
Only roles declared as L<Compositions|/"Composition">
may be auto-expanded.

Be careful about performance issues: when an object uses
auto-expansion through a call to L</"autoExpand">, every auto-expanded
role will generate an additional call to the database. This might
be slow, especially if there are recursive auto-expansions;
so in some cases it will be more appropriate to flatten the tree
and use database joins, typically through the method
L<selectFromRoles|/"selectFromRoles">.


=head2 Schema runtime properties or parameterization methods

=head3 dbh

  my $dbh = DBI::connect(...);
  Schema->dbh($dbh, %options);        # set

  my $dbh             = Schema->dbh;  # get back just the dbh
  my ($dbh, %options) = Schema->dbh;  # get back all

Returns or sets the handle to a DBI database handle (see L<DBI>). 
This handle is schema-specific.
C<DBIx::DataModel> expects the handle to be opened with
C<< RaiseError => 1 >>
(see L</"Transactions and error handling">).

In C<%options> you may pass any key-value pairs, and retrieve
them later by calling C<dbh> in a list context. 
C<DBIx::DataModel> will look in those options to try to find
the "catalog" and "schema" arguments for C<DBI>'s 
L<last_insert_id|DBI/last_insert_id>.



=head3 schema

  $schema = TableOrView->schema;
  $schema = $myObj->schema;

Returns the name of the schema class for the current object or current 
Table or View class.



=head3 db_table

  $db_table = TableOrView->db_table;
  $db_table = $obj->db_table;

Returns the database table name registered via C<< Schema->Table(..) >> 
or collection of joined tables registered via C<< Schema->View(..) >>.


=head3 debug

  Schema->debug( 1 );            # will warn for each SQL statement
  Schema->debug( $debugObject ); # will call $debugObject->debug($sql)
  Schema->debug( 0 );            # turn off debugging

Debug mode is useful for seeing SQL statements generated 
by C<DBIx::DataModel>. Enabling debugging with a C<$debugObject>
will typically be useful in conjunction with something like 
L<Log::Log4perl|Log::Log4perl> or 
L<Log::Dispatch|Log::Dispatch>.

There is also another way to see the SQL code :

  my $spy_sql = sub {my ($sql, @bind) = @_;
                     print STDERR join "\n", $sql, @bind;
                     return ($sql, @bind);};
  
  my $result = $myClassOrObj->$someSelectMethod(-columns  => \@columns,
                                                -where    => \%criteria,
                                                -postSQL  => $spy_sql);



=head3 classData

  my $val = $someClass ->classData->{someKey};
  my $val = $someObject->classData->{someKey};

Returns a ref to a hash for storing class-specific data.
Each subclass has its own hashref, so class data is NOT propagated
along the inheritance tree. Class data should be mainly
for reading; if you write into it, make sure you know what 
you are doing.

=head3 primKey

  my @primKeyColumns = Table->primKey;
  my @primKeyValues  = $obj->primKey;

If called as a class method, returns the list of columns
registered as primary key for that table (via C<< Schema->Table(..) >>).

If called as an instance method, returns the list of values 
in those columns.

When called in scalar context and the primary key has only one column,
returns that column (so you can call C<< $my k = $obj->primKey >>).

=head3 componentRoles

  my @roles = Table->componentRoles;

Returns the list of roles declared through L</"Composition">.


=head3 noUpdateColumns

  my @cols = MySchema->noUpdateColumns;

Returns the array of column names declared as noUpdate
through L</"NoUpdateColumns">.

  my @cols = $obj->noUpdateColumns;

Returns the array of column names
declared as noUpdate, either in the Schema or in the Table
class of the invocant.


=head3 autoUpdateColumns

  my @cols = MySchema->autoUpdateColumns;

Returns the array of column names declared as autoUpdate
through L</"AutoUpdateColumns">.

  my @cols = $obj->autoUpdateColumns;

Returns the array of column names declared as autoUpdate,
either in the Schema or in the Table class of the invocant.


=head3 selectImplicitlyFor

  MySchema->selectImplicitlyFor('read only'); # will be added to SQL selects
  MySchema->selectImplicitlyFor('');          # turn it off

Gets or sets a default value for the C<-for> argument to 
L<select()|/"select">. Here it is set 
at the C<Schema> level, so it will be applied to all tables.

  TableOrView->selectImplicitlyFor('read only');
  TableOrView->selectImplicitlyFor('');         

Same thing, but at a Table or View level.

  my $string = $obj->selectImplicitlyFor;   

Retrieves whatever whas set in the table or in the schema.


=head3 tables

   my @tables = MySchema->tables;

Returns an array of names of C<Table> subclasses declared in this schema.


=head3 views

   my @views = MySchema->views;

Returns an array of names of C<View> subclasses declared in this schema.



=head3 keepLasth

  MySchema->keepLasth(1); # schema will keep a reference to the last DBI handle
  MySchema->keepLasth(0); # turn it off

If true, the schema will keep a copy of the last generated
SQL statement handle (either C<select>, C<insert> or C<update>).
The handle may then be accessed through C<< $obj->schema->lasth >>.
This may be useful if you need to interact with the handle
for driver-specific operations. However, it also means that the
handle is not DESTROYed immediately, which might result in 
resources being locked until the next statement. Therefore
C<keepLasth> is off by default.


=head3 lasth

  my $sth = MySchema->lasth;

Returns the last DBI statement handle created by this module, if 
C<keepLasth> is turned on.




=head2 Data retrieval and manipulation methods

=head3 doTransaction

  my $coderef = sub {Table1->insert(...); Table2->update(...); ...};
  MySchema->doTransaction($coderef);

Evaluates the code within a transaction. In case of failure,
the transaction is rolled back, and an exception is raised with
the error message and the status of the rollback (because the
rollback itself may also fail).

Usually the coderef passed as argument will be a
closure that may refer to variables local to the environment where
it was created.

=head3 fetch

  my $record = MyTable->fetch(@keyValues, \%options);

Searches the single record whose primary key is C<< @keyValues >>.
Returns undef if none is found. The optional C<< \%options >> 
argument can specify things like C<-for>, C<-preExec>, C<-postExec>
(see the L<select()|/"select"> method 
for an explanation). Of course
it makes no sense to specify C<-where> in the options.




=head3 select

  my $records = TableOrView->select(\@columns, \%where, \@order);
  
  my $records = TableOrView->select(-columns  => \@columns, 
                                    # OR : -distinct => \@columns,
                                    -where    => \%where, 
                                    -groupBy  => \@groupings,
                                    -having   => \%criteria,
                                    -orderBy  => \@order,
                                    -for      => 'read only',
                                    -postSQL  => \&postSQL_callback,
                                    -preExec  => \&preExec_callback,
                                    -postExec => \&preExec_callback,
                                    -resultAs => 'rows' || 'sth' || 
                                                 'sql'  || 'iterator');
  
  my $wholeTable = Table->select();

Applies a SQL SELECT to the associated table (or view), and returns 
a result as specified by the C<-resultAs> argument (see below).
Arguments are all optional and may be passed either by name or by position
(but you cannnot combine both positional and named arguments in a single call).

The API is mostly borrowed from L<SQL::Abstract|SQL::Abstract> :

=over

=item * 

the first argument C<< \@columns >>  is a reference to an array
of SQL column specifications (i.e. column names, 
function or grouping operators, "AS" clauses, etc.).

A '|' in a column is translated into an 'AS' clause, according
to the current L<SQL dialect|"Schema">: this is convenient when
using perl C<< qw/.../ >> operator for columns, as in

  -columns => [ qw/table1.longColumn|t1lc table2.longColumn|t2lc/ ]

The argument to C<-columns> can also be a string instead of 
an arrayref, like for example
C<< "c1 AS foobar, MAX(c2) AS m_c2, COUNT(c3) AS n_c3" >>. 

If omitted, C<< \@columns >> takes the default, which is
usually '*', unless modified through L<DefaultColumns()|/DefaultColumns>.

No verification is done on the list of retrieved C<< \@columns >>,
so it is OK if the list does not contain the primary or foreign keys --- 
but then later attempts to perform joins or updates will obviously fail.


=item *

the second argument C<< \%where >> is a reference to a hash or array of 
criteria that will be translated into SQL clauses. In most cases, this
will just be something like C<< {col1 => 'val1', col2 => 'val2'} >>;
see L<SQL::Abstract::select|SQL::Abstract/select> for 
 detailed description of the
structure of that hash or array. It can also be
a plain SQL string like C<< "col1 IN (3, 5, 7, 11) OR col2 IS NOT NULL" >>.

=item *

the third argument C<< \@order >> is a reference to a list 
of columns for sorting. Again it can also be a plain SQL string
like C<< "col1 DESC, col3, col2 DESC" >>. Columns can 
also be prefixed by '+' or '-' for indicating sorting directions,
so for example C<< -orderBy => [qw/-col1 +col2 -col3/] >>
will generate the SQL clause
C<< ORDER BY col1 DESC, col2 ASC, col3 DESC >>.


=back

If using named arguments, more options are available :

=over

=item C<< -distinct => \@columns >> 

behaves like the C<< -columns >> arguments, except that 
keyword C<DISTINCT> will be included in the generated SQL.

=item C<< -groupBy => "string" >>  or C<< -groupBy => \@array >> 

adds a C<GROUP BY> clause in the SQL statement. Grouping columns are
specified either by a plain string or by an array of strings.

=item C<< -having => "string" >>  or C<< -having => \%criteria >> 

adds a C<HAVING> clause in the SQL statement (only makes
sense together with a C<GROUP BY> clause).
This is like a C<-where> clause, except that the criteria
are applied after grouping has occured.


=item C<< -for => $clause >> 

specifies an additional clause to be added at the end of the SQL statement,
like C<< -for => 'read only' >> or C<< -for => 'update' >>.

=item C<< -postSQL => \&postSQL_callback >>

hook for specifying a callback function to be called on SQL code and
bind values, before preparing the statement. It will be called as
follows:

  ($sql, @bind) = $args->{-postSQL}->($sql, @bind) if $args->{-postSQL};


=item C<< -preExec => \&preExec_callback, -postExec => \&postExec_callback >>

hooks for specifying callback functions to be called on the DBI statement
handle, just before or just after invoking C<< execute() >>. So the sequence
will be more or less like this:

  $sth = $dbh->prepare($sql_statement);
  $preExec_callback->($sth)  if $preExec_callback;
  $sth->execute(@bind_values);
  $postExec_callback->($sth) if $postExec_callback;

This is mostly useful if you need to call driver-specific functions at 
those stages.

=item C<< -resultAs => $result_kind >>

specifies what kind of result will be produced. Possible result kinds are :

=over

=item B<rows>

The result will be a ref to an array of rows, blessed into objects of the 
class. This is the default result kind. If there are no data rows, a ref
to an empty list is returned.

=item B<iterator> 

The result is a simple iterator object with a unique method: C<next>,
that fetches the next datarow and blesses it into the appropriate object.
The method returns C<undef> when there is no more data to fetch.
So a typical usage pattern is :

  my $iterator = $class->select(-where    => \%criteria, 
                                -resultAs => 'iterator');
  while (my $row = $iterator->next) {
    do_something_with($row);
  }

=item B<sth> or B<statement>

The result will be an executed C<DBI> statement handle. Then it is up to the 
caller to retrieve data rows using the DBI API.
If needed, these rows can then be blessed into appropriate objects
through L<blessFromDB()|/"blessFromDB">.

=item B<sql> 

In scalar context, the result will just be the generated SQL statement. 
In list context, it will be C<($sql, @bind)>, i.e. the SQL statement 
together with the bind values.


=back


=back



=head3 insert

  my @ids = MyTable->insert({col1 => $val1, col2 => $val2, ...}, {...});

Applies the C<toDB> handlers, removes the C<noUpdate> columns, 
and then inserts the new records into the database.
Because of the handlers, this operation I<may modify the argument data>, 
so it is not safe to access C<$val1>, C<$val2>, etc. after the call.

Primary key column(s) should of course be present 
in the supplied hashrefs, unless the the key is auto-generated.

Each hashref will be blessed into the C<MyTable> class, and
will be inserted through the internal L</"_singleInsert"> method.
The default implementation of this method should be good enough
for most common uses, but you may want to refine it in your
table classes if you need some fancy handling on primary keys
(like for example computing a random key and checking whether
that key is free). 

Scalar values returned by L</"_singleInsert"> are collected into
an array, and then returned by C<insert()>; usually, these are
the primary keys of the inserted records (if on one single column).
In scalar context, the return value is the first id in the list above, which
makes sense if you call insert() with a single argument.  If you call
it with several arguments but from a scalar context, a warning is issued.

If the table is a composite class (see L</"Composition"> above), then
the component parts may be supplied within the hashref, with keys
equal to the role names, and values given as arrayrefs of sub-hashrefs;
then these will be inserted into the database, at the same time as the
main record, with join values automatically filled in.  For example :

   HR::Employee->insert({firstname  => "Johann Sebastian",  
                         lastname   => "Bach",
                         activities => [{d_begin  => '01.01.1695',
        			         d_end    => '18.07.1750',
	        		         dpt_code => 'CPT'}]});


=head3 update

  MyTable->update({col1 => $val1, ...});
  MyTable->update(@primKey, {col1 => $val1, ...});
  $obj->update;

This is both a class and an instance method.
It applies the C<toDB> handlers, removes the C<noUpdate> columns, 
and then updates the database for the given record.

When called as a class method, the columns and values to update
are supplied as a hashref. The second syntax with 
C<< @primKey >> is an alternate way to supply the values
for the primary key (it may be more convenient because you don't
need to repeat the name of primary key columns). So if C<emp_id>
is the primary key of table C<Employee>, then the following
are equivalent :

  Employee->update({emp_id => $eid, address => $newAddr, phone => $newPhone});
  Employee->update($eid => {address => $newAddr, phone => $newPhone});

When called as an instance method, i.e. 

  $someEmployee->update;

the columns and values to update are taken from the object in 
memory (ignoring all non-scalar values). After the update, 
I<the memory for that object is emptied> (to prevent any confusion,
because the 'toDB' handlers might have changed the values).
So to continue working with the same record, you must fetch it again 
from the database (or clone it yourself before calling C<update>).

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

the final state of record C<$id> in the database will 
reflect changes from both clients. 


=head3 delete

  MyTable->delete({column1 => value1, ...});
  MyTable->delete(@primKey);
  $record->delete;

This is both a class and an instance method.
It deletes a record from the database.

When called as a class method, the primary key of the record 
to delete is supplied either as a hashref, or directly
as a list of values. Note that C<< MyTable->delete(11, 22) >>
does not mean "delete records with keys 11 and 22", but rather
"delete record having primary key (11, 22)"; in other words,
you only delete one record at a time. In order to 
simultaneously delete several records according to some
C<WHERE> criteria, you must generate 
the SQL yourself and go directly to the L<DBI|DBI> level.

When called as an instance method, the primary key is taken
from object columns in memory. After the delete, 
the memory for that object is destroyed.
If the table is a composite class (see L</"Composition"> above), 
and if the object contains references to lists of component parts, 
then those will be recursively deleted together with the main 
object (cascaded delete). However, if there are other component parts
in the database, not referenced in the hashref, then those will 
not be automatically deleted : in other words, the C<delete>
method does not go by itself to the database to find all
dependent composite parts (this is the job of the client code, or 
sometimes of the database itself).


=head3 applyColumnHandler

  TableOrView->applyColumnHandler($handlerName, \@objects);
  $myObject  ->applyColumnHandler($handlerName);

Inspects the target object or list of objects; for every
column that exists in the object, checks whether
a handler named C<< $handlerName >> was declared for
that column (see method L</ColumnHandlers>), and if so, 
calls the handler. By this definition, if a column
is I<absent> in an object, then the handler for that column
is not called, even though it was declared in the class.

The results of handler calls are collected into a hashref, with an
entry for each column name.  The value of each entry depends on how
C<< applyColumnHandlers >> was called : if it was called as an
instance method, then the result is something of shape

  {columnName1 => resultValue1, columnName2 => resultValue2, ... }

if it was called as a class method (i.e. if C<< \@objects >> is defined),
then the result is something of shape

  {columnName1 => [resultValue1forObject1, resultValue1forObject2, ...], 
   columnName2 => [resultValue2forObject1, resultValue2forObject2, ...], 
   ... }

If C<columnName> is not present in the target object(s), then the 
corresponding result value is  C<undef>.


=head3 hasInvalidColumns

  my $invalid_columns = $obj->hasInvalidColumns;
  if ($invalid_columns) {
    print "wrong data in columns ", join(", ", @$invalid_columns);
  }
  else {
   print "all columns OK";
  }


Applies the 'validate' handler to all existent columns.
Returns a ref to the list of invalid columns, or
undef if there are none.

Note that this is validation at the column level, not at the record
level. As a result, your validation handlers can check if an existent
column is empty, but cannot check if a column is missing (because in
that case the handler would not be called).

Your 'validate' handlers, defined through L</ColumnHandlers>,
should return 0 or an empty string whenever the column value is invalid.
Never return C<undef>, because we would no longer be able to
distinguish between an invalid existent column and a missing column.


=head3 expand

  $obj->expand($role [, @args] )

Executes the method C<< $role >> to follow an Association,
stores the result in the object itself under C<< $obj->{$role} >>,
and returns that result.
This is typically used to expand an object into a tree datastructure.
Optional C<< @args >> are passed to C<< $obj->$role(@args) >>, for
example for specifying C<-where>, C<-columns> or C<-orderBy> options.

After the expansion, further calls to 
C<< $obj->$role >> (without any arguments) will reuse 
that same expanded result instead of calling again the database.
This caching improves efficiency, but also introduces the risk
of side-effects across your code : after 

  $obj->expand(someRole => (-columns => [qw/just some columns/],
                            -where   => [someField => 'restriction']))

further calls to C<< $obj->someRole() >> will just return
a dataset restricted according to the above criteria, instead
of a full join. To prevent that effect, you would need to 
C<< delete $obj->{someRole} >>, or to call the role
with arguments : C<< $obj->someRole('*') >>.



=head3 autoExpand

  $record->autoExpand( $recurse );

Asks the object to expand itself with some objects in foreign tables.
Does nothing by default. Should be redefined in subclasses,
most probably through the 
L</AutoExpand> method (with capital 'A').
If the optional argument C<$recurse> is true, then 
C<autoExpand> is recursively called on the expanded objects.



=head3 blessFromDB

  TableOrView->blessFromDB($record);

Blesses C<< $record >> into an object of the class,
and applies the C<fromDB> column handlers.


=head3 preselectWhere

  my $meth = TableOrView->preselectWhere({col1 => $val1, ...}, $multiplicity);
  
  # .. later
  my $result = $meth->(-where =>{otherCol => 'otherVal'}, -columns => \@cols);


Returns a reference to a function that will select data from
C<MyTable>, just like the C<select()> method, but where some
additional selection criteria are "preselected". The preselection
criteria are specified in L<SQL::Abstract|SQL::Abstract> format. 
This method is
mainly for internal use; you only want to learn about it if you
intend to write your own role methods; an example is shown in section
L</"Self-referential associations"> below.

If the optional C<< $multiplicity >> argument contains C<1> or C<'0..1'>,
then the function behaves like 
L<fetch()|/fetch> rather than C<select()|/select>: 
that is, the result of C<< $meth->(...) >> will be a single 
recordref, rather than an arrayref of records.


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
The L<doTransaction()|/doTransaction> method does all this for you 
automatically.

=head3 Calling DBI directly

Maybe you will encounter situations where 
you need to generate SQL yourself (for example because of
clauses specific to your RDBMS), or to interact directly
with the DBI layer. This can be encapsulated in
additional methods incorporated into the classes
generated by C<DBIx::DataModel>.
In those methods, you may want to call L<blessFromDB()|/blessFromDB>
so that the rows returned by DBI may be seen as
objects from your client program. Here is an example :

  package MyTable; # switch to namespace 'MyTable'

  sub fancyMethod {

    # call the DBI API
    my $hash = $dbh->selectall_hashref($fancySQL, @keyFields);

    # bless results into objects of MyTable
    MyTable->blessFromDB($_) foreach values %$hash;

    return $hash;
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
                        [qw/Person children * father_id/]); # BUG

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


And here is a more sophisticated way to define the "children" method,
that will accept additional "where" criteria, like every regular method.

  package Person;
  sub children {
    my $self        = shift; # remaining args in @_ will be passed to select()
    my $id          = $self->{pers_id};
    my $select_func = Person->preselectWhere([mother_id => $id, 
					      father_id => $id]);
    return $select_func->(@_);
  }

This definition forces the join on C<mother_id> or 
C<father_id>, while leaving open the possibility for the caller
to specify additional criteria. For example, all female children 
of a person (either father or mother) can now be retrieved through

  $person->children({gender => 'F'})

Observe that C<mother_id> and C<father_id> are inside an arrayref
instead of a hashref, so that L<SQL::Abstract> will generate an SQL 'OR'.



=head1 INTERNALS

This section documents some details that normally should not be
relevant to clients; you only want to read about them if you
intend to extend the framework.


=head2 Class hierarchy

The following picture shows the hierarchy of implementation classes :

             +-----------------------+
             | DBIx::DataModel::Base |
             +-----------------------+
                   /                \
                  /                  \
   +-------------------------+   +--------------------------------+
   | DBIx::DataModel::Schema |	 | DBIx::DataModel::AbstractTable |
   +-------------------------+ 	 +--------------------------------+
                                       /                   \
                                      /                     \
                       +------------------------+  +-----------------------+
	               | DBIx::DataModel::Table |  | DBIx::DataModel::View |
	               +------------------------+  +-----------------------+


    +-----------------+	   +---------------------------+
    | DBIx::DataModel |	   | DBIx::DataModel::Iterator |
    +-----------------+	   +---------------------------+

The L</Schema> method creates a subclass of 
L<DBIx::DataModel::Schema|DBIx::DataModel::Schema>.
The L</Table> method creates a subclass of 
L<DBIx::DataModel::Table|DBIx::DataModel::Table>.
The L</View> method and its related clients (L</ViewFromRoles>, 
L</selectFromRoles>, etc.) use multiple inheritance : views inherit 
first from 
L<DBIx::DataModel::View|DBIx::DataModel::View>,
but also from the supplied
list of I<parent tables>. As a result, instances of such views can
exploit all role methods of their parent tables.
The entry class 
L<DBIx::DataModel|DBIx::DataModel>
is just a façade interface to 
L<DBIx::DataModel::Schema|DBIx::DataModel::Schema>.
The helper class 
L<DBIx::DataModel::Iterator|DBIx::DataModel::Iterator> implements
iterators returned by the L</select> method.


=head2 Private methods

=head3 _setClassData

  DBIx::DataModel::Base->_setClassData($subclass, $data_ref);


=head3 _createPackage

  DBIx::DataModel::Schema->_createPackage($pckName, $isa_arrayref);

Creates a new Perl package of name C<$pckName> that inherits from
C<@$isa_arrayref>. Raises an exception if the package name already
exists.

=head3 _defineMethod

  DBIx::DataModel::Schema->_defineMethod($pckName, $methName, $coderef);

Defines a new method in package C<$pckName>, bound to C<$coderef>;
or undefines a method if C<$coderef> is C<undef>.
Raises an exception if the method name already
exists in that package.

=head3 _rawInsert

  $obj->_rawInsert;

Internal implementation for insertions into the database :
takes keys and values within C<%$obj>, generates SQL for 
insertion of those values into C<< $obj->dbTable >>,
and executes it. Never called directly, but used by the protected method
L</"_singleInsert>.

=head2 "Protected" methods

=head3 _singleInsert

  $obj->_singleInsert;

Implementation for inserting a record into the
database; should never be called directly, but is used as 
a backend by the L</"insert"> method. 

This method receives an object blessed into some table class; the
object hash should only contain keys and values to be directly
inserted into the database, i.e. the C<noUpdateColumns> and all
references to foreign objects should have been removed already (this
is the job of the L</"insert"> method).  The method calls
L</"_rawInsert"> for performing the database update, and then makes
sure that the object contains its own key (if not supplied by the
client code, for example when keys are auto-generated, then
the key has to be .

In the default implementation, this is done by calling DBI's
L<last_insert_id()|DBI/last_insert_id> whenever necessary. This may or
may not be meaningful, depending on your database driver.  The four
arguments required by C<last_insert_id> are
supplied as follows : catalog and schema names are taken from options
given to C<< Schema->dbh(...) >> (or C<undef> otherwise), table and
column names are taken from the object's database table and 
primary key, as declared in C<< Schema->Table(...) >>.

You may redeclare this method in your own table classes,
for example if you need to compute a key, or construct it
from other fields. 

The scalar value returned by the method
will in turn be returned by the L</"insert"> method; usually 
this value if the primary key, if that key is on one single column.


=head1 SEE ALSO


Some alternative modules in this area are  
L<Class::DBI>, L<DBIx::Class>,
L<Alzabo>, L<Tangram>,
L<Rose::DB::Object>,
L<Data::ObjectDriver>,
L<ORM>,
L<SPOPS>, L<Class::PObject>, , L<DBIx::RecordSet>,
L<DBIx::SQLEngine>,L<DBIx::Record>, , and a lot more 
in the C<DBIx::*> namespace, all with different approaches.
For various reasons, none of these did  fit nicely in my context, 
so I decided to write C<DBIx:DataModel>.
Of course there might be also many reasons why C<DBIx:DataModel>
will not fit in I<your> context, so just do your own shopping.
A good place to start would be the general discussion on RDBMS - Perl 
mappings at L<http://poop.sourceforge.net>. There are also some
pointers in the Perl 5 Enterprise Environment website at 
L<http://www.officevision.com/pub/p5ee/>.

For discussions about C<DBIx::DataModel>, 
please use the CPAN::Forum site at
L<http://www.cpanforum.com/dist/DBIx-DataModel>.

=head1 TO DO 

  - autoloader to get tables and associations from $dbh->table_info, etc.
  - 'hasInvalidColumns' : should be called automatically before insert/update ?
  - 'validate' record handler (not only column handlers)
  - 'normalize' handler : for ex. transform empty string into null
  - walk through WHERE queries and apply 'toDB' handler (not obvious!)
  - decide what to do with multiple inheritance of role methods in Views;
    use NEXT ?
  - implement table aliases
  - maybe it is not a good idea to modify data in place when 
    performing inserts or updates; should perhaps clone the arguments.
  - more extensive and more organized testing
  - optional caching for fetch() within lookup tables
  - add support for UPDATE/DELETE ... WHERE ...
  - add PKEYS keyword in -columns, will be automatically replaced by 
    names of primary key columns of the touched tables
  - design API for easy dynamic association of objects without dealing 
    with the keys
  - remove spouse example from doc (because can't have same table twice in roles)
  - syntax for column aliases : Column|col
  - idem for tables
  - support for bind parameters for blobs

=head1 AUTHOR

Laurent Dami, E<lt>laurent.dami AT etat  geneve  chE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2006 by Laurent Dami.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 
