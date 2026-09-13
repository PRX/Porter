# Test samples

Fixtures for the acceptance tests

## Third-party content

### `big-buck-bunny-30s.mp4`

A 30-second 1080p excerpt of *Big Buck Bunny*, re-encoded for size.

> (c) copyright 2008, Blender Foundation / [www.bigbuckbunny.org](https://www.bigbuckbunny.org)

Licensed under the [Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/)
license, which permits redistribution and modification, including commercially,
with attribution.

- Source: `bbb_sunflower_1080p_30fps_normal.mp4` <https://ftp.nluug.nl/pub/graphics/blender/demo/movies/BBB/>.
  and the Internet Archive licensed as CC BY 3.0: <https://archive.org/details/BigBuckBunny>.
- Excerpted from 00:00:40, re-encoded H.264 at CRF 48, audio re-encoded to 64 kb/s AAC.
  The source's 5.1 AC-3 track was dropped; its stereo MP3 track became the AAC.
  (Start at :40 avoids logos, opening titles.)

To recreate it:
```sh
curl -o bbb.zip "https://ftp.nluug.nl/pub/graphics/blender/demo/movies/BBB/bbb_sunflower_1080p_30fps_normal.mp4.zip"

unzip -q -d bbbsrc bbb.zip

ffmpeg -y -ss 40 -t 30 -i bbbsrc/bbb_sunflower_1080p_30fps_normal.mp4 \
  -map 0:v:0 -map 0:a:0 \
  -vf "scale=1920:1080:force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1" \
  -c:v libx264 -preset veryslow -crf 48 -pix_fmt yuv420p \
  -c:a aac -b:a 64k -ac 2 -movflags +faststart big-buck-bunny-30s.mp4
```
