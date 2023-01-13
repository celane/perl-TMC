use 5.006;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;
use Data::Dumper;
    


WriteMakefile(
    NAME             => 'TMC',
    AUTHOR           => q{Charles Lane <lane@duphy4.physics.drexel.edu>},
    VERSION_FROM     => 'lib/TMC.pm',
    ABSTRACT_FROM    => 'lib/TMC.pm',
    LICENSE          => 'Artistic_2_0',
    PL_FILES         => {},
    MIN_PERL_VERSION => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
	
    PREREQ_PM => {
        #'ABC'              => 1.6,
        #'Foo::Bar::Module' => 5.0401,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'TMC-*' },
    # h2ph -d lib -a /usr/include/linux/usb/tmc.h
);

package MY;

sub postamble {
    my $text = 
	"install :: INSTALL_PH\n".
	"INSTALL_PH:\n". 
	"\th2ph -d \$(INSTALLVENDORLIB) -a linux/usb/tmc.h\n".
	"\th2ph -d \$(INSTALLVENDORLIB) -a linux/ioctl.h\n".
	"\th2ph -d \$(INSTALLVENDORLIB) -a linux/usbdevice_fs.h\n";
    return $text;
}

