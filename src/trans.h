/* 
 * RCS: @(#) $Id: trans.h,v 1.2 2002/07/10 07:36:37 barras Exp $
 */

#pragma export on
EXTERN int AxisCmd( ClientData clientData, Tcl_Interp *interp,
	      int argc, char *argv[]);
EXTERN int SegmtCmd( ClientData clientData, Tcl_Interp *interp,
	      int argc, char *argv[]);
EXTERN int WavfmCmd( ClientData clientData, Tcl_Interp *interp,
	      int argc, char *argv[]);
EXTERN int Trans_Init(Tcl_Interp *interp);
EXTERN int Trans_SafeInit(Tcl_Interp *interp);
#pragma export reset
