const ffprobe = require('./ffprobe');

/** @typedef {import('./index').InspectTask} InspectTask */

/**
 * @typedef {object} VideoInspection
 * @property {number} [Duration]
 * @property {string} [Format]
 * @property {string} [Aspect]
 * @property {number} [Width]
 * @property {number} [Height]
 * @property {number} [Framerate]
 */

module.exports = {
  /**
   * @param {InspectTask} task
   * @param {string} filePath
   * @returns {Promise<VideoInspection>}
   */
  inspect: async function inspect(task, filePath) {
    /** @type {VideoInspection} */
    const inspection = {};

    // FFprobe data
    try {
      const probe = await ffprobe.inspect(filePath);
      const stream = probe.streams.find(
        (s) => s.codec_type === 'video' && +s.duration > 0,
      );

      if (stream) {
        Object.assign(inspection, {
          Duration: Math.round(+stream.duration * 1000),
          Format: stream.codec_name,
          Width: stream.width,
          Height: stream.height,
          Aspect: stream.display_aspect_ratio,
          // r_frame_rate may be expressed as a string ratio, e.g. "24000/1001"
          Framerate: +eval(stream.r_frame_rate),
        });
      }
    } catch (error) {
      console.log(error);
    }

    // Only return the inspection result object if any keys were added
    if (Object.keys(inspection).length) {
      return inspection;
    }

    console.log('Video inspection yielded no results');
    return;
  },
};
