#!/usr/bin/perl
use ExtUtils::H2PM;

module 'TMC::constants';
use_export;

if (-e '/usr/include/linux/ioctl.h') {
    include 'linux/ioctl.h';
} else {
    include 'sys/ioctl.h';
}
include 'linux/usb/tmc.h';
include 'linux/usbdevice_fs.h';

constant "USBTMC_IOCTL_CLEAR";
constant "USBTMC488_IOCTL_READ_STB";
constant "USBDEVFS_RESET";
write_output $ARGV[0];

open(P,"<$ARGV[0]") || die "unable to open $ARGV[0] for reading";
my @lines = (<P>);
close(P);

open(P,">ARGV[0]") || die "unable to open $ARGV[0] for writing";
foreach (@lines) {
    last if /^\s*1;\s*/;
    print P $_;
}
print P "use vars qw(\@ISA \@EXPORT);\n";
print P "BEGIN {\n";
print P "     require Exporter;\n";
print P "     \@ISA = qw(Exporter);\n";
print P "\};\n";
print P "1;\n";
close(P);

