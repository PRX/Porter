const childProcess = require('child_process');
const os = require('os');

/**
 * @typedef {object} MpckResult
 * @property {string} [Layer]
 * @property {number} [Samples]
 * @property {number} [Frames]
 * @property {number} [UnidentifiedBytes]
 */

/**
 * @param {string} output - The mpck program output
 * @returns {MpckResult}
 */
function extract(output) {
  const result = {};

  const layer = output.match(/layer\s+([1-3])/);
  if (layer) {
    result.Layer = layer[1];
  }

  const frames = output.match(/frames\s+([0-9]+)/);
  if (frames) {
    result.Frames = +frames[1];
  }

  const samples = output.match(/samples\s+([0-9]+)/);
  if (samples) {
    result.Samples = +samples[1];
  }

  const unidentified = output.match(/unidentified\s+([0-9]+) b/);
  if (unidentified) {
    result.UnidentifiedBytes = +unidentified[1];
  }

  return result;
}

module.exports = {
  /**
   * @param {string} filePath
   * @returns {Promise<MpckResult>}
   */
  inspect: async function inspect(filePath) {
    return new Promise((resolve, reject) => {
      const start = process.hrtime();

      // mpck will nominally output something like:
      // SUMMARY: myAudio.mp3
      //     version                       MPEG v1.0
      //     layer                         3
      //     frames                        1682
      const childProc = childProcess.spawn('/opt/bin/mpck', ['-v', filePath], {
        env: process.env,
        cwd: os.tmpdir(),
      });
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
          reject(new Error(`mpck failed with ${code || signal}`));
        } else {
          resolve(extract(Buffer.concat(resultBuffers).toString().trim()));
        }
      });
    });
  },
};
