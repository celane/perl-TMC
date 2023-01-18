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
