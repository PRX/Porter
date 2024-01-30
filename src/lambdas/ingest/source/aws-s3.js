import {
  S3Client,
  HeadObjectCommand,
  CopyObjectCommand,
  CreateMultipartUploadCommand,
  UploadPartCopyCommand,
  CompleteMultipartUploadCommand,
  AbortMultipartUploadCommand,
} from '@aws-sdk/client-s3';

const s3 = new S3Client({
  apiVersion: '2006-03-01',
  followRegionRedirects: true,
});

class AwsS3MultipartCopyError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'AwsS3MultipartCopyError';
  }
}

// https://aws.amazon.com/blogs/storage/copying-objects-greater-than-5-gb-with-amazon-s3-batch-operations/
// Look for max_concurrency for some info on performance tuning
async function multipartCopy(copySource, artifact, sourceObjectSize) {
  // Initialize the multipart upload
  const multipartUpload = await s3.send(
    new CreateMultipartUploadCommand({
      Bucket: artifact.BucketName, // Destination bucket
      Key: artifact.ObjectKey, // Destination object key
    }),
  );

  const uploadId = multipartUpload.UploadId;

  // All parts except the last part will be this size. The last part will be
  // whatever is left over, and always less than or equal to this.
  const MiB = 2 ** 20; // 2^20 bytes = 1 MiB
  const targetPartSizeInBytes = 16 * MiB; // min 5 MiB, max 5 GiB

  // There's a maximum of 10,000 parts per multi-part upload. Calculate the
  // size of each part if the source object were split into the maximum number
  // of parts. Parts are always a whole number of bytes, so round this value
  // up to the nearest byte, to always stay below 10,000 after dividing (i.e.,
  // err on the side of fewer parts).
  const maxPartCount = 10000; // Limit set by S3
  const minPartSizeInBytes = Math.ceil(sourceObjectSize / maxPartCount);

  // If the target part size is smaller than the minimum, it would result in
  // more than 10,000 parts. Use the minimum instead to have larger parts and
  // stay below the limit.
  const partSizeInBytes = Math.max(targetPartSizeInBytes, minPartSizeInBytes);

  // Calculate the byte ranges for each part of the source file that we're
  // going to upload, based on the target part size
  const partCount = Math.ceil(sourceObjectSize / partSizeInBytes);
  const partRanges = new Array(partCount).fill(0).map((r, idx) => {
    // For part size of 10, these would be: 0, 10, 20, etc
    const start = idx * partSizeInBytes;
    // For part size of 10 these would be: 9, 19, 29, etc
    // This can never be outside the range of the source file's size, and the
    // copy range is zero-based, so it maxes out at 1 less than the size of the
    // source file
    const end = Math.min(sourceObjectSize - 1, (idx + 1) * partSizeInBytes - 1);
    // E.g., with a part size of 10, and a file size of 26:
    // [0, 9], [10, 19], [20, 25]
    return [start, end];
  });

  try {
    // Copy all parts in parallel
    const uploads = await Promise.all(
      partRanges.map((range, idx) =>
        s3.send(
          new UploadPartCopyCommand({
            Bucket: artifact.BucketName, // Destination bucket
            Key: artifact.ObjectKey, // Destination object key
            PartNumber: idx + 1, // Positive integer between 1 and 10,000
            UploadId: uploadId,
            // CopySource expects: "/sourcebucket/path/to/object.extension"
            // CopySource expects "/sourcebucket/path/to/object.extension" to be URI-encoded
            CopySource: copySource,
            CopySourceRange: `bytes=${range.join('-')}`,
          }),
        ),
      ),
    );

    // Finalize the upload after all parts have been successfully copied
    await s3.send(
      new CompleteMultipartUploadCommand({
        Bucket: artifact.BucketName, // Destination bucket
        Key: artifact.ObjectKey, // Destination object key
        UploadId: uploadId,
        MultipartUpload: {
          Parts: uploads.map((u, idx) => ({
            ETag: u.CopyPartResult.ETag,
            PartNumber: idx + 1,
          })),
        },
      }),
    );
  } catch (error) {
    // Clean up the incomplete upload if it fails
    await s3.send(
      new AbortMultipartUploadCommand({
        Bucket: artifact.BucketName, // Destination bucket
        Key: artifact.ObjectKey, // Destination object key
        UploadId: uploadId,
      }),
    );

    throw new AwsS3MultipartCopyError('Multipart copy was aborted');
  }
}

export default async function main(event, artifact) {
  // CopySource expects: "/sourcebucket/path/to/object.extension"
  // CopySource expects "/sourcebucket/path/to/object.extension" to be URI-encoded
  const copySource = encodeURIComponent(
    `/${event.Job.Source.BucketName}/${event.Job.Source.ObjectKey}`,
  );

  const head = await s3.send(
    new HeadObjectCommand({
      Bucket: event.Job.Source.BucketName,
      Key: event.Job.Source.ObjectKey,
    }),
  );

  // S3 can perform a native copy of objects up to 5 GB using the CopyObject
  // API. For objects larger than 5 GB, a multi-part upload must be used.
  if (head.ContentLength < 5000000000) {
    // Copies an existing S3 object to the S3 artifact bucket.
    // https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property
    // https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectCOPY.html
    await s3.send(
      new CopyObjectCommand({
        CopySource: copySource,
        Bucket: artifact.BucketName,
        Key: artifact.ObjectKey,
      }),
    );
  } else {
    // Copies and object using parallelized copy operations for byte range
    // parts of the source object
    await multipartCopy(copySource, artifact, head.ContentLength);
  }
}
