
dewebm
======

WebM is a web standard audio/video file format supported by most browsers. It is a simplified subset of the Matroska file format and may only contain the VP8, VP9 or AV1 video codecs or the OGG or OPUS audio codecs.

This is a Nim wrapper for the nestegg C library, which was designed for portability and efficiency. The wrapper is based on nimterop and links statically. The design is thin but featureful- the C API is exposed as is to preserve flexibility but with Nim language constructs and memory safety.

Examples
--------

Example of regular use with one or more decoders

    import dewebm

    let file = open("myvideo.webm")
    let demuxer = Demuxer(file)

    for track in d.tracks:
      echo $track.kind, " track with ", $track.codec, " codec"

      # initialize decoder for each track here

    for packet in demuxer:

      if packet.track.num == 0:
        echo $d.kind, " track with ", $d.codec, " codec"

        for chunk in packet:
          
          # send data chunk to decoder

          # if the decoder is also a C wrapper, an array
          # and a length are usually supplied
          # this is not memory safe
          
          myDecoder.sendData(chunk.data, chunk.length)

          # chunk.data is a ptr UncheckedArray[byte] and may need 
          # to be cast to whatever the decoder expects
          # myDecoder.sendData(cast[pointer](chunk.data), chunk.length)

    file.close()

Internals
---------

Memory safety is achieved by keeping each untraced reference to memory chunks from the C library in a traced Nim object. The Nim object has a finalizer that deallocates the untraced memory using the library interface when it goes out of scope. Further traced objects may contain untraced references to untraced memory as long as a reference to those objects is stored in the object with the finalizer, deferring deallocation of untraced memory until it can no longer be accessed. TL;DR It's by piggy-back

