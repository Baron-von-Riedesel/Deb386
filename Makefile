
# create Deb386.exe & ResWP.exe.
#
# path for DebugR (DEBUGRDIR) probably must be adjusted.
#
# if i/o is to be thru COMx, run: nmake aux=1
# if kbd is to be US, run: nmake kbd=us

!ifndef AUX
AUX=0
!endif
!ifndef KBD
KBD=GR
!endif

DEBUGRDIR = \projects\debug\build

odir = build

ALL: $(odir) $(odir)\Deb386.exe $(odir)\Deb386.sys $(odir)\ResWP.exe

$(odir):
	@mkdir $(odir)

$(odir)\Deb386.exe: Deb386.asm $(odir)\DebugR.bin Makefile dprintfr.inc dprintfp.inc vioout.inc kbdinp.inc auxout.inc
!if $(AUX)
	@jwasm -nologo -mz -Sg -DAUXOUT=1 -DAUXIN=1 -DBINDIR=$(odir) -Fl$* -Fo$* Deb386.asm
!else
	@jwasm -nologo -mz -Sg -DVIOOUT=1 -DKBDIN=1 -DKEYS=KBD_$(KBD) -DBINDIR=$(odir) -Fl$* -Fo$* Deb386.asm
!endif

$(odir)\Deb386.sys: Deb386.asm $(odir)\DebugR.bin Makefile dprintfr.inc dprintfp.inc vioout.inc kbdinp.inc auxout.inc
!if $(AUX)
	@jwasm -nologo -mz -Sg -DAUXOUT=1 -DAUXIN=1 -DBINDIR=$(odir) -DDRIVER=1 -Fl$*d -Fo$*.sys Deb386.asm
!else
	@jwasm -nologo -mz -Sg -DVIOOUT=1 -DKBDIN=1 -DKEYS=KBD_$(KBD) -DBINDIR=$(odir) -DDRIVER=1 -Fl$*d -Fo$*.sys Deb386.asm
!endif

$(odir)\DebugR.bin: $(DEBUGRDIR)\DebugR.bin
	@cd $(odir)
	@copy $(DEBUGRDIR)\DebugR.bin
	@cd ..

$(odir)\ResWP.exe: ResWP.asm
	@jwasm -nologo -mz -Fl$* -Fo$* ResWP.asm

clean:
	@del $(odir)\Deb386.exe
	@del $(odir)\ResWP.exe
	@del $(odir)\*.bin
	@del $(odir)\*.lst
