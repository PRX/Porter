const ebur128 = require('./ebu-r-128');
const ffprobe = require('./ffprobe');
const mpck = require('./mpck');

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
          Duration: Math.round(+stream.duration * 1000),
          Format: stream.codec_name,
          Bitrate: +stream.bit_rate,
          Frequency: +stream.sample_rate,
          Channels: stream.channels,
          Layout: stream.channel_layout,
        });
      }
    } catch (error) {
      console.log(error);
    }

    // Additional inspection for MP3 streams
    if (inspection.Format === 'mp3') {
      try {
        const check = await mpck.inspect(filePath);

        if (check) {
          Object.assign(inspection, {
            Layer: check.layer,
            Frames: check.frames,
            Samples: check.samples,
            UnidentifiedBytes: check.unidentified,
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
            LoudnessIntegrated: +loudness.input_i,
            LoudnessTruePeak: +loudness.input_tp,
            LoudnessRange: +loudness.input_lra,
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
