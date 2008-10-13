use strict;
use warnings;
no warnings 'uninitialized';
use DBI;
use Data::Dumper;

use constant N_DBI_MOCK_TESTS => 150;
use constant N_BASIC_TESTS    => 15;

use Test::More tests => (N_BASIC_TESTS + N_DBI_MOCK_TESTS);


# die_ok : succeeds if the supplied coderef dies with an exception
sub die_ok(&) { my $code=shift; eval {$code->()}; ok($@, $@);}



BEGIN {
use_ok("DBIx::DataModel");}

  BEGIN { DBIx::DataModel->Schema('HR'); } # Human Resources

ok(HR->isa("DBIx::DataModel::Schema"), 'Schema defined');

my ($lst, $emp, $emp2, $act);



# will not override an existing package
die_ok {DBIx::DataModel->Schema('DBI');};

  BEGIN {
    HR->Table(Employee   => T_Employee   => qw/emp_id/)
      ->Table(Department => T_Department => qw/dpt_id/)
      ->Table(Activity   => T_Activity   => qw/act_id/);
  }

ok(HR::Employee->isa("DBIx::DataModel::Table"), 'Table defined');
ok(HR::Employee->can("select"), 'select method defined');

  package HR::Department;
  sub currentEmployees {
    my $self = shift;
    my $currentAct = $self->activities({d_end => [{-is  => undef},
                                                  {"<=" => '01.01.2005'}]});
    return map {$_->employee} @$currentAct;
  }
  
  package main;		# switch back to the 'main' package


is_deeply([HR::Employee->primKey], ['emp_id'], 'primKey');

die_ok {HR::Employee->Table(Foo    => T_Foo => qw/foo_id/)};




  HR->Composition([qw/Employee   employee   1 /],
                        [qw/Activity   activities * /])
          ->Association([qw/Department department 1 /],
                        [qw/Activity   activities * /]);

ok(HR::Activity->can("employee"),   'Association 1');
ok(HR::Employee->can("activities"), 'Association 2');

  HR->View(MyView =>
     "DISTINCT column1 AS c1, t2.column2 AS c2",
     "Table1 AS t1 LEFT OUTER JOIN Table2 AS t2 ON t1.fk=t2.pk",
     {c1 => 'foo', c2 => {-like => 'bar%'}},
     qw/Employee Activity/);


ok(HR::MyView->isa("HR::Employee"), 'HR::MyView ISA HR::Employee'); 
ok(HR::MyView->isa("HR::Activity"), 'HR::MyView ISA HR::Activity'); 

ok(HR::MyView->can("employee"), 'View inherits roles');

  HR->ColumnType(Date => 
     fromDB   => sub {$_[0] =~ s/(\d\d\d\d)-(\d\d)-(\d\d)/$3.$2.$1/},
     toDB     => sub {$_[0] =~ s/(\d\d)\.(\d\d)\.(\d\d\d\d)/$3-$2-$1/},
     validate => sub {$_[0] =~ m/(\d\d)\.(\d\d)\.(\d\d\d\d)/});;

  HR::Employee->ColumnType(Date => qw/d_birth/);
  HR::Activity->ColumnType(Date => qw/d_begin d_end/);

  HR->NoUpdateColumns(qw/d_modif user_id/);
  HR::Employee->NoUpdateColumns(qw/last_login/);

is_deeply([HR::Employee->noUpdateColumns], 
	  [qw/d_modif user_id last_login/], 'noUpdateColumns');


  HR::Employee->ColumnHandlers(lastname => normalizeName => sub {
			    $_[0] =~ s/\w+/\u\L$&/g
			  });

  HR::Employee->AutoExpand(qw/activities/);

  $emp = HR::Employee->blessFromDB({firstname => 'Joseph',
                                lastname  => 'BODIN DE BOISMORTIER',
                                d_birth   => '1775-12-16'});
  $emp->applyColumnHandler('normalizeName');

is($emp->{d_birth}, '16.12.1775', 'fromDB handler');
is($emp->{lastname}, 'Bodin De Boismortier', 'ad hoc handler');


  # test self-referential assoc.
  HR->Association([qw/Employee   spouse   0..1 emp_id/],
                  [qw/Employee   ---      1    spouse_id/]);



SKIP: {
  eval "use DBD::Mock 1.36; 1"
    or skip "DBD::Mock 1.36 does not seem to be installed", N_DBI_MOCK_TESTS;

  my $dbh = DBI->connect('DBI:Mock:', '', '', {RaiseError => 1});

  # sqlLike : takes a list of SQL regex and bind params, and a test msg.
  # Checks if those match with the DBD::Mock history.

  sub sqlLike { # closure on $dbh
    my $msg = pop @_;    

    for (my $hist_index = -(@_ / 2); $hist_index < 0; $hist_index++) {
      my ($sql, $bind)  = (quotemeta(shift), shift);

      $sql =~ s/(\\?\s)+/\\s+/gs;
      $sql =~ s/\\\(/\\(\\s*/g;
      $sql =~ s/\\\)/\\s*\\)/g;
      my $regex = qr/^\s*$sql\s*$/i;
      my $hist = $dbh->{mock_all_history}[$hist_index];
      like($hist->statement, $regex, "$msg [$hist_index] (SQL)");
      is_deeply($hist->bound_params, $bind, "$msg [$hist_index] (params)");
    }
    $dbh->{mock_clear_history} = 1;
  }


  HR->dbh($dbh);
  isa_ok(HR->dbh, 'DBI::db', 'dbh handle');


  $lst = HR::Employee->select;
  sqlLike('SELECT * FROM t_employee', [], 'empty select');

  $lst = HR::Employee->select(-for => 'read only');
  sqlLike('SELECT * FROM t_employee FOR READ ONLY', [], 'for read only');


  $lst = HR::Employee->select([qw/firstname lastname emp_id/],
			  {firstname => {-like => 'D%'}});
  sqlLike('SELECT firstname, lastname, emp_id '.
	  'FROM t_employee ' .
	  "WHERE (firstname LIKE ?)", ['D%'], 'like select');


  $lst = HR::Employee->select({firstname => {-like => 'D%'}});
  sqlLike('SELECT * '.
	  'FROM t_employee ' .
	  "WHERE ( firstname LIKE ? )", ['D%'], 'implicit *');


  $lst = HR::Employee->select("firstname AS fn, lastname AS ln",
			  undef,
			  [qw/d_birth/]);

  sqlLike('SELECT firstname AS fn, lastname AS ln '.
	  'FROM t_employee ' .
	  "ORDER BY d_birth", [], 'order_by select');


  $dbh->{mock_clear_history} = 1;
  $dbh->{mock_add_resultset} = [ [qw/ln  db/],
                                 [qw/foo 2001-01-01/], 
                                 [qw/bar 2002-02-02/] ];
  $lst = HR::Employee->select(-columns => [qw/lastname|ln d_birth|db/]);
  sqlLike('SELECT lastname AS ln, d_birth AS db '.
	  'FROM t_employee', 
          [], 'column aliases');
  is($lst->[0]{db}, "01.01.2001", "fromDB handler on column alias");


  $lst = HR::Employee->select(-distinct => "lastname, firstname");

  sqlLike('SELECT DISTINCT lastname, firstname '.
	  'FROM t_employee' , [], 'distinct 1');


  $lst = HR::Employee->select(-distinct => [qw/lastname firstname/]);

  sqlLike('SELECT DISTINCT lastname, firstname '.
	  'FROM t_employee' , [], 'distinct 2');


  $lst = HR::Employee->select(-columns => ['lastname', 
				       'COUNT(firstname) AS n_emp'],
			  -groupBy => [qw/lastname/],
			  -having  => [n_emp => {">=" => 2}],
			  -orderBy => 'n_emp DESC'
			 );


  sqlLike('SELECT lastname, COUNT(firstname) AS n_emp '.
	  'FROM t_employee '.
	  'GROUP BY lastname HAVING ((n_emp >= ?)) '.
	  'ORDER BY n_emp DESC', [2], 'group by');



  $lst = HR::Employee->select(-orderBy => [qw/+col1 -col2 +col3/]);
  sqlLike('SELECT * FROM t_employee ORDER BY col1 ASC, col2 DESC, col3 ASC', 
          [], '-orderBy prefixes');



  $emp2 = HR::Employee->fetch(123);
  sqlLike('SELECT * FROM t_employee WHERE (emp_id = ?)', 
          [123], 'fetch');

  $emp2 = HR::Employee->select(-fetch => 123);
  sqlLike('SELECT * FROM t_employee WHERE (emp_id = ?)', 
          [123], 'select(-fetch)');

  $emp2 = HR::Employee->fetch("");
  sqlLike('SELECT * FROM t_employee WHERE (emp_id = ?)', 
          [""], 'fetch (empty string)');


  $emp2 = HR::Employee->fetch(undef);
  sqlLike('SELECT * FROM t_employee WHERE (emp_id IS NULL)', 
          [], 'fetch (undef)');


  # successive calls to fetch_cached 
  $dbh->{mock_clear_history} = 1;
  $dbh->{mock_add_resultset} = [ [qw/foo bar/], [123, 456] ];
  $emp2 = HR::Employee->fetch_cached(123);
  is (@{$dbh->{mock_all_history}}, 1, "first fetch_cached : go to db");
  my $emp3 = HR::Employee->fetch_cached(123);
  is (@{$dbh->{mock_all_history}}, 1, "second fetch_cached : no db");
  is_deeply($emp3, {foo=>123, bar=>456}, "fetch_cached result");

  $emp->{emp_id} = 999;

  # method call should break without autoload
die_ok {$emp->emp_id};
  # now turn it on
  HR->Autoload(1);
is($emp->emp_id, 999, 'autoload schema');
  # turn it off again
  HR->Autoload(0);
die_ok {$emp->emp_id};
  # turn it on just for the Employee class
  HR::Employee->Autoload(1);
is($emp->emp_id, 999, 'autoload table');
  # turn it off again
  HR::Employee->Autoload(0);
die_ok {$emp->emp_id};



  $lst = $emp->activities;

  sqlLike('SELECT * ' .
	  'FROM t_activity ' .
	  "WHERE ( emp_id = ? )", [999], 'activities');


  $lst = $emp->activities([qw/d_begin d_end/]);

  sqlLike('SELECT d_begin, d_end ' .
	  'FROM t_activity ' .
	  "WHERE ( emp_id = ? )", [999], 'activities column list');


  $lst = $emp->activities({d_begin => {">=" => '2000-01-01'}});

  sqlLike('SELECT * ' .
	  'FROM t_activity ' .
	  "WHERE (d_begin >= ? AND emp_id = ?)", ['2000-01-01', 999], 
	    'activities where criteria');

  
  $lst = $emp->activities("d_begin AS db, d_end AS de", 
                          {}, 
                          [qw/d_begin d_end/]);

  sqlLike('SELECT d_begin AS db, d_end AS de ' .
	  'FROM t_activity ' .
	  "WHERE (emp_id = ?) ".
	  'ORDER BY d_begin, d_end', [999], 
	    'activities order by');

  $act = $emp->activities(-fetch => 123);
  sqlLike('SELECT * FROM t_activity WHERE (act_id = ? AND emp_id = ? )', 
          [123, 999], 'activities(-fetch)');


  # testing cached expanded values
  $emp->{activities} = "foo";
  is ($emp->activities, "foo", "cached expanded values");
  delete $emp->{activities};


  # unbless
 SKIP: {
    eval "use Acme::Damn; 1"
      or skip "Acme::Damn does not seem to be installed", 1;

    my $emp2 = HR::Employee->blessFromDB({
      emp_id => 999,
      activities => [map {HR::Activity->blessFromDB({foo => $_})} 1..3],
      spouse     => HR::Employee->blessFromDB({foo => 'spouse'}),
    });
    is_deeply(HR->unbless($emp2),
              {emp_id => 999, 
               spouse => {foo => 'spouse'},
               activities => [{foo => 1}, {foo => 2}, {foo => 3}]}, 
              "unbless");
  }


  # testing combination of where criteria
  my $statement = HR::Employee->activities(-where => {foo => [3, 4]});
  $act = $statement->bind($emp)
                   ->select(-where => {foo => [4, 5]});

  sqlLike('SELECT * FROM T_Activity '
          .  'WHERE ( emp_id = ? AND ( ((     (foo = ?) OR (foo = ?) )) '
          .                           'AND (( (foo = ?) OR (foo = ?) ))))',
          [999, 3, 4, 4, 5], "combined where");

  $statement = HR::Employee->activities(-where => [foo => "bar", bar => "foo"]);
  $act = $statement->bind($emp)
                   ->select(-where => [foobar => 123, barfoo => 456]);

  sqlLike('SELECT * FROM T_Activity '
          .  'WHERE ( (((      (( (foo = ?   ) OR (bar = ?   ))) '
          .              'AND (( (foobar = ?) OR (barfoo = ?))) ))) '
          .           'AND emp_id = ? )',
          [qw/bar foo 123 456 999/], "combined where, arrayrefs");


  SKIP : {
    $DBD::Mock::VERSION ne '1.37'
      or skip "DBD::Mock v1.37 is bugged (http://rt.cpan.org/Ticket/Display.html?id=37054)", 1;

    # select -resultAs => 'flat_arrayref'
    $dbh->{mock_clear_history} = 1;
    $dbh->{mock_add_resultset} = [ [qw/col1 col2/],
                                   [qw/foo1 foo2/], 
                                   [qw/bar1 bar2/] ];
    my $pairs = HR::Employee->select(-columns => [qw/col1 col2/],
                                     -resultAs => 'flat_arrayref');
    my %hash = @$pairs;

    # TEST BELOW DOES NOT WORK because DBD::Mock does not implement
    # bind_columns. So we put a stupid test instead
    # is_deeply(\%hash, {foo1 => 'foo2', bar1 => 'bar2'}, "resultAs => 'columns'");
    is_deeply(\%hash, {'' => undef}, "resultAs => 'columns'");
  }

  # insertion 
  $emp->insert_into_activities({d_begin =>'2000-01-01', d_end => '2000-02-02'});
  sqlLike('INSERT INTO t_activity (d_begin, d_end, emp_id) ' .
            'VALUES (?, ?, ?)', ['2000-01-01', '2000-02-02', 999],
	    'add_to_activities');


  # test cascaded inserts

  my $tree = {firstname  => "Johann Sebastian",  
              lastname   => "Bach",
              activities => [{d_begin  => '01.01.1707',
                              d_end    => '01.07.1720',
                              dpt_code => 'Maria-Barbara'},
                             {d_begin  => '01.12.1721',
                              d_end    => '18.07.1750',
                              dpt_code => 'Anna-Magdalena'}]};


  my $emp_id = HR::Employee->insert($tree);
  my $sql_insert_activity = 'INSERT INTO t_activity (d_begin, d_end, '
                          . 'dpt_code, emp_id) VALUES (?, ?, ?, ?)';

  sqlLike('INSERT INTO t_employee (firstname, lastname) VALUES (?, ?)',
          ["Johann Sebastian", "Bach"],
          $sql_insert_activity, 
          ['1707-01-01', '1720-07-01', 'Maria-Barbara', $emp_id],
          $sql_insert_activity, 
          ['1721-12-01', '1750-07-18', 'Anna-Magdalena', $emp_id],
          "cascaded insert");



  HR::MyView->select({c3 => 22});

  sqlLike('SELECT DISTINCT column1 AS c1, t2.column2 AS c2 ' .
	  'FROM Table1 AS t1 LEFT OUTER JOIN Table2 AS t2 '.
	  'ON t1.fk=t2.pk ' .
	  'WHERE (c1 = ? AND c2 LIKE ? AND c3 = ?)',
	     ['foo', 'bar%', 22], 'HR::MyView');

  my $view = HR->join(qw/Employee activities department/);
  $view->select("lastname, dpt_name", {gender => 'F'});

  sqlLike('SELECT lastname, dpt_name ' .
	  'FROM t_employee LEFT OUTER JOIN t_activity ' .
	  'ON t_employee.emp_id=t_activity.emp_id ' .		
	  'LEFT OUTER JOIN t_department ' .
	  'ON t_activity.dpt_id=t_department.dpt_id ' .
	  'WHERE (gender = ?)', ['F'], 'join');


  my $view2 = HR->join(qw/Employee <=> activities => department/);
  $view2->select("lastname, dpt_name", {gender => 'F'});

  sqlLike('SELECT lastname, dpt_name ' .
	  'FROM t_employee INNER JOIN t_activity ' .
	  'ON t_employee.emp_id=t_activity.emp_id ' .		
	  'LEFT OUTER JOIN t_department ' .
	  'ON t_activity.dpt_id=t_department.dpt_id ' .
	  'WHERE (gender = ?)', ['F'], 'join with explicit roles');




  my $view3 = HR->join(qw/Activity employee department/);
  $view3->select("lastname, dpt_name", {gender => 'F'});

  sqlLike('SELECT lastname, dpt_name ' .
	  'FROM t_activity INNER JOIN t_employee ' .
	  'ON t_activity.emp_id=t_employee.emp_id ' .
	  'INNER JOIN t_department ' .
	  'ON t_activity.dpt_id=t_department.dpt_id ' .
	  'WHERE (gender = ?)', ['F'], 'join with indirect role');


  die_ok {$emp->join(qw/activities foo/)};
  die_ok {$emp->join(qw/foo bar/)};

  $emp->join(qw/activities department/)
      ->select({gender => 'F'});

  sqlLike('SELECT * ' .
	  'FROM t_activity ' .
	  'INNER JOIN t_department ' .
	  'ON t_activity.dpt_id=t_department.dpt_id ' .
	  'WHERE (emp_id = ? AND gender = ?)', [999, 'F'], 
	  'join (instance method)');

  # table aliases
  HR->join(qw/Activity|act employee|emp department|dpt/)
    ->select(-columns => [qw/lastname dpt_name/], 
             -where   => {gender => 'F'});

  sqlLike('SELECT lastname, dpt_name ' .
	  'FROM t_activity AS act INNER JOIN t_employee AS emp ' .
	  'ON act.emp_id=emp.emp_id ' .
	  'INNER JOIN t_department AS dpt ' .
	  'ON act.dpt_id=dpt.dpt_id ' .
	  'WHERE (gender = ?)', ['F'], 'table aliases');

  # explicit sources
  HR->join(qw/Activity Activity.employee Activity.department/)
    ->select(-columns => [qw/lastname dpt_name/], 
             -where   => {gender => 'F'});

  sqlLike('SELECT lastname, dpt_name ' .
	  'FROM t_activity INNER JOIN t_employee ' .
	  'ON t_activity.emp_id=t_employee.emp_id ' .
	  'INNER JOIN t_department ' .
	  'ON t_activity.dpt_id=t_department.dpt_id ' .
	  'WHERE (gender = ?)', ['F'], 'explicit sources');


  # both table aliases and explicit sources
  HR->join(qw/Activity|act act.employee|emp act.department|dpt/)
    ->select(-columns => [qw/lastname dpt_name/], 
             -where   => {gender => 'F'});

  sqlLike('SELECT lastname, dpt_name ' .
	  'FROM t_activity AS act INNER JOIN t_employee AS emp ' .
	  'ON act.emp_id=emp.emp_id ' .
	  'INNER JOIN t_department AS dpt ' .
	  'ON act.dpt_id=dpt.dpt_id ' .
	  'WHERE (gender = ?)', ['F'], 
          'both table aliases and explicit sources');


  HR->join(qw/Department|dpt dpt.activities|act act.employee|emp/)
    ->select(-columns => [qw/lastname dpt_name/], 
             -where   => {gender => 'F'});
  sqlLike('SELECT lastname, dpt_name ' .
	  'FROM t_department AS dpt '.
	  'LEFT OUTER JOIN t_activity AS act ' .
	  'ON dpt.dpt_id=act.dpt_id ' .
          'LEFT OUTER JOIN t_employee AS emp ' .
	  'ON act.emp_id=emp.emp_id ' .
	  'WHERE (gender = ?)', ['F'], 
          'both table aliases and explicit sources, reversed');

  # column types on table and column aliases
  $dbh->{mock_clear_history} = 1;
  $dbh->{mock_add_resultset} = [ [qw/ln  db/],
                                 [qw/foo 2001-01-01/], 
                                 [qw/bar 2002-02-02/] ];
  $lst = HR->join(qw/Department|dpt dpt.activities|act act.employee|emp/)
           ->select(-columns => [qw/emp.lastname|ln emp.d_birth|db/], 
                    -where   => {gender => 'F'});
  sqlLike('SELECT emp.lastname AS ln, emp.d_birth AS db ' .
	  'FROM t_department AS dpt '.
	  'LEFT OUTER JOIN t_activity AS act ' .
	  'ON dpt.dpt_id=act.dpt_id ' .
          'LEFT OUTER JOIN t_employee AS emp ' .
	  'ON act.emp_id=emp.emp_id ' .
	  'WHERE (gender = ?)', ['F'], 
          'column types on table and column aliases (sql)');
  is($lst->[0]{db}, "01.01.2001", "fromDB handler on table and column alias");




  # stepwise statement prepare/execute
  $statement = HR::Employee->join(qw/activities department/);
  $statement->refine(-where => {gender => 'F'});
  $statement->prepare;
  die_ok {$statement->next}; # statement is not executed yet
  my $row = $statement->execute($emp)->next;
  sqlLike('SELECT * ' .
	  'FROM t_activity ' .
	  'INNER JOIN t_department ' .
	  'ON t_activity.dpt_id=t_department.dpt_id ' .
	  'WHERE (emp_id = ? AND gender = ?)', [999, 'F'], 
	  'statement prepare/execute');



  # many-to-many association

  HR->Association([qw/Employee   employees   * activities employee/],
			[qw/Department departments * activities department/]);

  my $dpts = $emp->departments(-where =>{gender => 'F'});
  sqlLike('SELECT * ' .
	  'FROM t_activity ' .
	  'INNER JOIN t_department ' .
	  'ON t_activity.dpt_id=t_department.dpt_id ' .
	  'WHERE (emp_id = ? AND gender = ?)', [999, 'F'], 
	  'N-to-N Association ');


  my $dpt = bless {dpt_id => 123}, 'HR::Department';
  my $empls = $dpt->employees;
  sqlLike('SELECT * ' .
	  'FROM t_activity ' .
	  'INNER JOIN t_employee ' .
	  'ON t_activity.emp_id=t_employee.emp_id ' .
	  'WHERE (dpt_id = ?)', [123], 
	  'N-to-N Association 2 ');




  HR::Employee->update(999, {firstname => 'toto', 
			 d_modif => '02.09.2005',
			 d_birth => '01.01.1950',
			 last_login => '01.09.2005'});

  sqlLike('UPDATE t_employee SET d_birth = ?, firstname = ? '.
	  'WHERE (emp_id = ?)', ['1950-01-01', 'toto', 999], 'update');


  HR::Employee->update(     {firstname => 'toto', 
			 d_modif => '02.09.2005',
			 d_birth => '01.01.1950',
			 last_login => '01.09.2005',
			 emp_id => 999});

  sqlLike('UPDATE t_employee SET d_birth = ?, firstname = ? '.
	  'WHERE (emp_id = ?)', ['1950-01-01', 'toto', 999], 'update2');


  $emp->{firstname}  = 'toto'; 
  $emp->{d_modif}    = '02.09.2005';
  $emp->{d_birth}    = '01.01.1950';
  $emp->{last_login} = '01.09.2005';

  my %emp2 = %$emp;

  $emp->update;

  sqlLike('UPDATE t_employee SET d_birth = ?, firstname = ?, lastname = ? '.
	  'WHERE (emp_id = ?)', 
	  ['1950-01-01', 'toto', 'Bodin De Boismortier', 999], 'update3');


  HR->AutoUpdateColumns( last_modif => 
    sub{"someUser, someTime"}
  );
  HR::Employee->update(\%emp2);
  sqlLike('UPDATE t_employee SET d_birth = ?, firstname = ?, ' .
	    'last_modif = ?, lastname = ? WHERE (emp_id = ?)', 
	  ['1950-01-01', 'toto', "someUser, someTime", 
	   'Bodin De Boismortier', 999], 'autoUpdate');


  HR->AutoInsertColumns( created_by => 
    sub{"firstUser, firstTime"}
  );

  HR::Employee->insert({firstname => "Felix",
                    lastname  => "Mendelssohn"});

  sqlLike('INSERT INTO t_employee (created_by, firstname, last_modif, lastname) ' .
            'VALUES (?, ?, ?, ?)',
	  ['firstUser, firstTime', 'Felix', 'someUser, someTime', 'Mendelssohn'],
          'autoUpdate / insert');


  $emp = HR::Employee->blessFromDB({emp_id => 999});
  $emp->delete;
  sqlLike('DELETE FROM t_employee '.
	  'WHERE (emp_id = ?)', [999], 'delete');


  $emp = HR::Employee->blessFromDB({emp_id => 999, spouse_id => 888});
  my $emp_spouse = $emp->spouse;
  sqlLike('SELECT * ' .
	  'FROM t_employee ' .
	  "WHERE ( emp_id = ? )", [888], 'spouse self-ref assoc.');


  # testing -preExec / -postExec
  my %check_callbacks;
  HR::Employee->select(-where => {foo=>'bar'},
		   -preExec => sub {$check_callbacks{pre} = "was called"},
		   -postExec => sub {$check_callbacks{post} = "was called"},);
  is_deeply(\%check_callbacks, {pre =>"was called", 
				post => "was called" }, 'select, pre/post callbacks');

  %check_callbacks = ();
  HR::Employee->fetch(1234, {-preExec => sub {$check_callbacks{pre} = "was called"},
			 -postExec => sub {$check_callbacks{post} = "was called"}});
  is_deeply(\%check_callbacks, {pre =>"was called", 
				post => "was called" }, 'fetch, pre/post callbacks');


  # testing transactions 

  my $ok_trans       = sub { return "scalar transaction OK"     };
  my $ok_trans_array = sub { return qw/array transaction OK/    };
  my $fail_trans     = sub { die "failed transaction"           };
  my $nested_1       = sub { HR->doTransaction($ok_trans) };
  my $nested_many    = sub {
    my $r1 = HR->doTransaction($nested_1);
    my @r2 = HR->doTransaction($ok_trans_array);
    return ($r1, @r2);
  };

  is (HR->doTransaction($ok_trans), 
      "scalar transaction OK",
      "scalar transaction");
  sqlLike('BEGIN WORK', [], 
          'COMMIT',     [], "scalar transaction commit");

  is_deeply ([HR->doTransaction($ok_trans_array)],
             [qw/array transaction OK/],
             "array transaction");
  sqlLike('BEGIN WORK', [], 
          'COMMIT',     [], "array transaction commit");

  die_ok {HR->doTransaction($fail_trans)};
  sqlLike('BEGIN WORK', [], 
          'ROLLBACK',   [], "fail transaction rollback");

  $dbh->do('FAKE SQL, HISTORY MARKER');
  is_deeply ([HR->doTransaction($nested_many)],
             ["scalar transaction OK", qw/array transaction OK/],
             "nested transaction");
  sqlLike('FAKE SQL, HISTORY MARKER', [],
          'BEGIN WORK', [], 
          'COMMIT',     [], "nested transaction commit");


  # nested transactions on two different databases
  $dbh->{private_id} = "dbh1";
  my $other_dbh = DBI->connect('DBI:Mock:', '', '', 
                               {private_id => "dbh2", RaiseError => 1});

  $emp_id = 66;
  my $tell_dbh_id = sub {my $db_id = HR->dbh->{private_id};
                         HR::Employee->update({emp_id => $emp_id++, name => $db_id});
                         return "transaction on $db_id" };


  my $nested_change_dbh = sub {
    my $r1 = HR->doTransaction($tell_dbh_id);
    my $r2 = HR->doTransaction($tell_dbh_id, $other_dbh);
    my $r3 = HR->doTransaction($tell_dbh_id);
    return ($r1, $r2, $r3);
  };

  $dbh      ->do('FAKE SQL, BEFORE TRANSACTION');
  $other_dbh->do('FAKE SQL, BEFORE TRANSACTION');

  is_deeply ([HR->doTransaction($nested_change_dbh)],
             ["transaction on dbh1", 
              "transaction on dbh2", 
              "transaction on dbh1"],
              "nested transaction, change dbh");


  my $upd = 'UPDATE T_Employee SET last_modif = ?, name = ? WHERE ( emp_id = ? )';
  my $last_modif = 'someUser, someTime';

  sqlLike('FAKE SQL, BEFORE TRANSACTION', [],
          'BEGIN WORK', [], 
          $upd, [$last_modif, "dbh1", 66], 
          $upd, [$last_modif, "dbh1", 68], 
          'COMMIT',     [], "nested transaction on dbh1");


  $dbh = $other_dbh;
  sqlLike('FAKE SQL, BEFORE TRANSACTION', [],
          'BEGIN WORK', [], 
          $upd, [$last_modif, "dbh2", 67], 
          'COMMIT',     [], "nested transaction on dbh2");

} # END OF SKIP BLOCK



__END__

TODO: 

hasInvalidFields
expand
autoExpand
MethodFromRoles
document the tests !!


