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
    if sym.kind == nskType and sym.name == "nestegg_packet":
      sym.name = "cpacket"
    elif (sym.kind == nskProc or sym.kind == nskType or sym.kind == nskConst) and sym.name.toLowerAscii.startsWith("nestegg_"):
      sym.name = sym.name.substr(8)

# supplement automatic conversions with hand-edits
cOverride:
  const
    CODEC_UNKNOWN = high(cint)
    TRACK_UNKNOWN = high(cint)
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

const unknownValue = high(int8)

type
  AudioCodec* = enum
    acVorbis = (CODEC_VORBIS, "vorbis")
    acOpus = (CODEC_OPUS, "opus")
    acUnknown = (unknownValue, "unkown")
  VideoCodec* = enum
    vcVp8 = (CODEC_VP8, "vp8")
    vcVp9 = (CODEC_VP9, "vp9")
    vcAv1 = (CODEC_AV1, "av1")
    vcUnknown = (unknownValue, "unkown")
  TrackKind* = enum
    tkVideo = (TRACK_VIDEO, "video")
    tkAudio = (TRACK_AUDIO, "audio")
    tkUnknown = (unknownValue, "unknown")
  TrackObj* = object
    case kind: TrackKind
    of tkVideo:
      videoCodec: VideoCodec
      videoParams: video_params
    of tkAudio:
      audioCodec: AudioCodec
      audioParams: audio_params
    of tkUnknown:
      discard
  Track* = ref TrackObj
  InitError* = object of IOError
  DemuxError* = object of IOError
  DemuxerObj* = object
    file: File
    context: ptr nestegg
    duration: uint64
    codecdata, ptrvar: ptr cuchar
    io: io
    tracks: seq[Track]
  Demuxer = ref DemuxerObj
  PacketObj* = object
    raw: ptr cpacket
    track: Track
    n: cuint
    timestamp: culonglong
  Packet = ref PacketObj

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

proc cleanup(track: Track) =
  discard

proc newTrack(context: ptr nestegg, i: cuint): Track =
  let trackType = track_type(context, i)
  let kind = case trackType:
    of TRACK_UNKNOWN:
      tkUnknown
    else:
      trackType.TrackKind
  if kind == tkVideo:
    # workaround to register finalizer, call new for the default value
    new(result, cleanup)
    assert result.kind == tkVideo
  else:
    result = Track(kind: kind)
  case result.kind:
  of tkVideo:
    if 0 != track_video_params(context, i, result.videoParams.addr):
      raise newException(InitError, "error initializing video track metadata $#" % $i)
  of tkAudio:
    if 0 != track_audio_params(context, i, result.audioParams.addr):
      raise newException(InitError, "error initializing audio track metadata $#" % $i)
  else:
    discard

proc cleanup(demuxer: Demuxer) =
  destroy(demuxer.context)

proc newDemuxer*(file: File): Demuxer =
  new(result, cleanup)
  result.io.read = file_read
  result.io.seek = file_seek
  result.io.tell = file_tell
  result.io.userdata = cast[pointer](file)
  if 0 != init(result.context.addr, result.io, cast[log](log_callback), -1):
    # insert statemnts into nestegg.h/nestegg_init for more detailed debugging 
    raise newException(InitError, "initializing nestegg demuxer failed")

  var n: cuint
  if 0 != track_count(result.context, n.addr):
      raise newException(InitError, "could not retrieve track count")

  if 0 != duration(result.context, result.duration.addr):
      raise newException(InitError, "could not retrieve duration")

  for i in 0..<n:
    result.tracks.add(newTrack(result.context, i))

proc cleanup(packet: Packet) =
  free_packet(packet.raw)

iterator packets*(demuxer: Demuxer): Packet =
  var packet: Packet
  new(packet, cleanup)
  while 0 != read_packet(demuxer.context, packet.raw.addr):
    var i:cuint
    if 0 != packet_track(packet.raw, i.addr):
      raise newException(DemuxError, "could not retrieve packet track number")
    packet.track = demuxer.tracks[i]
    if 0 != packet_count(packet.raw, packet.n.addr):
      raise newException(DemuxError, "could not retrieve number of data objects")
    if 0 != packet_tstamp(packet.raw, packet.timestamp.addr):
      raise newException(DemuxError, "could not retrieve packet timestamp")
    yield packet

iterator data*(packet: Packet): (csize_t, ptr UncheckedArray[byte]) =
  for i in 0..<packet.n:
    var chunk:ptr cuchar
    var size:csize_t
    if 0 != packet_data(packet.raw, i.cuint, chunk.addr, size.addr):
      raise newException(DemuxError, "could not retrieve data chunk")
    yield (size, cast[ptr UncheckedArray[byte]](chunk))



