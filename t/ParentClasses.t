package Foo::Parent::Table;

our @ISA = qw/DBIx::DataModel::Table/;

package Foo::Parent::V1;

our @ISA = qw/DBIx::DataModel::View/;

package Foo::Parent::V2;

our @ISA = qw/DBIx::DataModel::View/;

package main;
use strict;
use warnings;
no warnings 'uninitialized';
use DBI;

use Test::More tests => 6;


BEGIN {use_ok("DBIx::DataModel");}


DBIx::DataModel->Schema('MySchema', tableParent => 'Foo::Parent::Table',
                                    viewParent  => [qw/Foo::Parent::V1
                                                       Foo::Parent::V2/]);

MySchema->Table(Employee   => T_Employee   => qw/emp_id/);
MySchema->Table(Department => T_Department => qw/dpt_id/);
MySchema->Table(Activity   => T_Activity   => qw/act_id/);

MySchema->Composition([qw/Employee   employee   1 /],
                      [qw/Activity   activities * /]);
MySchema->Association([qw/Activity   activities * dpt_id/],
                      [qw/Department department 1 dpt_id/]);

ok(Employee->isa('Foo::Parent::Table'),     "isa table custom");
ok(Employee->isa('DBIx::DataModel::Table'), "isa table base");

my $view = MySchema->ViewFromRoles(qw/Employee activities department/);

ok($view->isa('Foo::Parent::V1'),       "isa view custom 1");
ok($view->isa('Foo::Parent::V2'),       "isa view custom 2");
ok($view->isa('DBIx::DataModel::View'), "isa view base");

