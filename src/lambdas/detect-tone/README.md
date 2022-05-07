# Tone Detection

Uses a series of FFmpeg audio filters to find specific tones within an audio file and report the timings of those tones.

## FFmpeg command

Looks something like this:

```shell
ffmpeg -i myAudio.mp3 -af _____ -f null -
```

`-i myAudio.mp3` indicates the input audio file

`-af` is an alias for `-filter:a`, which creates an audio filtergraph (a chain of one or more filters). See below for more details.

`-f null` indicates that FFmpeg will not attempt to encode or mux any output media, since all that is required from this command is the tone timing data.

The final `-` means that any output the command does generate will be sent to stdout.

### Filtergraph

In the above command, the `_____` is where the audio filtergraph used to detect tones goes. The filtergraph consists of six filters.

`pan=mono|c0=.5*c0+.5*c1`: The `pan` filter mixes audio channels. This will output a single mono channel with two input channels contributing equally (i.e., balanced). This essentially mixes stereo files down to mono.

`volume=volume=1.0`: The `volume` filter adjusts audio volume. I don't remember exactly why this filter is included, but it seemed necessary to include after the `pan`.

`bandpass=frequency=440:width_type=q:width=3`: Applies a bandpass filter to the audio, using a Q-factor model to set the width of the band at the given frequency. The frequency here, `440` in the example, would be the tone we are trying to detect. This filter is attempting to remove any audio that is not very close to the desired tone.

`asetnsamples=2000`: Sets the number of samples per frame, which is attempting to decrease the resolution of the input audio to smooth out the data being used for tone detection. This is attempting to reduce the possibilities of false positive detections of audio in the file that is close to the frequency, but is not the intended detectable tone engineered into the audio.

`astats=metadata=1:reset=1`: Produces statistical information about the audio input to the filter. `metadata=1` turns the filter on, and `reset=1` resets the statistical calculation every 1 frame.

`ametadata=key=lavfi.astats.Overall.Max_level:mode=print:file=tone.txt`: Captures the `astats` metadata added by the previous filter. The `mode=print` option prints the frame metadata available to the filter. The `file=tone.txt` specifies a file that the print output is written to. `key=lavfi.astats.Overall.Max_level` indicates that only metadata with the `lavfi.astats.Overall.Max_level` key should be captured by the filter (`astats` produces lots of metadata with many different keys).

## Level Metadata

An example of the text file that gets created by this filter:

```
frame:0    pts:0       pts_time:0
lavfi.astats.Overall.Max_level=0.075196
frame:1    pts:2000    pts_time:0.0453515
lavfi.astats.Overall.Max_level=0.059983
frame:2    pts:4000    pts_time:0.0907029
lavfi.astats.Overall.Max_level=0.059990
frame:3    pts:6000    pts_time:0.136054
lavfi.astats.Overall.Max_level=0.059991
```

Note that there are lines that indicate a frame, time, etc, and the following lines are the statistical metadata associated with that frame. The filtergraph included on the `Overall.Max_level` value in the file.

This Lambda function reads through these lines, and constructs ranges of time where a given tone appears to be present in the audio, based on these overall max sample level values.
