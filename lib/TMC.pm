package TMC;

use 5.006;
use strict;
use warnings FATAL => 'all';
no strict qw(subs);
use Fcntl qw(O_RDWR);
use filetest 'access'; # for acl permissions, like on usbtmc device
use FileHandle;
use Time::HiRes qw( usleep );
use Carp;

=head1 NAME

TMC - Perl interface to usbtmc test and measurement

=head1 VERSION

Version 0.06

=cut

our $VERSION = '0.06';
our $DEBUG = 0;
our $BASEDEV = '/dev/usbtmc';
our $MODULE = 'usbtmc';
our $MAXBUF = 1024;



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


BEGIN {
    require 'linux/ioctl.ph';
    require 'linux/usb/tmc.ph'; 

    require Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT_OK = qw(Tx Rx);
    our %EXPORT_TAGS = (
	':all' => [ qw(Tx Rx) ]
	);
}





=head1 SUBROUTINES/METHODS

=head2 new(parameters)   

    my $tmc = TMC:::new(
       MANUFACTURE => manufacturer
       PRODUCT=>product,
       SERIAL=>serial
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

    

    $self->{MANUFACTURE} = _glob2pat($mfr);
    $self->{PRODUCT} = _glob2pat($prod);
    $self->{SERIAL} = _glob2pat($sn);
    $self->{CONNECTED} = 0;
   

    bless($self,$class);
    return $self;
}

sub _connect 
{
    my $self = shift;
    local *X;

    return 1 if $self->{CONNECTED};

#   check if usbtmc module is loaded...
#     one-line header from driver, then one line/tmc device
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


#
#   check connected TMC devices
#
    my $dev;
    my $fdev;
    my $inq;
    my $id = -1;
    $got = 0;

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
		     &USBTMC_IOCTL_CLEAR,0);
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
	my $block = $MAXBUF;
	$block = $n if $block > $n;
        $nw = syswrite($self->{IO},$s,$block,$j);
        print "Tx n=$block j=$j written=",
        (defined($nw)?$nw:'undef')," '",
        substr($s,$j,($n-$j < 10 ? $n-$j: 10)),"'\n"
            if $DEBUG > 1;
        
        if (!defined($nw) || $nw < 1) {
            carp("USBTMC::Tx error writing $!");
            return 0;
        }
        $j += $nw;
    }
    return 1;
}

=head2 Rx
    my $string = $tmc->Rx();
    read string from device 

    Note that this will hang/timeout if the device hasn't been
    told to send something.

=cut
    
sub Rx 
{
    my $self = shift;
    $self->_connect() || return undef;
    
    my $s;
    my $j = 0;
    my $n;
    while (1) {
        $n = sysread($self->{IO},$s,$MAXBUF,$j);
        print "Rx n=",
        (defined($n)?$n:'undef')," '" if $DEBUG > 1;
        print substr($s,$j,($n<10? $n:10)) if defined($n) && $DEBUG > 1;
        print "'\n" if $DEBUG > 1;
        if (!defined($n)) {
            carp("error $!");
            sleep(1);      
	    next;
        }
        last if $n < $MAXBUF || substr($s,-1,1) eq "\n";
        $j += $n;
    }
    return $s;
}




    
    

=head1 AUTHOR

Charles Lane, C<< <lane at duphy4.physics.drexel.edu> >>

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
