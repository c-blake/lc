# Package
version     = "0.20.6"
author      = "Charles Blake"
description = "A post-modern, \"multi-dimensional\", configurable, abbreviating, extensible ls/file lister"
license     = "MIT/ISC"
bin         = @["lc"]
installDirs = @["man", "configs"]
# Dependencies
requires "nim >= 1.6.0", "cligen >= 1.6.12"

import os, strutils #XXX from os import parentDir, getEnv, dirExists fails
proc getNimbleDir: string =
  result = getEnv("NIMBLE_DIR", getEnv("nimbleDir", ""))
  if result.len > 0: return
  if (let (installDir, ex) = gorgeEx("nimble path lc"); ex == 0):
    result = installDir.strip.parentDir.parentDir  # Hopefully .ini nimbleDir

# 1) While becoming rare, for a CLI tool like `ls` a man page seems expected.
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
Try doing `nimble install lc` first
or try `MAN_DIR=/x/y/share/man nimble installMan`"""; return
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

# 2) The next bits populate an `etc/lc/` directory used by `lc` If a user gives
# neither config nor CLI options.  `lc` finds this from /proc/PID | $0 which may
# not work in all OSes/shells (then users just do not get a fallback config..).
proc getEtcDir: string =
  result = getEnv("ETC_DIR", getEnv("ETCDIR", getEnv("etcDir", "")))
  if result.len > 0: return
  let nDir = getNimbleDir()
  if nDir.len == 0: return
  let etc = nDir & "/../etc"                    # $(HOME|/opt)/etc
  result = if etc.dirExists: etc & "/lc" else: nDir & "/../etc/lc"

task installConf, "install the default config in \".../etc/lc/\"":
  let cD = getEtcDir()                          # .../etc/lc
  if cD.dirExists or cD.fileExists:
    echo "\n", cD, " ALREADY EXISTS\nRename/Remove/uninstallConf & try again"
  elif cD.len > 0:
    exec "umask 022 && mkdir -p " & cD & " && install -m644 configs/cb0/* " & cD
  else: echo """ERROR: Could not infer ETC_DIR;
Try doing `nimble install lc` first
or try `ETC_DIR=/x/y/etc nimble installConf`"""; return

task uninstallConf, "uninstall the default config from \".../etc/lc/\"":
  let cD = getEtcDir(); let pD = cD.parentDir   # rmdir in case we spammed $HOME
  if dirExists(cD): exec "rm -vr " & cD & " && rmdir -v "  & pD & ";:"

task installData, "installMan;Conf": installManTask(); installConfTask()
task uninstallData, "uninstallMan;Conf": uninstallManTask(); uninstallConfTask()

# 3) Allow nimble to drive both man & conf installation if it has permission.
proc absent(evs: openArray[string]): bool =             # True if *NONE* of evs
  result = true
  for ev in evs: result = result and not ev.existsEnv   #..is set to anything.
after install:          # Evidently, `after uninstall:` is not honored
  if ["NIMBLE_MINI","mini"].absent:
    if ["NIMBLE_NOMAN","noman"].absent: installManTask()
    if ["NIMBLE_NOETC","noetc","NIMBLE_NOCONF","noconf"].absent: installConfTask()
