use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'DBIx::DataModel',
    license             => 'perl',
    dist_author         => 'Laurent Dami <laurent.dami AT etat.ge.ch>',
    dist_version_from   => 'lib/DBIx/DataModel.pm',
    requires => {
        'Test::More'    => 0,
	'Carp'          => 0,
	'DBI'           => 0,
	'SQL::Abstract' => 0,
    },
    add_to_cleanup      => [ 'DBIx-DataModel-*' ],
);

$builder->create_build_script();



