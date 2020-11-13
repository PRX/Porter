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
};
