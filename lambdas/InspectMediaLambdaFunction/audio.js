const ebur128 = require('./ebu-r-128');
const ffprobe = require('./ffprobe');
const mpck = require('./mpck');
const { nmbr } = require('./util');

/** @typedef {import('./index').InspectTask} InspectTask */

/**
 * @typedef {object} AudioInspection
 * @property {number} [Duration]
 * @property {string} [Format]
 * @property {number} [Bitrate]
 * @property {number} [Frequency]
 * @property {number} [Channels]
 * @property {string} [Layout]
 * @property {string} [Layer]
 * @property {number} [Samples]
 * @property {number} [Frames]
 * @property {number} [LoudnessIntegrated]
 * @property {number} [LoudnessTruePeak]
 * @property {number} [LoudnessRange]
 */

module.exports = {
  /**
   * @param {InspectTask} task
   * @param {string} filePath
   * @returns {Promise<AudioInspection>}
   */
  inspect: async function inspect(task, filePath) {
    /** @type {AudioInspection} */
    const inspection = {};

    // FFprobe data
    try {
      const probe = await ffprobe.inspect(filePath);
      const stream = probe.streams.find((s) => s.codec_type === 'audio');

      if (stream) {
        Object.assign(inspection, {
          ...(stream.duration && {
            Duration: Math.round(nmbr(stream.duration) * 1000),
          }),
          ...(stream.codec_name && { Format: stream.codec_name }),
          ...(stream.bit_rate && { Bitrate: nmbr(stream.bit_rate) }),
          ...(stream.sample_rate && { Frequency: nmbr(stream.sample_rate) }),
          ...(stream.channels && { Channels: stream.channels }),
          ...(stream.channel_layout && { Layout: stream.channel_layout }),
        });
      }
    } catch (error) {
      console.log(error);
    }

    // Additional inspection for mpeg streams
    if (['mp2', 'mp3'].includes(inspection.Format)) {
      try {
        let check;

        // mpck will occasionally not return any output, even though it doesn't
        // fail. Let it run a few times if necessary as a workaround.
        for (let i = 0; i < 5; i += 1) {
          console.log(JSON.stringify({ msg: 'mpck attempt', attempt: i }));
          // eslint-disable-next-line no-await-in-loop
          check = await mpck.inspect(filePath);

          console.log(
            JSON.stringify({ msg: 'mpck result', mpckResult: check }),
          );

          if (Object.keys(check).length) {
            break;
          }
        }

        if (check) {
          Object.assign(inspection, {
            ...(check.layer && { Layer: check.layer }),
            ...(check.frames && { Frames: check.frames }),
            ...(check.samples && { Samples: check.samples }),
            ...(check.unidentified && {
              UnidentifiedBytes: check.unidentified,
            }),
          });
        }
      } catch (error) {
        console.log(error);
      }
    }

    // Do EBU R 128 loudness measurement only if the task calls for it
    if (task.EBUR128 === true) {
      try {
        const loudness = await ebur128.inspect(filePath);

        if (loudness) {
          Object.assign(inspection, {
            ...(loudness.input_i && { LoudnessIntegrated: +loudness.input_i }),
            ...(loudness.input_tp && { LoudnessTruePeak: +loudness.input_tp }),
            ...(loudness.input_lra && { LoudnessRange: +loudness.input_lra }),
          });
        }
      } catch (error) {
        console.log(error);
      }
    }

    // Only return the inspection result object if any keys were added
    if (Object.keys(inspection).length) {
      return inspection;
    }

    console.log('Audio inspection yielded no results');
    return null;
  },
};
