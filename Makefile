
# create Deb386.exe, Deb386w.exe & ResWP.exe.
# path for DebugR probably must be adjusted.

odir = build
DEBUGRDIR = \projects\debug\build

ALL: $(odir) $(odir)\Deb386.exe $(odir)\Deb386w.exe $(odir)\ResWP.exe

$(odir):
	@mkdir $(odir)

$(odir)\Deb386.exe: Deb386.asm $(odir)\DebugR.bin Makefile dprintfr.inc dprintfp.inc vioout.inc
	@jwasm -nologo -mz -Sg -DBINDIR=$(odir) -Fl$* -Fo$* Deb386.asm

$(odir)\Deb386w.exe: Deb386.asm $(odir)\DebugR.bin Makefile dprintfr.inc dprintfp.inc vioout.inc kbdinp.inc
#	@jwasm -nologo -mz -Sg -DVIOOUT=1 -DKBDIN=1 -DBINDIR=$(odir) -Fl$* -Fo$* Deb386.asm
	@jwasm -nologo -DKEYS=KBD_GE -mz -Sg -DVIOOUT=1 -DKBDIN=1 -DBINDIR=$(odir) -Fl$* -Fo$* Deb386.asm

$(odir)\DebugR.bin: $(DEBUGRDIR)\DebugR.bin
	@cd $(odir)
	@copy $(DEBUGRDIR)\DebugR.bin
	@cd ..

$(odir)\ResWP.exe: ResWP.asm
	@jwasm -mz -Fl$* -Fo$* ResWP.asm

clean:
	@del $(odir)\Deb386.exe
	@del $(odir)\ResWP.exe
	@del $(odir)\*.bin
	@del $(odir)\*.lst
