import nimterop/[build, cimport]
import strutils

## nim-nestegg - a portable, statically linked WebM format demuxer for Nim
##
## wraps the popular and portable nestegg C library from mozilla in Nim goodness (expressiveness and memory safety)

import nestegg/wrapper

export audio_params
export video_params

type
  va_list {.importc: "va_list", header: "<stdarg.h>".} = object

proc vprintf(format: cstring, args: va_list) {.cdecl, importc, header: 
"stdio.h"}
proc vfprintf(file: File, format: cstring, args: va_list) {.cdecl, importc, header: 
"stdio.h"}
proc va_start(args: va_list, format: cstring) {.cdecl, importc, header: 
"stdio.h"}
proc va_end(args: va_list) {.cdecl, importc, header: 
"stdio.h"}

proc log_callback(context: ptr nestegg, severity: cuint, format: cstring) {.cdecl,varargs} =
  var sev:cstring
  case (severity):
  of LOG_DEBUG:
    sev = "debug:   "
  of LOG_WARNING:
    sev = "warning: "
  of LOG_CRITICAL:
    sev = "critical:"
  else:
    sev = "unknown: "
  stderr.write sev
  
  var args:va_list
  va_start(args, format)
  vfprintf(stderr, format, args)
  va_end(args)
  stderr.writeLine ""

const unknownValue = high(int8)

type
  AudioCodec* = enum
    ## Allowed codecs for WebM audio, or flag unknown
    acVorbis = (CODEC_VORBIS, "vorbis")
    acOpus = (CODEC_OPUS, "opus")
    acUnknown = (unknownValue, "unkown")
  VideoCodec* = enum
    ## Allowed codecs for WebM video, or flag unknown
    vcVp8 = (CODEC_VP8, "vp8")
    vcVp9 = (CODEC_VP9, "vp9")
    vcAv1 = (CODEC_AV1, "av1")
      ## av1 is de-facto part of webm and assumed to become official
    vcUnknown = (unknownValue, "unkown")
  TrackKind* = enum
    ## Track types, audio or video
    tkVideo = (TRACK_VIDEO, "video")
    tkAudio = (TRACK_AUDIO, "audio")
    tkUnknown = (unknownValue, "unknown")

  InitError* = object of IOError
    ## An error that happens during setting up of the demuxer
  DemuxError* = object of IOError
    ## An error that happens during the demuxing process itself

  TrackObj* = object
    ## Contains initialization data and metadata about one of the tracks multiplexed in the WebM file
    case kind*: TrackKind
    of tkVideo:
      videoCodec*: VideoCodec
      videoParams*: video_params
      duration*: culonglong
      fps*: float
    of tkAudio:
      audioCodec*: AudioCodec
      audioParams*: audio_params
    of tkUnknown:
      discard
    num*: cuint
    codecData*: seq[Chunk]
  Track* = ref TrackObj
  Chunk* = object
    ## A chunk of data. Each multiplexed packet contains a series of these chunks that make up the
    ## actual encoded data to be sent to the decoder
    # TODO: When data views are no longer experimental, an openArray view should be used instead
    # of this chunk object
    len*: int
    data*: ptr UncheckedArray[byte]
  PacketObj* = object
    ## An individual data packet. A stream of these is sent over a file or a network, each track's packets
    ## interspersed with each other. That's what makes it a multiplexed stream. Each `Packet` contains
    ## one or more Chunks of raw data.
    raw*: ptr cpacket
    length*: cuint
    timestamp*: culonglong
    track*: Track
    chunks*: seq[Chunk]
  Packet* = ref PacketObj
  SourceObj* = object
    ## A data source interface that is mapped to a file by default, but other data
    ## sources such as network streams can be implemented.
    io*: io
  Source* = ref SourceObj
  DemuxerObj* = object
    ## The demuxer object that wraps the actual demux process. Can be iterated
    ## over to retrieve packets.
    file*: File
    context*: ptr nestegg
    duration*: uint64
    source*: Source
    tracks*: seq[Track]
    firstVideo*: Track
    firstAudio*: Track
  Demuxer* = ref DemuxerObj

proc file_read(buffer: pointer, length: csize_t, file: pointer): cint {.cdecl} =
  ## Internal "seek" (position setting) procedure to map a file object to the internal muxer
  let file = cast[File](file)
  let n = file.readBuffer(buffer, length)
  if n == 0:
    if file.endOfFile:
      return 0
    else:
      return -1
  return 1

proc file_seek(offset: clonglong, whence: cint, file: pointer): cint {.cdecl} =
  ## Internal "seek" (position setting) procedure to map a file object to the internal muxer
  let file = cast[File](file)
  file.setFilePos(offset, whence.FileSeekPos)

proc file_tell(file: pointer): clonglong {.cdecl} =
  ## Internal "tell" (position getting) procedure to map a file object to the internal muxer
  let file = cast[File](file)
  return file.getFilePos

# proc cleanup(track: Track) =
#   discard

proc newTrack*(context: ptr nestegg, trackNum: cuint): Track =
  let trackType = track_type(context, trackNum)
  let kind = case trackType:
    of TRACK_UNKNOWN:
      tkUnknown
    else:
      trackType.TrackKind
  #[
  # workaround - left here commented out in case a track cleanup function might be needed after all
  if kind == tkVideo:
    # workaround to register finalizer, call new for the default value
    new(result, cleanup)
    assert result.kind == tkVideo
  else:
    result = Track(kind: kind)
  ]#
  result = Track(kind: kind)
  let raw_codec_id = track_codec_id(context, trackNum)
  case result.kind:
  of tkVideo:
    if 0 != track_video_params(context, trackNum, result.videoParams.addr):
      raise newException(InitError, "error initializing video track metadata $#" % $trackNum)
    result.videoCodec = case raw_codec_id:
    of CODEC_UNKNOWN:
      vcUnknown
    else:
      raw_codec_id.VideoCodec

    if 0 != track_default_duration(context, trackNum, result.duration.addr):
      raise newException(InitError, "error initializing track duration for track $#" % $trackNum)
    result.fps = 1000_000_000.0 / result.duration.float

  of tkAudio:
    if 0 != track_audio_params(context, trackNum, result.audioParams.addr):
      raise newException(InitError, "error initializing audio track metadata $#" % $trackNum)
    result.audioCodec = case raw_codec_id:
    of CODEC_UNKNOWN:
      acUnknown
    else:
      raw_codec_id.AudioCodec
  else:
    discard
  result.num = trackNum
  var n:cuint
  if 0 == track_codec_data_count(context, trackNum, n.addr):
    # just ignore errors for this one, they get returned when a codec isn't vorbis or opus
    # if there really is womething wrong with the init data, we catch it in track_codec_data below
    for i in 0..<n:
      var codecChunk:Chunk
      var l: uint
      if 0 != track_codec_data(context, trackNum, i.cuint, cast[ptr ptr cuchar](codecChunk.data.addr), l.addr):
        raise newException(InitError, "error initializing codec initialization data chunk $# of track $#" % [$i, $trackNum])
      codecChunk.len = l.int
      result.codecData.add(codecChunk)

proc newSource(file: File): Source =
  ## Create a set of callback functions for the wrapped library to call
  ## to navigate a data stream and get data. This particular set reads
  ## from a nim file. Other data sources, such as network streams, can be
  ## implemented by duplicating this constructor and taking a different object
  ## to initialize from
  new(result)
  result.io.read = file_read
  result.io.seek = file_seek
  result.io.tell = file_tell

  # This is potentially dangerous. Use Nim objects that can be cast to pointers
  # and back without a lot of fuss, since this is passed directly into the wrapped
  # C library
  result.io.userdata = cast[pointer](file)

proc cleanup(demuxer: Demuxer) =
  ## Object finalizer triggered by the GC, explicitly destroys the demuxer
  destroy(demuxer.context)

proc newDemuxer*(source: Source): Demuxer =
  ## Initialize a demuxer object from a data source. Reads all the initialization
  ## data and metadata and presents them in an object. Can be iterated over in order
  ## to retrieve data packets from the stream.
  new(result, cleanup)
  result.source = source
  if 0 != init(result.context.addr, result.source.io, cast[log](log_callback), -1):
    # insert statemnts into nestegg.h/nestegg_init for more detailed debugging 
    raise newException(InitError, "initializing nestegg demuxer failed")

  var n: cuint
  if 0 != track_count(result.context, n.addr):
      raise newException(InitError, "could not retrieve track count")

  if 0 != duration(result.context, result.duration.addr):
      raise newException(InitError, "could not retrieve duration")

  result.tracks.setLen(n)
  for i in 0..<n:
    result.tracks[i] = newTrack(result.context, i)

  for track in result.tracks:
    if track.kind == tkVideo:
      result.firstVideo = track
      break
  for track in result.tracks:
    if track.kind == tkAudio:
      result.firstAudio = track
      break

template newDemuxer*(file: File): Demuxer =
  ## Convenience template to create a demuxer from a file objcet
  ## If other sources are created, adding one of these keeps the interface friendly
  newDemuxer(newSource(file))

proc cleanup(packet: Packet) =
  ## Object cleanup for packets. Explicitly frees the memory occupied by the packet.
  free_packet(packet.raw)

iterator items*(demuxer: Demuxer): Packet =
  ## The iterater that retrieves packets from the demuxer. Note that a packet
  ## can be from various tracks, no guarantees are made in which order packets
  ## arrive in. Within the iterator, select codecs to handle the data and perform
  ## buffering as needed.
  var packet: Packet
  new(packet, cleanup)
  while 0 != read_packet(demuxer.context, packet.raw.addr):
    var i:cuint
    if 0 != packet_track(packet.raw, i.addr):
      raise newException(DemuxError, "could not retrieve packet track number")
    packet.track = demuxer.tracks[i]
    if 0 != packet_count(packet.raw, packet.length.addr):
      raise newException(DemuxError, "could not retrieve number of data objects")
    if 0 != packet_tstamp(packet.raw, packet.timestamp.addr):
      raise newException(DemuxError, "could not retrieve packet timestamp")
    
    for i in 0..<packet.length:
      var chunk:Chunk
      var l:uint
      if 0 != packet_data(packet.raw, i.cuint, cast[ptr ptr cuchar](chunk.data.addr), l.addr):
        raise newException(DemuxError, "could not retrieve data chunk from track $#" % $i)
      chunk.len = l.int
      packet.chunks.add(chunk)

    yield packet
  
    new(packet) # cleanup already specified, once per type is enough

#template items*(demuxer: Demuxer) =
#  ## Convenience template that allows iterating directly over the demuxer object
#  ## without explicitly specifying a interator
#  packets(demuxer)

iterator items*(packet: Packet): Chunk =
  for p in packet.chunks:
    yield p

template toOpenArray*(chunk:Chunk, first, last: int): openArray[byte] =
  ## Allows passing a chunk of data to various collection functions that take an openArray
  ## for data analysis or processing. This is always a copy operation.
  if last > chunk.len:
    raise newException(ValueError, "last:int $# is larger than chunk.len $#" % [$last, $chunk.len])
  toOpenArray(chunk.data, first, last)

