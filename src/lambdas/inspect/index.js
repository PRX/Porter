const path = require('path');
const os = require('os');
const fs = require('fs');
const aws = require('aws-sdk');
const audio = require('./audio');
const video = require('./video');
const image = require('./image');

const s3 = new aws.S3();

/** @typedef {import('./audio').AudioInspection} AudioInspection */
/** @typedef {import('./video').VideoInspection} VideoInspection */
/** @typedef {import('./image').ImageInspection} ImageInspection */

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
 * @param {string} bucket
 * @param {string} fileKey
 * @param {string} filePath
 */
function s3GetObject(bucket, fileKey, filePath) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(filePath);
    const stream = s3
      .getObject({
        Bucket: bucket,
        Key: fileKey,
      })
      .createReadStream();

    stream.on('error', reject);
    file.on('error', reject);

    file.on('finish', () => {
      resolve(filePath);
    });

    stream.pipe(file);
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

exports.handler = async (event, context) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const artifactFileTmpPath = path.join(os.tmpdir(), context.awsRequestId);
  await fetchArtifact(event, artifactFileTmpPath);

  const stat = fs.statSync(artifactFileTmpPath);

  const [audioInspection, videoInspection, imageInspection] = await Promise.all(
    [
      audio.inspect(event.Task, artifactFileTmpPath),
      video.inspect(event.Task, artifactFileTmpPath),
      image.inspect(event.Task, artifactFileTmpPath),
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

  fs.unlinkSync(artifactFileTmpPath);

  if (inspection.Audio && !inspection.Audio.Layer) {
    console.log(JSON.stringify({ event, inspection, tag: 'NO_LAYER' }));
  }

  return { Task: 'Inspect', Inspection: inspection };
};
