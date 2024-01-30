import { join as pathJoin } from 'node:path';
import { tmpdir } from 'node:os';
import { unlinkSync, statSync } from 'node:fs';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { writeFile } from 'node:fs/promises';

import { inspect as audio } from './audio.js';
import { inspect as video } from './video.js';
import { inspect as image } from './image.js';

const s3 = new S3Client({
  apiVersion: '2006-03-01',
  followRegionRedirects: true,
});

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

/** Fetches the job's source file artifact from S3 and writes it to the Lambda
 * environment's local temp storage.
 * @returns {Promise<string>} Path to the file that was written
 */
async function writeArtifact(event, context) {
  const ext = event.Artifact.Descriptor.Extension;
  const tmpFilePath = pathJoin(tmpdir(), `${context.awsRequestId}.${ext}`);

  const { Body } = await s3.send(
    new GetObjectCommand({
      Bucket: event.Artifact.BucketName,
      Key: event.Artifact.ObjectKey,
    }),
  );

  // @ts-ignore
  await writeFile(tmpFilePath, Body);

  return tmpFilePath;
}

export const handler = async (event, context) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

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
    console.log(JSON.stringify({ event, inspection, tag: 'NO_LAYER' }));
  }

  return { Task: 'Inspect', Inspection: inspection };
};
