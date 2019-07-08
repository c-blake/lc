# Package
version     = "0.1"
author      = "Charles Blake"
description = "A post-modern, \"multi-dimensional\" configurable ls/file lister"
license     = "MIT/ISC"
bin         = @["lc"]

# Dependencies
requires "nim >= 0.19.2", "cligen >= 0.9.32"
skipDirs = @["configs"]
