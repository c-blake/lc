# Package
version     = "0.2"
author      = "Charles Blake"
description = "A post-modern, \"multi-dimensional\" configurable ls/file lister"
license     = "MIT/ISC"
bin         = @["lc"]

# Dependencies
requires "nim >= 0.19.2", "cligen >= 0.9.33"
skipDirs = @["configs"]
