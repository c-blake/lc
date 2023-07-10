# Package
version     = "0.11.0"
author      = "Charles Blake"
description = "A post-modern, \"multi-dimensional\", configurable, abbreviating, extensible ls/file lister"
license     = "MIT/ISC"
bin         = @["lc"]

# Dependencies
requires "nim >= 1.6.0", "cligen >= 1.6.8"

skipDirs    = @["configs"]
installDirs = @["man"]

import os       # splitFile
after install:  # Also install the man page
  proc getManDir(): string =
    # The below is sadly *NOT* robust to `nimble install --nimbleDir:somesuch`.
    # (which may even be a common case for some OS package manager sandboxes..)
    let (installDir, ex) = gorgeEx("nimble path lc")  # nimbleDir/pkgs*/x
    if ex == 0:
      let (pkgs, _,_) = installDir.strip.splitFile    # either pkgs | pkgs2
      let (nimbleDir, _,_) = pkgs.splitFile
      result = nimbleDir & "/man"
  if hostOS == "linux":
    let manDir = getManDir()
    exec "install -Dvm644 man/lc.1 " & manDir & "/man1/lc.1"
    if manDir notin staticExec("manpath") and         #NOTE: man-db-specific
       manDir notin getEnv("MANPATH", ""):
      echo "warning: ", manDir, " is in neither manpath output nor $MANPATH."
  else: # if hostOS == "macosx" or hostOS.endsWith("bsd"):
    let manDir = getManDir(); let m1 = manDir & "/man1"
    echo "installing man page as " & m1 & "/lc.1"
    exec "umask 022 && mkdir -p "&m1&" && install -m644 man/lc.1 "&m1&"/lc.1"
    if manDir notin getEnv("MANPATH", ""):
      echo "warning: ", manDir, " is not in $MANPATH; `man lc` may not work."
