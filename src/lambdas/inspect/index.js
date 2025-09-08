import { statSync, unlinkSync } from "node:fs";
import { writeArtifact } from "porter-util";

import { inspect as audio } from "./audio.js";
import { inspect as image } from "./image.js";
import { inspect as video } from "./video.js";

/** @typedef {import('./audio.js').AudioInspection} AudioInspection */
/** @typedef {import('./video.js').VideoInspection} VideoInspection */
/** @typedef {import('./image.js').ImageInspection} ImageInspection */

/**
 * @typedef {object} InspectTask
 * @property {string} Type
 * @property {boolean} [EBUR128]
 */

/**
 * @typedef {object} Inspection
 * @property {AudioInspection} [Audio]
 * @property {VideoInspection} [Video]
 * @property {ImageInspection} [Image]
 */

export const handler = async (event, context) => {
  console.log(JSON.stringify({ msg: "State input", input: event }));

  const artifactTmpPath = await writeArtifact(event, context);

  const stat = statSync(artifactTmpPath);

  const [audioInspection, videoInspection, imageInspection] = await Promise.all(
    [
      audio(event.Task, artifactTmpPath),
      video(event.Task, artifactTmpPath),
      image(event.Task, artifactTmpPath),
    ],
  );

  /** @type Inspection */
  const inspection = {
    Size: stat.size,
    ...event.Artifact.Descriptor,
    ...(audioInspection && { Audio: audioInspection }),
    ...(videoInspection && { Video: videoInspection }),
    ...(imageInspection && { Image: imageInspection }),
  };

  unlinkSync(artifactTmpPath);

  if (inspection.Audio && !inspection.Audio.Layer) {
    console.log(JSON.stringify({ event, inspection, tag: "NO_LAYER" }));
  }

  return { Task: "Inspect", Inspection: inspection };
};
