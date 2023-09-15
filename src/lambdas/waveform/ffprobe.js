const childProcess = require('child_process');
const os = require('os');

/**
 * @typedef {object} FfprobeFormat
 * @property {string} [filename]
 * @property {number} [nb_streams]
 * @property {number} [nb_programs]
 * @property {string} [format_name]
 * @property {string} [format_long_name]
 * @property {string} [start_time]
 * @property {string} [duration]
 * @property {string} [size]
 * @property {number} [probe_score]
 * @property {object} [tags]
 */

/**
 * @typedef {object} FfprobeStream
 * @property {number} [index]
 * @property {string} [codec_name]
 * @property {string} [codec_long_name]
 * @property {string} [codec_type]
 * @property {string} [sample_rate]
 * @property {number} [channels]
 * @property {string} [channel_layout]
 * @property {string} [bit_rate]
 * @property {string} [duration]
 * @property {number} [width]
 * @property {number} [height]
 * @property {string} [display_aspect_ratio]
 * @property {string} [r_frame_rate]
 */

/**
 * @typedef {object} FfprobeResult
 * @property {FfprobeStream[]} [streams]
 * @property {FfprobeFormat} [format]
 */

/**
 * @typedef {object} FfprobeLevelsResultFrameTag
 * @property {string} [`lavfi.astats.Overall.Min_level`]
 * @property {string} [`lavfi.astats.Overall.Max_level`]
 */

/**
 * @typedef {object} FfprobeLevelsResultFrame
 * @property {FfprobeLevelsResultFrameTag} [tags]
 */

/**
 * @typedef {object} FfprobeLevelsResultStream
 * @property {"s16"|"s32"|"s64"|"flt"} sample_fmt
 */

/**
 * @typedef {object} FfprobeLevelsResult
 * @property {FfprobeLevelsResultFrame[]} [frames]
 * @property {FfprobeLevelsResultStream[]} [streams]
 */

module.exports = {
  /**
   * @param {string} filePath
   * @returns {Promise<FfprobeResult>}
   */
  inspect: async function inspect(filePath) {
    return new Promise((resolve, reject) => {
      const start = process.hrtime();

      // This should normally output only JSON data
      const childProc = childProcess.spawn(
        '/opt/bin/ffprobe',
        [
          '-v',
          'error',
          '-show_streams',
          '-show_format',
          '-i',
          filePath,
          '-print_format',
          'json',
        ],
        {
          env: process.env,
          cwd: os.tmpdir(),
        },
      );
      const resultBuffers = [];

      childProc.stdout.on('data', (buffer) => resultBuffers.push(buffer));
      childProc.stderr.on('data', (buffer) => console.error(buffer.toString()));

      childProc.on('exit', (code, signal) => {
        const end = process.hrtime(start);
        console.log(
          JSON.stringify({
            msg: 'Finished ffprobe',
            duration: `${end[0]} s ${end[1] / 1000000} ms`,
          }),
        );

        if (code || signal) {
          reject(new Error(`ffprobe failed with ${code || signal}`));
        } else {
          try {
            const data = JSON.parse(
              Buffer.concat(resultBuffers).toString().trim(),
            );
            resolve(data);
          } catch (error) {
            reject(error);
          }
        }
      });
    });
  },
  /**
   * @param {string} filePath
   * @returns {Promise<FfprobeLevelsResult>}
   */
  levels: async function levels(filePath, frameSize) {
    return new Promise((resolve, reject) => {
      const start = process.hrtime();

      // This should normally output only JSON data
      const childProc = childProcess.spawn(
        '/opt/bin/ffprobe',
        [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          // reset=X determines how many frames are used to generate each
          // statistic. reset=1 means: generate a statistic (min, max, etc) for
          // every frame based on all the samples in the frame.
          //
          // asetnsamples=n=X determines the number of samples to include in
          // each frame. When n is equal to the sample rate, each frame will
          // represent 1 second. When n = (sample rate / 100), each frame will
          // represent 0.01 second, etc.
          //
          // The combination of asetnsamples and reset will determine how many
          // data points are generated, and how much audio each data point
          // represents. We hold reset constant at 1, and only use the number
          // of samples per frame to determine how much audio data should
          // contribute to each data point.
          //
          // The samples/frame value is dependent on the sample rate of the
          // audio. For example, given a 44100 Hz file, if the desired output
          // is 10 data points per second, n would need to be 4410; for 50 data
          // points per second, n would need to be 882. For a 48000 Hz file,
          // those values would be 4800 and 960, respectively.
          `amovie=${filePath},asetnsamples=n=${frameSize},astats=metadata=1:reset=1`,
          '-show_entries',
          'stream=sample_fmt:frame_tags=lavfi.astats.Overall.Max_level,lavfi.astats.Overall.Min_level',
          '-of',
          'json',
        ],
        {
          env: process.env,
          cwd: os.tmpdir(),
        },
      );
      const resultBuffers = [];

      childProc.stdout.on('data', (buffer) => resultBuffers.push(buffer));
      childProc.stderr.on('data', (buffer) => console.error(buffer.toString()));

      childProc.on('exit', (code, signal) => {
        const end = process.hrtime(start);
        console.log(
          JSON.stringify({
            msg: 'Finished ffprobe',
            duration: `${end[0]} s ${end[1] / 1000000} ms`,
          }),
        );

        if (code || signal) {
          reject(new Error(`ffprobe failed with ${code || signal}`));
        } else {
          try {
            const data = JSON.parse(
              Buffer.concat(resultBuffers).toString().trim(),
            );
            resolve(data);
          } catch (error) {
            reject(error);
          }
        }
      });
    });
  },
};
