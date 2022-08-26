// Using the file-type NPM module, this attempts to identify MIME type of the
// state machine source artifact.

// @ts-ignore
// eslint-disable-next-line import/no-unresolved, import/no-absolute-path, import/extensions
import { fileTypeFromStream } from '/opt/nodejs/node_modules/file-type/index.js';

// @ts-ignore
// eslint-disable-next-line import/no-unresolved, import/no-absolute-path, import/extensions
import AWS from '/var/runtime/node_modules/aws-sdk/index.js';

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
// eslint-disable-next-line import/prefer-default-export
export const handler = async (event) => {
  const s3 = new AWS.S3({ apiVersion: '2006-03-01' });

  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const s3stream = s3
    .getObject({
      Bucket: event.Artifact.BucketName,
      Key: event.Artifact.ObjectKey,
      Range: `bytes=0-${MINIMUM_BYTES}`,
    })
    .createReadStream();

  // Eg. {ext: 'mov', mime: 'video/quicktime'}
  // Returns `undefined` when there is no match.
  const result = await fileTypeFromStream(s3stream);

  if (!result) {
    return {};
  }

  console.log(JSON.stringify({ msg: 'Result', result }));

  return {
    Extension: result.ext,
    MIME: result.mime,
  };
};
