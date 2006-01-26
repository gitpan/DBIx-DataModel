use 5.008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'DBIx::DataModel',
    'VERSION_FROM'	=> 'DataModel.pm', # finds $VERSION
    'PREREQ_PM'		=> {Carp => 0,
			    DBI => 0,
			    SQL::Abstract => 0}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'DataModel.pm', # retrieve abstract from module
       AUTHOR     => 'Laurent Dami <laurent.dami AT etat.ge.ch>') : ()),
);
