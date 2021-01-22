# Package

version       = "0.1.0"
author        = "Carlo Capocasa"
description   = "nestegg, a portable demuxer for the webm audio/video container format, which is a subset of the matroska container format."
license       = "0BSD"

# Dependencies

requires "nim >= 1.4.0"
requires "nimterop"
foreignDep "autoconf"
foreignDep "libtool"
foreignDep "make"

