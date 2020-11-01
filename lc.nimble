# Package
version     = "0.9.0"
author      = "Charles Blake"
description = "A post-modern, \"multi-dimensional\", configurable, abbreviating, extensible ls/file lister"
license     = "MIT/ISC"
bin         = @["lc"]

# Dependencies
requires "nim >= 0.20.1", "cligen >= 1.2.0"
skipDirs = @["configs"]
