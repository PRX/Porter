/* eslint-disable max-classes-per-file */

const childProcess = require('child_process');
const os = require('os');

class InvalidDataFormatError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'InvalidDataFormatError';
  }
}

module.exports = {
  async v1(event, inputFilePath, outputFilePath) {
    return new Promise((resolve, reject) => {
      // Use the heuristically-determined file extension of the input file as
      // the input format by default. This is only used for MP3 and WAV files
      // that are handled directly by audiowaveform. All other files are
      // pre-processed through FFmpeg, which detects the media format
      // automatically.
      const mediaFormat = event.Artifact.Descriptor.Extension;

      // Ensure that the chosen output format is supported
      if (!['Binary', 'JSON'].includes(event.Task.DataFormat)) {
        reject(
          new InvalidDataFormatError(
            `Unexpected data format: ${event.Task.DataFormat}`,
          ),
        );
      }

      // Remap the human-readable task output format to the value expected by
      // audiowaveform
      const outputFormat = { Binary: 'dat', JSON: 'json' }[
        event.Task.DataFormat
      ];

      // Use the defined bit depth if the value is allowed, otherwise default
      // to 16 bits.
      const bitDepth = [8, 16].includes(event.Task.WaveformPointBitDepth)
        ? event.Task.WaveformPointBitDepth
        : 16;

      // Use the defined points-per-second if it's an integer in the allowed
      // range. Otherwise, clamp it to the range, or default to 100.
      const pointsPerSecond = Number.isInteger(
        event.Task.WaveformPointFrequency,
      )
        ? Math.max(1, Math.min(4096, event.Task.WaveformPointFrequency))
        : 100;

      const start = process.hrtime();

      // Set the program parameters
      // Because we are piping FFmpeg output to audiowaveform, and spawn
      // doesn't really support that so good, w're using this work around where
      // spawn runs `sh` and the entire command is sent as a single argument.
      //
      // This runs some audio files through FFmpeg to be converted to WAV before
      // being sent to audiowaveform to generate the waveform data points. This
      // allows for handling vastly more audio encodings than audiowaveform
      // supports natively.
      let cmd;
      if (['wav', 'mp3'].includes(mediaFormat)) {
        // WAV and MP3 are natively supported by audiowaveform, so they don't
        // run through FFmpeg
        cmd = [
          '/opt/bin/audiowaveform',
          `--input-filename ${inputFilePath}`,
          `--input-format ${mediaFormat}`,
          `--output-filename ${outputFilePath}`,
          `--output-format ${outputFormat}`,
          `--bits ${bitDepth}`,
          `--pixels-per-second ${pointsPerSecond}`,
        ].join(' ');
      } else {
        // All other formats are *not* supported by audiowaveform, so they are
        // transcoded first by FFmpeg with the result being piped to
        // audiowaveform.
        cmd = [
          '/opt/bin/ffmpeg',
          // Input from file
          `-i ${inputFilePath}`,
          // Output to stdout; always transcode to WAV
          '-f wav -',
          '|',
          '/opt/bin/audiowaveform',
          // Input from stdin
          '--input-filename -',
          // Audio coming from FFmpeg is always WAV
          `--input-format wav`,
          `--output-filename ${outputFilePath}`,
          `--output-format ${outputFormat}`,
          `--bits ${bitDepth}`,
          `--pixels-per-second ${pointsPerSecond}`,
        ].join(' ');
      }

      const args = ['-c', cmd];
      console.log(
        JSON.stringify({
          msg: 'audiowaveform arguments',
          args,
        }),
      );

      // Run the program
      const childProc = childProcess.spawn('sh', args, {
        env: process.env,
        cwd: os.tmpdir(),
      });

      // Output from the program is only helpful for debugging purposes
      childProc.stdout.on('data', (buffer) => console.info(buffer.toString()));
      childProc.stderr.on('data', (buffer) => console.error(buffer.toString()));

      // When the program is done, if it exist successfully the data file
      // will be in the output path, and there's nothing else to return from
      // this function other than signal the success.
      childProc.on('exit', (code, signal) => {
        const end = process.hrtime(start);
        console.log(
          JSON.stringify({
            msg: 'Finished audiowaveform',
            duration: `${end[0]} s ${end[1] / 1000000} ms`,
          }),
        );

        if (code || signal) {
          reject(new Error(`audiowaveform failed with ${code || signal}`));
        } else {
          resolve();
        }
      });
    });
  },
};
