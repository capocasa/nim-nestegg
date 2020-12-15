import nimterop/[build, cimport]
import os, strutils

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
  DemuxerInitError* = object of IOError
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

proc file_read(buffer: pointer, length: csize_t, file: pointer): cint {.cdecl} =
  let file = cast[File](file)
  let n = file.readBuffer(buffer, length)
  if n == 0:
    if file.endOfFile:
      return 0
    else:
      return -1
  return 1

proc file_seek(offset: clonglong, whence: cint, file: pointer): cint {.cdecl} =
  let file = cast[File](file)
  file.setFilePos(offset, whence.FileSeekPos)

proc file_tell(file: pointer): clonglong {.cdecl} =
  let file = cast[File](file)
  return file.getFilePos

proc newDemuxer*(file: File): Demuxer =
  result = Demuxer(
    io: io(
      read: file_read,
      seek: file_seek,
      tell: file_tell,
      userdata: cast[pointer](file)
    )
  )
  let r = init(result.context.addr, result.io, cast[log](log_callback), -1)
  if r != 0:
    # open up the source file nestegg_init and insert debug statements
    # to get a better idea what the problem is
    raise newException(DemuxerInitError, "initializing nestegg demuxer failed")

iterator demux*(filename: string): string =
  let file = open(filename)
  let demuxer = newDemuxer(file)
  file.close()


