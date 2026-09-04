/** @import { ResultPayload, HlsResult } from "./types.js" */

/**
 * @param {ResultPayload} event
 * @returns {Promise<HlsResult>}
 */
export const handler = async (event) => {
  const objectKeyPrefix = event.Task.Destination.ObjectKeyPrefix;

  const variants = event.VariantResults.map((r) => {
    delete r.M3U8;
    return r;
  });

  return {
    Task: "HLS",
    Preset: event.Orchestration.Preset,
    Assets: {
      MasterPlaylist: {
        ObjectKey: [objectKeyPrefix, "index.m3u8"].join(""),
      },
      Variants: variants,
    },
  };
};
