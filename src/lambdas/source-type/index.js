// Using the file-type NPM module, this attempts to identify MIME type of the
// state machine source artifact.

// Lambda doesn't currently support easy ESM imports from Lambda layers, so
// the import has to use a static path.
// @ts-ignore
// eslint-disable-next-line import/no-unresolved, import/no-absolute-path, import/extensions
import { fileTypeFromTokenizer } from '/opt/nodejs/node_modules/file-type/index.js';

// @ts-ignore
// eslint-disable-next-line import/no-unresolved, import/no-absolute-path, import/extensions
import { makeTokenizer } from '/opt/nodejs/node_modules/@tokenizer/s3';

// Lambda doesn't currently support easy ESM imports from where the native
// aws-sdk is installed, so the import has to use a static path.
// @ts-ignore
// eslint-disable-next-line import/no-unresolved, import/no-absolute-path, import/extensions
import AWS from '/var/runtime/node_modules/aws-sdk/index.js';

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

  const s3Tokenizer = await makeTokenizer(s3, {
    Bucket: event.Artifact.BucketName,
    Key: event.Artifact.ObjectKey,
  });
  const result = await fileTypeFromTokenizer(s3Tokenizer);

  if (!result) {
    return {};
  }

  console.log(JSON.stringify({ msg: 'Result', result }));

  return {
    Extension: result.ext,
    MIME: result.mime,
  };
};
