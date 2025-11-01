import { inspect as ffprobe } from "./ffprobe.js";
import { ffprobeTags } from "./tags.js";
import { nmbr } from "./util.js";

/** @typedef {import('./index.js').InspectTask} InspectTask */
/** @typedef {import('./tags.js').Tag} Tag */

/**
 * @typedef {object} VideoInspection
 * @property {number} [Duration]
 * @property {string} [Format]
 * @property {string} [Aspect]
 * @property {number} [Width]
 * @property {number} [Height]
 * @property {number} [Framerate]
 * @property {Tag[]} [Tags]
 */

/**
 * @param {InspectTask} task
 * @param {string} filePath
 * @returns {Promise<VideoInspection>}
 */
export async function inspect(task, filePath) {
  /** @type {VideoInspection} */
  const inspection = {};

  // FFprobe data
  try {
    const probe = await ffprobe(filePath);
    const stream = probe.streams.find(
      (s) => s.codec_type === "video" && +s.duration > 0,
    );

    if (stream) {
      Object.assign(inspection, {
        ...(stream.duration && {
          Duration: Math.round(nmbr(stream.duration) * 1000),
        }),
        ...(stream.codec_name && { Format: stream.codec_name }),
        ...(stream.width && { Width: stream.width }),
        ...(stream.height && { Height: stream.height }),
        ...(stream.display_aspect_ratio && {
          Aspect: stream.display_aspect_ratio,
        }),
        ...(stream.r_frame_rate && { Framerate: nmbr(stream.r_frame_rate) }),
      });
    }
    const tags = probe.format?.tags;
    // Find tags in the format section that match the criteria
    if (tags && task.IncludeMetadata) {
      inspection.Tags = ffprobeTags(tags, task.IncludeMetadata);
    }
  } catch (error) {
    console.log(error);
  }

  // Only return the inspection result object if any keys were added
  if (Object.keys(inspection).length) {
    return inspection;
  }

  console.log("Video inspection yielded no results");
  return null;
}
