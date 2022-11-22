
# create Deb386.exe & ResWP.exe

odir = build

ALL: $(odir) $(odir)\Deb386.exe $(odir)\Deb386w.exe $(odir)\ResWP.exe

$(odir):
	@mkdir $(odir)

$(odir)\Deb386.exe: Deb386.asm $(odir)\DebugR.bin Makefile dprintfr.inc dprintfp.inc vioout.inc
	@jwasm -nologo -mz -Sg -DBINDIR=$(odir) -Fl$* -Fo$* -Sg Deb386.asm

$(odir)\Deb386w.exe: Deb386.asm $(odir)\DebugR.bin Makefile dprintfr.inc dprintfp.inc vioout.inc
	@jwasm -nologo -mz -Sg -DVIOOUT=1 -DKBDIN=1 -DBINDIR=$(odir) -Fl$* -Fo$* -Sg Deb386.asm

$(odir)\DebugR.bin: \projects\debug\build\debugR.bin
	@cd $(odir)
	@copy \projects\debug\build\debugR.bin
	@cd ..

$(odir)\ResWP.exe: ResWP.asm
	@jwasm -mz -Fl$* -Fo$* ResWP.asm

clean:
	@del $(odir)\Deb386.exe
	@del $(odir)\ResWP.exe
	@del $(odir)\*.bin
	@del $(odir)\*.lst
