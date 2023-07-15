# Package
version     = "0.11.0"
author      = "Charles Blake"
description = "A post-modern, \"multi-dimensional\", configurable, abbreviating, extensible ls/file lister"
license     = "MIT/ISC"
bin         = @["lc"]
installDirs = @["man", "configs"]
# Dependencies
requires "nim >= 1.6.0", "cligen >= 1.6.8"

import os #XXX from os import parentDir, getEnv, dirExists fails
proc getNimbleDir: string =
  result = getEnv("NIMBLE_DIR", getEnv("nimbleDir", ""))
  if result.len > 0: return
  if (let (installDir, ex) = gorgeEx("nimble path lc"); ex == 0):
    result = installDir.parentDir.parentDir     # nimbleDir/pkgs*/x

proc getManDir: string =
  result = getEnv("MAN_DIR", getEnv("MANDIR", getEnv("manDir", "")))
  if result.len > 0: return
  let nDir = getNimbleDir()
  if nDir.len == 0: return
  let share = nDir & "/../share"                # $(HOME|/opt)(/share)*/man
  result = if share.dirExists: share & "/man" else: nDir & "/../man"

task installMan, "install the man page lc.1":   # Named ~as automake does
  let mD = getManDir()
  if mD.len == 0: echo """ERROR: Could not infer MAN_DIR
Try doing `nimble install lc` first or else force override
with `MAN_DIR=/x/y/share/man nimble installMan`"""; return
  if hostOS == "linux":
    exec "install -Dvm644 man/lc.1 " & mD & "/man1/lc.1"
  else: # if hostOS == "macosx" or hostOS.endsWith("bsd"):
    let m1 = mD & "/man1"
    echo "installing man page as " & m1 & "/lc.1"
    exec "umask 022 && mkdir -p "&m1&" && install -m644 man/lc.1 "&m1&"/lc.1"
  if (let (_, ex) = gorgeEx("man lc | grep -q custom-classified"); ex != 0):
    echo "WARNING: `man lc` may not work; ",mD," --> $MANPATH may help."

task uninstallMan, "uninstall the man page lc.1":
  let mD = getManDir()
  if mD.len == 0: echo """ERROR: Could not infer MAN_DIR;
`MAN_DIR=/x/y/share/man nimble uninstallMan` may work"""; return
  exec "rm -vf "&mD&"/man1/lc.1 && rmdir -v "&mD&"/man1 && rmdir -v "&mD&";:"
