# perl-TMC
perl code for talking to usbtmc (usb 'test and measurement' devices), including code for Tektronix TDS2024 oscillocopes.


TMC

TMC interface module for usbtmc connections...this is
for the "more modern (post 2008?)" usbtmc driver. 

INSTALLATION

To install this module, run the following commands:

	perl Makefile.PL
	make
	make test
	make install

SUPPORT AND DOCUMENTATION

After installing, you can find documentation for this module with the
perldoc command.

    perldoc TMC

There are several perl scripts in the "programs/" directory, for
getting/setting the scope configuration, for doing a screen
capture, and for reading waveforms when the scope is triggered
(or self-triggering).  And for resetting the usb port after a 
usbtmc timout: TMCreset. 

Note that Take2024Waveforms is now set up so that it can run in the
background and respond rationally to control-C or "kill" signals.

Just do "Take2024Waveform ... "
^Z to "stop"
bg to let it run in background
fg to bring to foreground
^C to stop aquisition

Or do the
   Take2024Waveforms ... &
   (prints 'pid' #)

kill 'pid'




