use strict;
use warnings;
no warnings 'uninitialized';
use DBI;

use constant N_TESTS => 3;
use Test::More tests => N_TESTS;
use POSIX qw/_exit/;
use IO::Handle;

use DBIx::DataModel;

SKIP:
{
  $] >= 5.008
   or skip "need Perl 5.8 for in-memory IO::Handle ", N_TESTS;

  DBIx::DataModel->Schema('HR');

  HR->Table(Employee   => T_Employee   => qw/emp_id/);
  HR->Table(Department => T_Department => qw/dpt_id/);
  HR->Table(Activity   => T_Activity   => qw/act_id/);

  HR->Composition([qw/Employee   employee   1 /],
                  [qw/Activity   activities * /]);

  HR->Association([qw/Department department 1 /],
                  [qw/Activity   activities * /]);

  use Storable qw/store_fd fd_retrieve/; ;
  pipe my $child_fh, my $parent_fh or die $!;

  # fork a child
  my $pid = fork();

  no strict 'refs';

  if ($pid) { # is parent
    my $view    = HR->join(qw/Employee activities department/);
    my @records = map {bless {"foo$_" => "bar$_"}, $view} 1..3;
    my $isa     = \@{$view . "::ISA"};

    # serialize the instances and some class information
    store_fd [\@records, $view, $isa, $view->classData], $parent_fh;
    $parent_fh->flush;

    # the child will perform the tests, so force exit on parent
    wait;
    _exit(0);
  }
  else {       # is child
    # deserialize the instance and class information
    my $struct = fd_retrieve($child_fh);
    my ($records, $view, $isa, $classData) = @$struct;

    # check that class info is consistent (class has been properly recreated)

    is($view, ref $records->[0], 'class name');
    is_deeply($isa, \@{$view . "::ISA"}, 'ISA array');
    is_deeply($classData, $view->classData, 'class data');
  } 

} # end SKIP
