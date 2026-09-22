# Test samples

Fixtures for this container's unit tests - self contained.

Acceptance-test fixtures still in `test/samples`; those are fetched from github

## `tiny-video.ts`

Made up test pattern video - regenerate with:
```
    ffmpeg -f lavfi -i testsrc=size=426x240:rate=30:duration=1 \
      -c:v libx264 -profile:v baseline -level 2.1 -pix_fmt yuv420p -g 30 -an \
      -f mpegts tiny-video.ts
```

## `source-480p-13s.mp4`

Made up test pattern video with a tone - regenerate with:
```
    ffmpeg -f lavfi -i testsrc=size=854x480:rate=30:duration=13 \
      -f lavfi -i sine=frequency=440:sample_rate=48000:duration=13 \
      -map 0:v -map 1:a \
      -c:v libx264 -preset veryslow -crf 40 -pix_fmt yuv420p \
      -c:a aac -b:a 32k -movflags +faststart source-480p-13s.mp4
```

## `source-audio-only.m4a`

A source with no video stream, which the task refuses - regenerate with:
```
    ffmpeg -f lavfi -i sine=frequency=440:sample_rate=8000:duration=0.1 \
      -c:a aac -b:a 8k source-audio-only.m4a
```
