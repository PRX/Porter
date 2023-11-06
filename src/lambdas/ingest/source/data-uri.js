import { Upload } from '@aws-sdk/lib-storage';
import { S3 } from '@aws-sdk/client-s3';

const s3 = new S3();

class InvalidDataUriError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'InvalidDataUriError';
  }
}

export default async function main(event, artifact) {
  // e.g., data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7
  const uri = event.Job.Source.URI;

  if (!/^data:[\w/+-]+;base64,/.test(uri)) {
    throw new InvalidDataUriError('Invalid Data URI');
  }

  const base64Data = uri.split(';base64,')[1];

  await new Upload({
    client: s3,
    params: {
      Bucket: artifact.BucketName,
      Key: artifact.ObjectKey,
      Body: Buffer.from(base64Data, 'base64'),
    },
  }).done();
}
