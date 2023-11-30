// eslint-disable-next-line import/no-extraneous-dependencies
import { Upload } from '@aws-sdk/lib-storage';
import { S3Client } from '@aws-sdk/client-s3';

const s3 = new S3Client({ apiVersion: '2006-03-01' });

/**
 * Requests a file over HTTP and streams it to S3
 * @param {object} event
 * @param {object} artifact
 */
export default async function main(event, artifact) {
  const res = await fetch(event.Job.Source.URL, {
    method: 'GET',
    headers: {
      'User-Agent': 'PRX-Porterbot/1.0 (+https://github.com/PRX/Porter)',
    },
  });

  console.log(
    JSON.stringify({
      msg: 'HTTP request',
      originalURL: event.Job.Source.URL,
      finalURL: res.url, // Reflects any redirects that were followed
      status: res.status,
      headers: res.headers,
    }),
  );

  if (res.ok) {
    const upload = new Upload({
      client: s3,
      params: {
        Bucket: artifact.BucketName,
        Key: artifact.ObjectKey,
        Body: res.body,
      },
    });
    await upload.done();
  } else {
    // fetch() does not throw on HTTP errors, only connection errors, so any
    // bad responses we throw manually
    throw new Error(res.statusText);
  }
}
