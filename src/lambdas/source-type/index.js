// Using the file-type NPM module, this attempts to identify MIME type of the
// state machine source artifact.

import { S3Client } from "@aws-sdk/client-s3";
// eslint-disable-next-line import/no-unresolved
import { makeChunkedTokenizerFromS3 } from "@tokenizer/s3";
import { fileTypeFromTokenizer } from "file-type";

const s3 = new S3Client({
  apiVersion: "2006-03-01",
  followRegionRedirects: true,
});

/**
 * @typedef {object} SourceTypeResult
 * @property {string} [Extension]
 * @property {string} [MIME]
 */

/**
 * @param {object} event
 * @returns {Promise<SourceTypeResult>}
 */
export const handler = async (event) => {
  console.log(JSON.stringify({ msg: "State input", input: event }));

  const s3Tokenizer = await makeChunkedTokenizerFromS3(s3, {
    Bucket: event.Artifact.BucketName,
    Key: event.Artifact.ObjectKey,
  });

  // Eg. {ext: 'mov', mime: 'video/quicktime'}
  // Returns `undefined` when there is no match.
  const fileType = await fileTypeFromTokenizer(s3Tokenizer);

  if (!fileType) {
    return {};
  }

  console.log(JSON.stringify({ msg: "Result", result: fileType }));

  return {
    Extension: fileType.ext,
    MIME: fileType.mime,
  };
};
