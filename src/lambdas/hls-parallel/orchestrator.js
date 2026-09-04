/** @import { Payload, Orchestration } from "./types.js" */

import std2026v1 from "./presets/standard_podcast_2026_v1.js";

class UnknownPresetError extends Error {
  constructor(...params) {
    super(...params);
    this.name = "UnknownPresetError";
  }
}

/**
 * @param {Payload} event
 * @returns {Promise<Orchestration>}
 */
export const handler = async (event) => {
  if (event.Task.Preset === "Standard Podcast 2026 v1") {
    return std2026v1(event.Task);
  }

  throw new UnknownPresetError("Unexpected HLS preset");
};
