import nimterop/[build, cimport]
 
## Low-level C-wrapper for nestegg webm demuxer
## generated with nimterop
##
## Everything is imported, "nestegg_" prefix is removed, "packet" becomes "cpacket" to avoid collision 

# fetch and build configuration
setDefines(@["nesteggGit", "nesteggSetVer=b50521d4", "nesteggStatic"])

static:
  cDebug()

const
  baseDir = getProjectCacheDir("nestegg")

getHeader(
  "nestegg.h",
  giturl = "https://github.com/kinetiknz/nestegg",
  outdir = baseDir,
)

cPlugin:
  import strutils

  # Strip prefix from procs
  proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
    if sym.kind == nskType and sym.name == "nestegg_packet":
      sym.name = "cpacket"
    elif (sym.kind == nskProc or sym.kind == nskType or sym.kind == nskConst) and sym.name.toLowerAscii.startsWith("nestegg_"):
      sym.name = sym.name.substr(8)

# supplement automatic conversions with hand-edits
cOverride:
  const
    CODEC_UNKNOWN* = high(cint)
    TRACK_UNKNOWN* = high(cint)
  #[
  # keep this override around in case we need to downgrade nimterop
  type
    io* {.importc: "nestegg_io", header: headernestegg, bycopy} = object
      read: proc(buffer: pointer, length: csize_t, userdata: pointer): cint {.cdecl}
      seek: proc(offset: clonglong, whence: cint, userdata: pointer): cint {.cdecl}
      tell: proc(userdata: pointer): clonglong {.cdecl}
      userdata: pointer
    log* = proc(context: ptr nestegg, severity: cuint, format: cstring) {.cdecl}
  ]#

# import symbols
cImport nesteggPath, recurse=false

