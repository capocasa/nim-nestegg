import nimterop/[build, cimport]
import os

# Nimterop setup

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

# remove nestegg_ prefix

cPlugin:
  import strutils

  # Strip prefix from procs
  proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
    if (sym.kind == nskProc or sym.kind == nskType) and sym.name.startsWith("nestegg_"):
      sym.name = sym.name.substr(8)

# supplement automatic conversions with hand-edits
cOverride:
  type
    io {.importc: "nestegg_io", header: headernestegg, bycopy} = object
      read: proc(buffer: pointer, length: csize_t, userdata: pointer): cint {.cdecl}
      seek: proc(offset: clonglong, whence: cint, userdata: pointer): cint {.cdecl}
      tell: proc(userdata: pointer): clonglong {.cdecl}
      userdata: pointer
    log = proc(context: ptr nestegg, severity: cuint, format: cstring) {.cdecl}

# import symbols
cImport nesteggPath, recurse=false

# compose higher-level API

proc log_callback(context: ptr nestegg, severity: cuint, format: cstring) {.cdecl} =
  discard


type
  NesteggInitError* = object of IOError
  Demuxer* = object
    file: File
    context: ptr nestegg
    audioParams: audio_params
    pkt: ptr packet
    videoParams: video_params
    length, size: csize_t
    duration, tstamp, pkt_tstam: clonglong # TODO: in C this is uint64_t, verify the nim type is ok
    codecdata, ptrvar: ptr cuchar
    cnt, i, j, track, tracks, pkt_cnt, pkt_track, data_items: cuint
    io: io

proc read(p: pointer, length: csize_t, file: pointer): cint {.cdecl} =
  discard

proc seek(offset: clonglong, whent: cint, file: pointer): cint {.cdecl} =
  discard

proc tell(file: pointer): clonglong {.cdecl} =
  discard

proc newDemuxer*(file: File): Demuxer =
  result = Demuxer(
    io: io(
      read: read,
      seek: seek,
      tell: tell,
      userdata: cast[pointer](file)
    )
  )
  var r = init(result.context.addr, result.io, cast[log](log_callback), -1)

iterator iter*(demuxer: Demuxer): string =
  discard


  
