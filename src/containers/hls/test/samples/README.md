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
