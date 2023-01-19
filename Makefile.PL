use 5.006;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;
use Data::Dumper;
    

WriteMakefile(
    NAME             => 'TMC',
    AUTHOR           => q{Charles Lane <lane@dchooz.org>},
    VERSION_FROM     => 'lib/TMC.pm',
    ABSTRACT_FROM    => 'lib/TMC.pm',
    LICENSE          => 'GPL_3',
    PL_FILES         => {
        'lib/TMC/constants.pm.PL' => 'lib/TMC/constants.pm',
    },
#    PM => {},
    MIN_PERL_VERSION => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
        'ExtUtils::H2PM' => 0,
    },
	
    PREREQ_PM => {
        #'ABC'              => 1.6,
        #'Foo::Bar::Module' => 5.0401,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { },
);

# package MY;
# 
# sub postamble {
#     my $text = 
# 	"config :: GENERATE_CONSTANTS generate_constants.pl\n".
# 	"GENERATE_CONSTANTS:\n". 
#         "\t$(PERL) generate_constants.pl lib/TMC/constants.pm";
#         return $text;
# }
# 
