#!perl -T

use Test::More tests => 3;

BEGIN {
	use_ok( 'DBIx::DataModel' );
	use_ok( 'DBIx::DataModel::Schema' );
	use_ok( 'DBIx::DataModel::Table' );
}

diag( "Testing DBIx::DataModel $DBIx::DataModel::VERSION, Perl $], $^X" );
