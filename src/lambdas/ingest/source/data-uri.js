import { Upload } from '@aws-sdk/lib-storage';
import { S3Client } from '@aws-sdk/client-s3';

const s3 = new S3Client({
  apiVersion: '2006-03-01',
  followRegionRedirects: true,
});

class InvalidDataUriError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'InvalidDataUriError';
  }
}

/**
 * Creates an object in S3 from a data URI
 * @param {object} event
 * @param {object} artifact
 */
export default async function main(event, artifact) {
  // e.g., data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7
  const uri = event.Job.Source.URI;

  if (!/^data:[\w/+-]+;base64,/.test(uri)) {
    throw new InvalidDataUriError('Invalid Data URI');
  }

  const base64Data = uri.split(';base64,')[1];

  const upload = new Upload({
    client: s3,
    params: {
      Bucket: artifact.BucketName,
      Key: artifact.ObjectKey,
      Body: Buffer.from(base64Data, 'base64'),
    },
  });
  await upload.done();
}
