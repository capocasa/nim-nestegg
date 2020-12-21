
nim-nestegg
=======

**Development version, unfinished! This is here for reference and does spit out data, but has not been tested properly with any real decoders.**

WebM is a web standard audio/video file format supported by most browsers. It is a simplified subset of the Matroska file format and may only contain the VP8, VP9 or AV1 video codecs or the OGG or OPUS audio codecs.

This is a Nim wrapper for the nestegg C library, which was designed for portability and efficiency. The wrapper is based on nimterop and links statically. The design is thin but featureful- the C API is exposed as is to preserve flexibility but with Nim language constructs and memory safety.

Example
--------

Example of regular use with one or more decoders

    import nestegg

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

Documentation
-------------

[nim-nestegg module documentation](//capocasa.github.io/nim-nestegg/nestegg.html), including the low level wrapper, is available


Advisory
--------

nim-nestegg is memory-safe when using the high-level interface as documented.

Directly using C-allocated memory, modifying object structure or directly interfacing with the library are possible but not memory safe.

Internals
---------

**Memory safety''

There are two blobs of memory allocated in C by the nestegg library, accessible by untraced references `Demuxer.context` and `Packet.raw`.

When Demuxer or Packet go out of scope, they have a finalizer that frees up that C-memory.

`Track` objects may contain references to `Demuxer.context` memory. `Demuxer` objects contain a traced reference to each of their `Track`, preventing preventing the `Demuxer.context` memory from going out of scope as long as it can be accessed via a `Track`.

`Chunk` objects may contain references to `Packet.raw` memory. `Packet` objects contain a traced references to ecah of their `Chunk` objects, preventing the `Packet.raw` memory from going out of scope as long as it can be accessed via a `Chunk`.

As always when using finalizers, garbage collection becomes heavier than usual.

**nestegg**

Nestegg itself is a high performance, highly portable C library for demuxing webm streams and should be usable just about everywhere nim is, as long as a C target is used (so emscripten yes, js no), and has seen a lot of production use with Mozilla and others.

Nestegg is not particularly helpful debugging corrupt webm files- it will tell you a file is broken, but not why. This can be circumnvented by inserting debug statements into the failing nestegg function's C code, but for most purposes other tools should be used to validate webm files so nestegg will play them.
