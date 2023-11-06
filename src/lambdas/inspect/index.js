import { join as pathJoin } from 'node:path';
import { tmpdir } from 'node:os';
import { unlinkSync, statSync, createWriteStream } from 'node:fs';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';

import { inspect as audio } from './audio.js';
import { inspect as video } from './video.js';
import { inspect as image } from './image.js';

const s3 = new S3Client();

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

/**
 * Downloads the given S3 object to a local file path
 * @param {string} bucketName
 * @param {string} objectKey
 * @param {string} filePath
 */
function s3GetObject(bucketName, objectKey, filePath) {
  // eslint-disable-next-line no-async-promise-executor
  return new Promise(async (resolve, reject) => {
    const file = createWriteStream(filePath);

    const resp = await s3.send(
      new GetObjectCommand({
        Bucket: bucketName,
        Key: objectKey,
      }),
    );

    const stream = resp.Body;

    // @ts-ignore
    stream.pipe(file);

    // @ts-ignore
    stream.on('error', reject);
    file.on('error', reject);

    file.on('finish', () => {
      resolve(filePath);
    });
  });
}

/**
 * Downloads the artifact from the Lambda input to a local file path
 * @param {object} event
 * @param {string} filePath
 */
async function fetchArtifact(event, filePath) {
  console.log(
    JSON.stringify({
      msg: 'Fetching artifact from S3',
      s3: `${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
      fs: filePath,
    }),
  );

  const s3start = process.hrtime();
  await s3GetObject(
    event.Artifact.BucketName,
    event.Artifact.ObjectKey,
    filePath,
  );

  const s3end = process.hrtime(s3start);
  console.log(
    JSON.stringify({
      msg: 'Fetched artifact from S3',
      duration: `${s3end[0]} s ${s3end[1] / 1000000} ms`,
    }),
  );
}

export const handler = async (event, context) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const artifactFileTmpPath = pathJoin(tmpdir(), context.awsRequestId);
  await fetchArtifact(event, artifactFileTmpPath);

  const stat = statSync(artifactFileTmpPath);

  const [audioInspection, videoInspection, imageInspection] = await Promise.all(
    [
      audio(event.Task, artifactFileTmpPath),
      video(event.Task, artifactFileTmpPath),
      image(event.Task, artifactFileTmpPath),
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

  unlinkSync(artifactFileTmpPath);

  if (inspection.Audio && !inspection.Audio.Layer) {
    console.log(JSON.stringify({ event, inspection, tag: 'NO_LAYER' }));
  }

  return { Task: 'Inspect', Inspection: inspection };
};
