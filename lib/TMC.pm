package TMC;

use 5.006;
use Config;
use strict;
use warnings FATAL => 'all';
no strict qw(subs);
use Fcntl qw(O_RDWR);
use filetest 'access'; # for acl permissions, like on usbtmc device
use FileHandle;
use Time::HiRes qw( usleep );
use Carp;
use TMC::constants;

=head1 NAME

TMC - Perl interface to usbtmc test and measurement

=head1 VERSION

Version 0.07

=cut

our $VERSION = '0.07';
our $DEBUG = 0;
our $BASEDEV = '/dev/usbtmc';
our $MODULE = 'usbtmc';
our $MAXBUF = 1024;
our $DRIVER_TIMEOUT = 5000;  # millisec, module default
our $DRIVER_MAXBUF = 4096;   # module default
# NOTE: devices may have smaller max buffer

# the ioctl includes need to have 'sizeof' definitions, which
# h2ph *does*not*provide*  So we roll our own
our (%sizeof);
{
    # sizes needed for ioctl calls

    no warnings qw(redefine misc);

    %sizeof = (
	'char' => $Config{charsize},
	'double' => $Config{doublesize},
	'int' => $Config{intsize},
	'long' => $Config{longsize},
	'short' => $Config{shortsize},
	'long double' => $Config{longdblsize},
	'long long' => $Config{longlongsize},
	'ptr' => $Config{ptrsize},
	'__uint8_t' => $Config{u8size},
	'__uint16_t' => $Config{u16size},
	'__uint32_t' => $Config{u32size},
	'__uint64_t' => $Config{u64size},
	'int8_t' => $Config{i8size},
	'int16_t' => $Config{i16size},
	'int32_t' => $Config{i32size},
	'int64_t' => $Config{i64size},
	'unsigned int' => $sizeof{int},
	'unsigned char' => $sizeof{char},
	'unsigned long' => $sizeof{long},
	'unsigned short' => $sizeof{short},
	);
}

#  
# please note: with the usbtmc kernel module on Linux
# kernel 4.7.4 (and some prior versions) the module has a
# built-in unchangable timeout of 5 seconds. So the only
# way to deal with timeouts is "try the read N times, and see
# if there is a response".  It also makes no sense to "sleep between
# the write and read" of a query, since one might as well do
# the read and get a (potentially) faster result.

# So:
# wait_query is ignored
# brutal only has the effect of not throwing errors on read timeouts
# timeout is rounded to 5 second interval, to give the number of reads
# that are tried

# kernel <4.20 the default buffer size was 2048; later
# kernel versions have a default buffer size of 4096, but
# for some reason, tests with a TDS2024B show that the
# buffering is 1024. It might be at the 'device' end. 

# the reason this matters is in how one determines that a usbtmc
# 'read' is complete, because many of the queries do not return
# a completely deterministic number of bytes; so you have to request
# with a larger number, and you get less. Is that because the read
# is split up in multiple buffers (with more remaining to be read),
# or did you reach the end? Reading data that isn't there will give
# a timeout error, or hang the interface.

# there are four hints for 'reached the end':
#   the bytes returned is less than a full buffer
#   the last byte of the returned buffer is '\n' (LF)
#   the EOM bit is set in bmTransferAttributes (bit 0) (4.20+ only)
#   the device has MAV bit set in STB when 'more data available'. 
#

# the STB can be read by ioctl USBTMC488_IOCTL_READ_STB  (>=4.6)
# but it's only really useful if there is a USB 'interrupt'
# endpoint for retrieving STB in a side-channel from the main
# BULK-in data channel, otherwise it just gets queued to the end
# of the other data. (>=4.6 has this)

# all of this stuff is relevant when binary data is read from the
# device, because you can't really trust that a \n at the end of
# a block of data means that it's the end, or just an unfortunate
# coincidence.

# the EOM bit is faster to deal with, no extra USB i/o is
# requred, but it does need the requested buffer to be >=
# the internal buffer, to make sure that that one is getting
# the full buffer for which the EOM bit applies (instead of the
# first part of a buffer that is being transfered to user in
# smaller parts).

# so, going to ignore the user read_length for performing
# the usb i/o, and only apply it when deciding what to
# store for transfer to user. 

# going with the ioctl "*STB?" version for now, since it
# seems more likely to work without weird failure modes.

=head1 SYNOPSIS


    use TMC;

    my $foo = TMC->new();
    ...

Routines for communicating with USB devices
that use the usbtmc driver

$tmc = new TMC(
    MANUFACTURE => $mfr,
    PRODUCT=> $prod,
    SERIAL=>$serial
    );

Note that "mfr", "prod" and "serial" can use shell type
wildcards:  $prod = 'TDS*2024*' matches 'TDS2024B', 'TDS 2024', etc.

$tmc->Tx("string to send");

$string = $tmc->Rx();

$TMC::DEBUG = 1   connection debugging
$TMC::DEBUG = 2   ..data i/o debug also

Note that the Linux usbtmc driver has a hard-coded timeout of
5000ms, so timeouts can result when sending large chunks of
data, or if commands take a long time to complete. It may require
putting "sleep" commands in code in order to work around
this issue. See the included programs ScreenCap2024 and
Set2024Config for examples of workarounds. 

When timeouts do occur, it sometimes leaves the /dev/usbtmc*
device in a non-responsive state. The included TMCreset program
searches for TMC devices and resets their USB ports to get them
working again. 

Note that the /dev/usbtmc* device needs to have r/w access. If
a port needs to be reset, then the /dev/bus/usb/BUS/NUM needs
write access. 

=cut



#BEGIN {
    
    # "sys/ioctl.ph" throws a warning about FORTIFY_SOURCE, but
    # this alternate is (perhaps?) not present on all systems,
    # so do a workaround
    if ( !defined( eval('require "linux/ioctl.ph";') ) ) {
        require "sys/ioctl.ph";
    }
    require "linux/usb/tmc.ph";

    require Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT_OK = qw(Tx Rx);
    our %EXPORT_TAGS = (
	':all' => [ qw(Tx Rx) ]
	);
#}





=head1 SUBROUTINES/METHODS

=head2 new(parameters)   

    my $tmc = TMC:::new(
       MANUFACTURE => manufacturer
       PRODUCT=>product,
       SERIAL=>serial,
       TIMEOUT=> timeout_sec [def 5s],
       BUFLEN=> buffer_length [def 1024],
       NO_LF => 0|1 strip LF from end [def: 0],
    );

    set up i/o...connection occurs on first Tx or Rx
    The "mfr/prod/serial" match comes from a *INQ? that
    is done while trying to find the appropriate USB port to 
    use. 

=cut

sub new {
    my $class = shift;
    my $opts = {@_};

    my $self = {};

    my $mfr = '*';
    $mfr  = $opts->{MANUFACTURE} if exists($opts->{MANUFACTURE});
    my $prod = '*';
    $prod  = $opts->{PRODUCT} if exists($opts->{PRODUCT});
    my $sn = '*';
    $sn  = $opts->{SERIAL} if exists($opts->{SERIAL});
    my $timeout = $DRIVER_TIMEOUT;
    $timeout = $opts->{TIMEOUT} if exists($opts->{TIMEOUT});
    my $buflen = $DRIVER_MAXBUF;
    $buflen = $opts->{BUFLEN} if exists($opts->{BUFLEN});
    my $nolf = 0;
    $nolf = $opts->{NO_LF} if exists($opts->{NO_LF});

    $self->{DEBUG} = $DEBUG;
    $self->{DEBUG} = $opts->{DEBUG} if exists $opts->{DEBUG};
                                    
    $self->{MANUFACTURE} = _glob2pat($mfr);
    $self->{PRODUCT} = _glob2pat($prod);
    $self->{SERIAL} = _glob2pat($sn);
    $self->{TIMEOUT} = int($timeout);
    $self->{BUFLEN} = int($buflen);
    $self->{NO_LF} = $nolf;

                                     
    $self->{CONNECTED} = 0;
   

    bless($self,$class);
    return $self;
}

sub _connect 
{
    my $self = shift;
    local *X;

    return 1 if $self->{CONNECTED};

    $self->{DRIVER_TIMEOUT} = $DRIVER_TIMEOUT;
    $self->{DRIVER_MAXBUF} = $DRIVER_MAXBUF;
    
    # check if usbtmc module is loaded...
    #     one-line header from driver, then one line/tmc device
    ####
    # first see if we can use sysfs
    #
    if (-e '/sys/module' && -d '/sys/module' &&
        -d '/sys/module/usbtmc') {
        if (-e '/sys/module/usbtmc/version') {
            $self->{MODVERSION} = `cat /sys/module/usbtmc/version`;
        }
        if (-e '/sys/module/usbtmc/parameters/usb_timeout') {
            $self->{DRIVER_TIMEOUT} =
                `cat /sys/module/usbtmc/parameters/usb_timeout`;
        }
        if (-e '/sys/module/usbtmc/parameters/io_buffer_size') {
            $self->{DRIVER_BUFSIZE} =
                `cat /sys/module/usbtmc/parameters/io_buffer_size`;
        }
    } else {
        open(X,"/sbin/lsmod|") || croak("unable to lsmod");

        $_ = <X>;
        my $got = 0;
        while(<X>) {
            next unless /^$MODULE\s/;
            $got++;
            last;
        }
        close(X);
        croak("module $MODULE not loaded") unless $got;
       
        # check version of usbtmc module
        
        open(X, "modinfo usbtmc|") || croak("unable to modinfo usbtmc");

        while (<X>) {
            next unless /^version:\s(\d[\w\.]+)\s*$/i;
            $self->{MODVERSION} = $1;
            last;
        }
        close(X);
    }
    carp("usbtmc module version unknown (pre 2023?); might be missing capabilities")
        unless exists($self->{MODVERSION});
    
#
#   check connected TMC devices
#
    my $dev;
    my $fdev;
    my $inq;
    my $id = -1;
    my $got = 0;

    my $io = new FileHandle;

    while ($id++ < 100) {
	$dev = "${BASEDEV}${id}";
	last unless -e $dev && -r $dev && -w $dev && -c $dev ;

	sysopen($io,$dev,O_RDWR) ||
	    croak("error opening $dev for r/w");
	binmode($io);
	my $iss;
	


#	open(X,"+<$dev") || croak("failed to open $dev for r/w");
#TEKTRONIX,TDS 2024B,C031234,CF:91.1CT FV:v22.11
	$iss = ioctl($io,
		     USBTMC_IOCTL_CLEAR,0);
	croak("error clearing comm iss=$iss $!") unless $iss;


	sleep(1);
	
        my $nw = syswrite($io,"*IDN?\n",6,0);
	if (!defined($nw) || $nw <= 0) {
	    croak("error writing to $dev, $!");
	}

	usleep(1000);
	
	my $inq;
	my $j = 0;
	while (1) {
	    $nw = sysread($io,$inq,$MAXBUF,$j);
	    if (!defined($nw) || $nw <= 0) {
		croak("error reading from $dev, $!");
	    }
	    last if $nw < $MAXBUF || substr($inq,-1,1) eq "\n";
	    $j += $nw;
	}
       
	chomp($inq);
	my ($mfr,$prod,$serial) = split(',',$inq);
	next unless $mfr =~ /$self->{MANUFACTURE}/i;
	next unless $prod =~ /$self->{PRODUCT}/i;
	next unless $serial =~ /$self->{SERIAL}/i;
	$got++;
	$fdev = $dev;
	close($io) || croak("close failed $!");
    }
	    
    croak("could not find specified USBTMC device") if $got == 0;
    croak("USBTMC device spec matches multiple devices") if $got > 1;
    $self->{DEV} = $fdev;
    $self->{IDN} = $inq;

#

#    $iss = ioctl($self->{IO},
#                 &USBTMC_IOCTL_SET_ATTRIBUTE,
#                 _PackAttr(&USBTMC_ATTRIB_READ_MODE,
#                          &USBTMC_ATTRIB_VAL_FREAD)
#                 );
 
#    croak("error setting read_mode iss=$iss $!") unless $iss;


#    $iss = ioctl($self->{IO},
#                 &USBTMC_IOCTL_SET_ATTRIBUTE,
#                 _PackAttr(&USBTMC_ATTRIB_TIMEOUT,10));
                 
#    croak("error setting timeout iss=$iss $!") unless $iss;
    sysopen($io,$fdev,O_RDWR) ||
	croak("error opening $dev for r/w");
    binmode($io);

    $self->{IO} = $io;
    $self->{CONNECTED} = 1;
    return 1;
}


# process 'glob' shell-like wildcard string to make it
# something that Perl can use as a RE
sub _glob2pat {
    my $globstr = shift;
    my %patmap = (
        '*' => '.*',
        '?' => '.',
        '[' => '[',
        ']' => ']',
    );
    $globstr =~ s{(.)} { $patmap{$1} || "\Q$1" }ge;
    return '^' . $globstr . '$';
}




=head2 Tx 
       $tmc->Tx(string)
       send string to connected device

=cut

sub Tx 
{
    my $self = shift;
    my $s = shift;
    $self->_connect() || return 0;

    chomp($s);
    $s .= "\n";
    my $n = length($s);
    my $j = 0;
    my $nw;

    while ($j < $n) {
	my $block = $self->{BUFLEN};
	$block = $n if $block > $n;
        $nw = syswrite($self->{IO},$s,$block,$j);
        print "Tx n=$block j=$j written=",
        (defined($nw)?$nw:'undef')," '",
        substr($s,$j,($n-$j < 10 ? $n-$j: 10)),"'\n"
            if $self->{DEBUG} > 1;
        
        if (!defined($nw) || $nw < 1) {
            carp("USBTMC::Tx error writing $!");
            return 0;
        }
        $j += $nw;
    }
    return 1;
}

=head2 Rx
    my $string = $tmc->Rx([[length],timeout]);
    my $string = $tmc->Rx(BUFLEN=>length,TIMEOUT=>timeout,NO_LF=>0);
    read string from device 

    timeout is in milliseconds. 

    Note that this will hang/timeout if the device hasn't been
    told to send something.

=cut
    
sub Rx 
{
    my $self = shift;
    $self->_connect() || return undef;

    my $args = undef;
    if (ref $_[0] eq 'HASH') {
        $args = shift;
    } else {
        $args = {@_};
    }
    my $maxbuf = $args->{'BUFLEN'} || $self->{'BUFLEN'};
    my $timeout = $args->{'TIMEOUT'} || $self->{'TIMEOUT'};
    my $no_LF = $args->{'NO_LF'} || $self->{'NO_LF'};

    my $result = '';
    my $iss;
    my $tries = 0;
    
    while (1) {
        my $buf;
        $iss = sysread($self->{IO},$buf,$maxbuf);
        if ($self->{DEBUG} > 1) {
            print "Rx n=",(defined($iss)?$iss:'undef')," '";
            print substr($buf,0,$iss) if defined($iss);
            print "'\n";
        }
        if (!defined($iss)) {
            if ($! =~ /timed?\s*out/i) {
                print "timeout $!\n" if $self->{DEBUG}; 
                $tries++;
                next if $timeout <= 0;
                next if $timeout >= $tries * $DRIVER_TIMEOUT;
                carp("error $!");
                return '';
            } else {
                carp("usbtmc read error $!");
            }
        }
        $result .= $buf;
        last unless $self->get_stb(0x10);
    }
    $result =~ s/\n$// unless $no_LF;
    return $result;
}

# read the status register via ioctl/usb interrupt endpoint

# can select a single bit for true/false return:
# ex: get_stb($conn, STB_MAV);

sub get_stb {
    my $self = shift;
    my $bitmask = shift;
    $self->_connect() || return undef;
    
    my $stb = ' ';
    my $iss = ioctl($self->{IO}, USBTMC488_IOCTL_READ_STB, $stb);
    if (!$iss) {
        carp("error doing stb $!");
        return 0;
    }
    $stb = unpack('C',$stb);
    printf("STB=0b%08b\n",$stb) if $self->{DEBUG};
    return ($stb & $bitmask) != 0 if defined $bitmask;
    return $stb;
}
    
    

=head1 AUTHOR

Charles Lane, C<< <lane at dchooz.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-tmc at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=TMC>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc TMC


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=TMC>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/TMC>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/TMC>

=item * Search CPAN

L<http://search.cpan.org/dist/TMC/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2016 Charles Lane.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of TMC
