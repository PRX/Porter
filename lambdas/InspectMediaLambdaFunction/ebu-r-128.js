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
  inspect: async function inspect(filePath, measureLoudness) {
    return new Promise((resolve, reject) => {
      if (measureLoudness !== true) {
        resolve({});
      }

      const start = process.hrtime();

      // This will return JSON data after a lot of other FFmpeg process
      // information
      const childProc = childProcess.spawn(
        '/opt/bin/ffmpeg',
        [
          '-v',
          'info',
          '-hide_banner',
          '-nostats',
          '-i',
          filePath,
          '-af',
          'loudnorm=dual_mono=true:print_format=json',
          '-f',
          'null',
          '-',
        ],
        {
          env: process.env,
          cwd: os.tmpdir(),
        },
      );
      const resultBuffers = [];

      // The data we want seems to end up in stderr, so add that to the buffer
      // capture as well
      childProc.stdout.on('data', (buffer) => resultBuffers.push(buffer));
      childProc.stderr.on('data', (buffer) => {
        console.error(buffer.toString());
        resultBuffers.push(buffer);
      });

      childProc.on('exit', (code, signal) => {
        const end = process.hrtime(start);
        console.log(
          JSON.stringify({
            msg: 'Finished ffmpeg loudnorm',
            duration: `${end[0]} s ${end[1] / 1000000} ms`,
          }),
        );

        if (code || signal) {
          reject(new Error(`ffprobe failed with ${code || signal}`));
        } else {
          const output = Buffer.concat(resultBuffers).toString().trim();
          const match = output.match(/\n({.+})$/m);

          if (match) {
            const json = match[1];

            try {
              const data = JSON.parse(json);
              resolve(data);
            } catch (error) {
              reject(error);
            }
          } else {
            resolve({});
          }
        }
      });
    });
  },
};
