// Using the file-type NPM module, this attempts to identify MIME type of the
// state machine source artifact.

const fileType = require('file-type');
const { S3Client, GetObjectCommand } = require('@aws-sdk/client-s3');

const s3Client = new S3Client({});

/** The number of bytes to use to detect a files type. */
const MINIMUM_BYTES = 4100;

/**
 * @typedef {object} SourceTypeResult
 * @property {string} [Extension]
 * @property {string} [MIME]
 */

/** @typedef {import('stream')} Readable */
/**
 * @param {*} s3ObjectBody
 * @return {s3ObjectBody is Readable}
 */
function bodyIsReadable(s3ObjectBody) {
  if (Object.prototype.hasOwnProperty.call(s3ObjectBody, 'pipe')) {
    return true;
  }

  return false;
}

/**
 * @param {object} event
 * @returns {Promise<SourceTypeResult>}
 */
exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const s3Object = await s3Client.send(
    new GetObjectCommand({
      Bucket: event.Artifact.BucketName,
      Key: event.Artifact.ObjectKey,
      Range: `bytes=0-${MINIMUM_BYTES}`,
    }),
  );

  let ftStream;
  if (bodyIsReadable(s3Object.Body)) {
    ftStream = await fileType.stream(s3Object.Body);
  } else {
    throw new Error('Unexpected S3 object Body type');
  }

  // Eg. {ext: 'mov', mime: 'video/quicktime'}
  // Returns `undefined` when there is no match.
  const result = ftStream.fileType;

  if (!result) {
    return {};
  }

  console.log(JSON.stringify({ msg: 'Result', result }));

  return {
    Extension: result.ext,
    MIME: result.mime,
  };
};
