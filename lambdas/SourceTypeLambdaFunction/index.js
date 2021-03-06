// Using the file-type NPM module, this attempts to identify MIME type of the
// state machine source artifact.

const fileType = require('file-type');
const AWSXRay = require('aws-xray-sdk');

const AWS = AWSXRay.captureAWS(require('aws-sdk'));

/** The number of bytes to use to detect a files type. */
const MINIMUM_BYTES = 4100;

/**
 * @typedef {object} SourceTypeResult
 * @property {string} [Extension]
 * @property {string} [MIME]
 */

/**
 * @param {object} event
 * @returns {Promise<SourceTypeResult>}
 */
exports.handler = async (event) => {
  const s3 = new AWS.S3({ apiVersion: '2006-03-01' });

  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const s3stream = s3
    .getObject({
      Bucket: event.Artifact.BucketName,
      Key: event.Artifact.ObjectKey,
      Range: `bytes=0-${MINIMUM_BYTES}`,
    })
    .createReadStream();

  const ftStream = await fileType.stream(s3stream);

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
