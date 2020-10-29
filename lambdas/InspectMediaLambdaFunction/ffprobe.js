const childProcess = require('child_process');
const os = require('os');

/**
 * @typedef {object} FfprobeResult
 * @property {array} [streams]
 * @property {object} [format]
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
            resolve(JSON.parse(Buffer.concat(resultBuffers).toString().trim()));
          } catch (error) {
            reject(error);
          }
        }
      });
    });
  },
};
