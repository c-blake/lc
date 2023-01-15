# Package
version     = "0.9.3"
author      = "Charles Blake"
description = "A post-modern, \"multi-dimensional\", configurable, abbreviating, extensible ls/file lister"
license     = "MIT/ISC"
bin         = @["lc"]

# Dependencies
requires "nim >= 1.2.0", "cligen >= 1.5.37"
skipDirs = @["configs"]
