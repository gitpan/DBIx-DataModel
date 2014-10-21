# Test that DBIx::DataModel::Schema::_State::DESTROY preserves $@

use strict;
use warnings;
use DBI;
use DBIx::DataModel;

use constant N_DBI_MOCK_TESTS => 1;

use Test::More tests => N_DBI_MOCK_TESTS;

# fake method Foo::dbh() that uses an eval {}
DBIx::DataModel->Schema('Foo');
package Foo;
sub dbh {
  my $class = shift;
  eval { $class .= "" }; # this succesful eval{} will clear $@ !
  $class->SUPER::dbh(@_);
}


# back to main package
package main;
SKIP: {
  eval "use DBD::Mock 1.36; 1"
    or skip "DBD::Mock 1.36 does not seem to be installed", N_DBI_MOCK_TESTS;

  my $dbh = DBI->connect('DBI:Mock:', '', '', {RaiseError => 1});
  eval {
    Foo->dbh($dbh);
    {
      my $scope_guard = Foo->localizeState;
      die "aargh\n";
    } 
    # here $scope_guard is destroyed and calls Foo::dbh()
  };

  # check that we didn't loose the error message
  is ($@, "aargh\n", "error message is preserved");
}

