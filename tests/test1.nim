# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest, os

import nestegg

let testDir = currentSourcePath().parentDir()

test "high level":
  let f = open(testDir/"bear-av1-opus.webm")
  let demuxer = newDemuxer(f)
  for packet in demuxer:
    #[
    echo $packet.track.kind, " PACKET"
    for chunk in packet.chunks:
      echo "CONTAINS CHUNK"
      echo $chunk[]
    ]#

    for chunk in packet:
      discard

  f.close
