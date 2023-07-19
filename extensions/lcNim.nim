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
  cmdExitsOk("te1", qualPath) # te == T)est E)xtension

proc te2(qualPath: cstring): cint {.noconv, exportc, dynlib.} =
  cmdExitsOk("te2", qualPath)

# With this part, lc -e liblcNim.so:fe1 -f'%e %f' does something interesting if
# a program in $PATH named "fe1" also does something interesting (when given a
# fully qualified path as $1) and similarly for "fe2" in both places. { It may
# be helpful to move to a 5-field param: lib:hdr:ini:arg:fun & call ob=ini(arg)
# just once and later fun(ob, qpath) for each file to avoid global state. }
var res: string               # Use a global to avoid after-call GC
proc cmdOutput(cmd: string, qualPath: cstring): cstring =
  qpString(qualPath)
  try:
    let f = popen((cmd & " " & qp).cstring, "r".cstring)
    res = f.readAll.strip     # External command-based user-defined fmt fields.
    f.close                   # User must keep output easy on tabulation, but
    return res.cstring        # we do at least strip any trailing newline.
  except CatchableError:
    res.setLen(0)

proc fe1(qualPath: cstring): cstring {.noconv, exportc, dynlib.} =
  cmdOutput("fe1", qualPath)  # fe == F)ormat E)xtension

proc fe2(qualPath: cstring): cstring {.noconv, exportc, dynlib.} =
  cmdOutput("fe2", qualPath)

# 3 ideas to get you started: space usage, security contexts, git status
# #!/bin/sh
# du -s "$1" | awk '{print $1}'
# #!/bin/sh
# ls -1Z "$FILE_NAME" | awk '{print $1}' | tr -d \\n
# #!/bin/sh
# d="${1%/*}"; b="${1##*/}"         # d)ir & b)asename
# n="/dev/null"; t="$(printf '\t')" # n)ull & t)ab
# case $(cd "$d" 2>$n; git status 2>$n |noc| grep "$b") in
#   "${t}new file: "*) echo 'A';; # Codes used by Mercurial
#   "${t}modified: "*) echo 'M';; # Slow, buggy, incomplete
#   "${t}deleted: "*)  echo 'D';; # More teaser than answer
#   *?*) echo '?';; *) printf '-' ;;
# esac
