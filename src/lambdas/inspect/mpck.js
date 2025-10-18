import { spawn } from "node:child_process";
import { tmpdir } from "node:os";
import { binDir } from "porter-util";

/**
 * @typedef {object} MpckResult
 * @property {string} [layer]
 * @property {number} [samples]
 * @property {number} [frames]
 * @property {number} [time]
 * @property {number} [unidentified]
 * @property {boolean} [vbr]
 */

/**
 * Uses pattern matching to extract structured data out of the mpck program
 * output
 * @param {string} output - The mpck program output
 * @returns {MpckResult}
 */
function extract(output) {
  console.log(JSON.stringify({ msg: "Raw mpck output", mpckOutput: output }));
  const result = {};

  const layer = output.match(/layer\s+([1-3])/);
  if (layer) {
    [, result.layer] = layer;
  }

  const frames = output.match(/frames\s+([0-9]+)/);
  if (frames) {
    result.frames = +frames[1];
  }

  const samples = output.match(/samples\s+([0-9]+)/);
  if (samples) {
    result.samples = +samples[1];
  }

  const unidentified = output.match(/unidentified\s+([0-9]+) b/);
  if (unidentified) {
    result.unidentified = +unidentified[1];
  }

  const time = output.match(/time\s+([0-9:.]+)/);
  if (time) {
    const parts = time[1].split(":");
    const min = +parts[0];
    const sec = +parts[1];
    const total = min * 60 + sec;

    result.time = total;
  }

  if (output.includes("(VBR)")) {
    result.vbr = true;
  }

  console.log(
    JSON.stringify({ msg: "mpck extraction", mpckExtraction: result }),
  );
  return result;
}

/**
 * @param {string} filePath
 * @returns {Promise<MpckResult>}
 */
export async function inspect(filePath) {
  return new Promise((resolve, reject) => {
    const start = process.hrtime();

    // mpck will nominally output something like:
    // SUMMARY: myAudio.mp3
    //     version                       MPEG v1.0
    //     layer                         3
    //     frames                        1682
    const childProc = spawn(binDir("mpck"), ["-v", filePath], {
      env: process.env,
      cwd: tmpdir(),
    });
    const resultBuffers = [];

    childProc.stdout.on("data", (buffer) => resultBuffers.push(buffer));
    childProc.stderr.on("data", (buffer) => console.error(buffer.toString()));

    childProc.on("exit", (code, signal) => {
      const end = process.hrtime(start);
      console.log(
        JSON.stringify({
          msg: "Finished mpck",
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
}
