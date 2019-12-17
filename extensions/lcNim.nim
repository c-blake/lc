## Show how to extend 'lc' in Nim;  nim c --app:lib -d:release lcNim.nim
## Be sure to install resulting lcNim.so somewhere in $LD_LIBRARY_PATH.
import os, posix, strutils

template qpString(qualPath) {.dirty.} =
  var qp = newStringOfCap(qualPath.len)
  qp.setLen(qualPath.len)
  copyMem(qp[0].unsafeAddr, qualPath, qualPath.len)

proc cmdExitsOk(cmd: string, qualPath: cstring): cint =
  qpString(qualPath)
  (execShellCmd(cmd & " " & qp) == 0).cint

proc te1(qualPath: cstring): cint {.noconv, exportc, dynlib.} =
  cmdExitsOk("te1", qualPath)  # te == T)est E)xtension

proc te2(qualPath: cstring): cint {.noconv, exportc, dynlib.} =
  cmdExitsOk("te2", qualPath)

var res: string               # Use a global to avoid after-call GC
proc cmdOutput(cmd: string, qualPath: cstring): cstring =
  qpString(qualPath)
  try:
    let f = popen((cmd & " " & qp).cstring, "r".cstring)
    res = f.readAll.strip     # External command-based user-defined fmt fields.
    f.close                   # User must keep output easy on tabulation, but
    return res.cstring        # we do at least strip any trailing newline.
  except:
    res.setLen(0)

proc fe1(qualPath: cstring): cstring {.noconv, exportc, dynlib.} =
  cmdOutput("fe1", qualPath)   # fe == F)ormat E)xtension

proc fe2(qualPath: cstring): cstring {.noconv, exportc, dynlib.} =
  cmdOutput("fe2", qualPath)
