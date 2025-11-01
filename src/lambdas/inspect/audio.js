import { inspect as ebur128 } from "./ebu-r-128.js";
import { inspect as ffprobe } from "./ffprobe.js";
import { inspect as mpck } from "./mpck.js";
import { nmbr } from "./util.js";
import { ffprobeTags } from "./tags.js";

/** @typedef {import('./index.js').InspectTask} InspectTask */
/** @typedef {import('./tags.js').Tag} Tag */

/**
 * @typedef {object} AudioInspection
 * @property {number} [Duration]
 * @property {number} [DurationDiscrepancy]
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
 * @property {number} [UnidentifiedBytes]
 * @property {Tag[]} [Tags]
 */

/**
 * @param {InspectTask} task
 * @param {string} filePath
 * @returns {Promise<AudioInspection>}
 */
export async function inspect(task, filePath) {
  /** @type {AudioInspection} */
  const inspection = {};

  // FFprobe data
  try {
    const probe = await ffprobe(filePath);
    const stream = probe.streams.find((s) => s.codec_type === "audio");

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

    const tags = probe.format?.tags;
    // Find tags in the format section that match the criteria
    if (tags && task.IncludeMetadata) {
      inspection.Tags = ffprobeTags(tags, task.IncludeMetadata);
    }
  } catch (error) {
    console.log(error);
  }

  // Additional inspection for mpeg streams
  if (["mp2", "mp3"].includes(inspection.Format)) {
    try {
      let check;

      // mpck will occasionally not return any output, even though it doesn't
      // fail. Let it run a few times if necessary as a workaround.
      for (let i = 0; i < 5; i += 1) {
        console.log(JSON.stringify({ msg: "mpck attempt", attempt: i }));
        // eslint-disable-next-line no-await-in-loop
        check = await mpck(filePath);

        console.log(JSON.stringify({ msg: "mpck result", mpckResult: check }));

        if (Object.keys(check).length) {
          break;
        }
      }

      if (check) {
        // The duration reported by a previous analysis (usually FFmpeg)
        const otherDuration = inspection.Duration;
        // The duration as calculated by mpck. If present, this will replace
        // any duration previously added to the inspection result
        const mpckDuration = check.time && Math.round(nmbr(check.time) * 1000);

        const durationDiscrepancy =
          otherDuration &&
          mpckDuration &&
          Math.abs(otherDuration - mpckDuration);

        Object.assign(inspection, {
          ...(check.layer && { Layer: check.layer }),
          ...(check.frames && { Frames: check.frames }),
          ...(check.samples && { Samples: check.samples }),
          ...(mpckDuration && { Duration: mpckDuration }),
          ...(durationDiscrepancy && {
            DurationDiscrepancy: durationDiscrepancy,
          }),
          ...(check.unidentified && {
            UnidentifiedBytes: check.unidentified,
          }),
          ...(check.vbr && { VariableBitrate: true }),
        });
      }
    } catch (error) {
      console.log(error);
    }
  }

  // Do EBU R 128 loudness measurement only if the task calls for it
  if (task.EBUR128 === true) {
    try {
      const loudness = await ebur128(filePath);

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

  console.log("Audio inspection yielded no results");
  return null;
}
