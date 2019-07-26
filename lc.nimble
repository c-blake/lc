# Package
version     = "0.6"
author      = "Charles Blake"
description = "A post-modern, \"multi-dimensional\" configurable ls/file lister"
license     = "MIT/ISC"
bin         = @["lc"]

# Dependencies
requires "nim >= 0.19.2", "cligen#head"
skipDirs = @["configs"]
