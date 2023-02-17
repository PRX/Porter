/* eslint-disable max-classes-per-file */
const childProcess = require('child_process');
const os = require('os');

class InvalidDataFormatError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'InvalidDataFormatError';
  }
}

class InvalidMediaFormatError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'InvalidMediaFormatError';
  }
}

module.exports = {
  async v1(event, inputFilePath, outputFilePath) {
    return new Promise((resolve, reject) => {
      // Use the heuristically-determined file extension of the input file as
      // the input format by default
      let mediaFormat = event.Artifact.Descriptor.Extension;

      // Only certain extensions for some valid formats are compatible with
      // audiowaveform. Remap known incompatible values to their compatible
      // equivalents.
      if (mediaFormat === 'oga') {
        mediaFormat = 'ogg';
      }

      // If the task explicity sets a media format, use that instead
      if (event.Task.MediaFormat) {
        mediaFormat = event.Task.MediaFormat;
      }

      // Throw an error if the final media format is not supported
      if (!['wav', 'mp3', 'flac', 'ogg', 'opus'].includes(mediaFormat)) {
        reject(
          new InvalidMediaFormatError(
            `Unexpected media format: ${mediaFormat}`,
          ),
        );
      }

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
      // range.
      const pointsPerSecond = Number.isInteger(
        event.Task.WaveformPointFrequency,
      )
        ? Math.max(1, Math.min(4096, event.Task.WaveformPointFrequency))
        : 100;

      const start = process.hrtime();

      // Set the program parameters
      const args = [
        '--input-filename',
        inputFilePath,
        '--input-format',
        mediaFormat,
        '--output-filename',
        outputFilePath,
        '--output-format',
        outputFormat,
        '--bits',
        `${bitDepth}`,
        '--pixels-per-second',
        `${pointsPerSecond}`,
      ];
      console.log(
        JSON.stringify({
          msg: 'audiowaveform arguments',
          args,
        }),
      );

      // Run the program
      const childProc = childProcess.spawn('/opt/bin/audiowaveform', args, {
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
