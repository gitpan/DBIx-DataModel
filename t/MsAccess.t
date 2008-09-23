use strict;
use warnings;
no warnings 'uninitialized';
use DBI;

use Test::More tests => 5;

sub die_ok(&) { my $code=shift; eval {$code->()}; ok($@, $@);}



BEGIN {use_ok("DBIx::DataModel");}

  BEGIN { DBIx::DataModel->Schema('HR', sqlDialect => 'MsAccess'); }
  
  BEGIN {
    HR->Table(Employee   => T_Employee   => qw/emp_id/);
    HR->Table(Department => T_Department => qw/dpt_id/);
    HR->Table(Activity   => T_Activity   => qw/act_id/);
  }

  HR->Composition([qw/Employee   employee   1 /],
                  [qw/Activity   activities * /]);
  HR->Association([qw/Activity   activities * dpt_id/],
		  [qw/Department department 1 dpt_id/]);

  HR->ColumnType(Date => 
     fromDB   => sub {$_[0] =~ s/(\d\d\d\d)-(\d\d)-(\d\d)/$3.$2.$1/},
     toDB     => sub {$_[0] =~ s/(\d\d)\.(\d\d)\.(\d\d\d\d)/$3-$2-$1/},
     validate => sub {$_[0] =~ m/(\d\d)\.(\d\d)\.(\d\d\d\d)/});;

  HR::Employee->ColumnType(Date => qw/d_birth/);
  HR::Activity->ColumnType(Date => qw/d_begin d_end/);

  HR->NoUpdateColumns(qw/d_modif user_id/);
  HR::Employee->NoUpdateColumns(qw/last_login/);

  HR::Employee->ColumnHandlers(lastname => normalizeName => sub {
			    $_[0] =~ s/\w+/\u\L$&/g
			  });

  HR::Employee->AutoExpand(qw/activities/);


SKIP: {
  my $dbh;
  eval {$dbh = DBI->connect('DBI:Mock:', '', '', {RaiseError => 1})};
  skip "DBD::Mock does not seem to be installed", 4 if $@ or not $dbh;


  sub sqlLike { # closure on $dbh
    my $sql = quotemeta(shift);
    my $bind = shift;
    my $msg = shift;
    $sql =~ s/(\\?\s)+/\\s+/gs;
    $sql =~ s/\\\(/\\(\\s*/g;
    $sql =~ s/\\\)/\\s*\\)/g;
    my $regex = qr/^\s*$sql\s*$/i;
    my $dbd_last = $dbh->{mock_all_history}[-1];
    like($dbd_last->statement, $regex, "$msg (SQL)");
    is_deeply($dbd_last->bound_params, $bind, "$msg (params)");
    $dbh->{mock_clear_history} = 1;
  }


  HR->dbh($dbh);

  my $emp = HR::Employee->blessFromDB({emp_id => 999});



  my $view = HR->join(qw/Employee activities department/);

  $view->select("lastname, dpt_name", {gender => 'F'});
  sqlLike('SELECT lastname, dpt_name ' .
	  'FROM t_employee LEFT OUTER JOIN (t_activity ' .
	  'LEFT OUTER JOIN (t_department) ' .
	  'ON t_activity.dpt_id=t_department.dpt_id) ' .
	  'ON t_employee.emp_id=t_activity.emp_id ' .		
	  'WHERE (gender = ?)', ['F'], 'join (MsAccess)');


  $emp->join(qw/activities department/)
      ->select({gender => 'F'});
  sqlLike('SELECT * ' .
	  'FROM t_activity ' .
	  'INNER JOIN (t_department) ' .
	  'ON t_activity.dpt_id=t_department.dpt_id ' .
	  'WHERE (emp_id = ? AND gender = ?)', [999, 'F'], 
	  'selectFromRoles (MsAccess)');

};


