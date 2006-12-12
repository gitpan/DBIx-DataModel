use strict;
use warnings;
no warnings 'uninitialized';
use DBI;

use Test::More tests => 5;

sub die_ok(&) { my $code=shift; eval {$code->()}; ok($@, $@);}



BEGIN {use_ok("DBIx::DataModel");}

  BEGIN { DBIx::DataModel->Schema('MySchema', sqlDialect => 'MsAccess'); }
  
  BEGIN {
    MySchema->Table(Employee   => T_Employee   => qw/emp_id/);
    MySchema->Table(Department => T_Department => qw/dpt_id/);
    MySchema->Table(Activity   => T_Activity   => qw/act_id/);
  }

  MySchema->Composition([qw/Employee   employee   1 /],
                        [qw/Activity   activities * /]);
  MySchema->Association([qw/Activity   activities * dpt_id/],
			[qw/Department department 1 dpt_id/]);

  MySchema->ColumnType(Date => 
     fromDB   => sub {$_[0] =~ s/(\d\d\d\d)-(\d\d)-(\d\d)/$3.$2.$1/},
     toDB     => sub {$_[0] =~ s/(\d\d)\.(\d\d)\.(\d\d\d\d)/$3-$2-$1/},
     validate => sub {$_[0] =~ m/(\d\d)\.(\d\d)\.(\d\d\d\d)/});;

  Employee->ColumnType(Date => qw/d_birth/);
  Activity->ColumnType(Date => qw/d_begin d_end/);

  MySchema->NoUpdateColumns(qw/d_modif user_id/);
  Employee->NoUpdateColumns(qw/last_login/);

  Employee->ColumnHandlers(lastname => normalizeName => sub {
			    $_[0] =~ s/\w+/\u\L$&/g
			  });

  Employee->AutoExpand(qw/activities/);


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


  MySchema->dbh($dbh);

  my $emp = Employee->blessFromDB({emp_id => 999});



  my $view = MySchema->ViewFromRoles(qw/Employee activities department/);

  $view->select("lastname, dpt_name", {gender => 'F'});
  sqlLike('SELECT lastname, dpt_name ' .
	  'FROM t_employee LEFT OUTER JOIN (t_activity ' .
	  'LEFT OUTER JOIN (t_department) ' .
	  'ON t_activity.dpt_id=t_department.dpt_id) ' .
	  'ON t_employee.emp_id=t_activity.emp_id ' .		
	  'WHERE (gender = ?)', ['F'], 'ViewFromRoles (MsAccess)');


  $emp->selectFromRoles(qw/activities department/)->({gender => 'F'});
  sqlLike('SELECT * ' .
	  'FROM t_activity ' .
	  'INNER JOIN (t_department) ' .
	  'ON t_activity.dpt_id=t_department.dpt_id ' .
	  'WHERE (emp_id = ? AND gender = ?)', [999, 'F'], 
	  'selectFromRoles (MsAccess)');

};


