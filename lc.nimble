# Package
version     = "0.8"
author      = "Charles Blake"
description = "A post-modern, \"multi-dimensional\", configurable, abbreviating, extensible ls/file lister"
license     = "MIT/ISC"
bin         = @["lc"]

# Dependencies
requires "nim >= 0.19.2", "cligen#head"
skipDirs = @["configs"]
