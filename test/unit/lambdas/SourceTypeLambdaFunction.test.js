const AWS = require('aws-sdk-mock');
const fs = require('fs');

const {
  handler,
} = require('../../../src/lambdas/SourceTypeLambdaFunction/index');

test('detects type for S3 objects', async () => {
  AWS.mock(
    'S3',
    'getObject',
    Buffer.from(fs.readFileSync('test/samples/jpg.jpg')),
  );

  const result = await handler({
    Artifact: {
      BucketName: 'myBucket',
      ObjectKey: 'foo.bar',
    },
  });

  expect(result.Extension).toEqual('jpg');

  AWS.restore('S3');
});

test('detects type for S3 objects with goofy extensions', async () => {
  AWS.mock(
    'S3',
    'getObject',
    Buffer.from(fs.readFileSync('test/samples/jpg.png')),
  );

  const result = await handler({
    Artifact: {
      BucketName: 'myBucket',
      ObjectKey: 'foo.bar',
    },
  });

  expect(result.Extension).toEqual('jpg');

  AWS.restore('S3');
});

test('does not detects type for undetectable S3 objects', async () => {
  AWS.mock(
    'S3',
    'getObject',
    Buffer.from(fs.readFileSync('test/samples/empty')),
  );

  const result = await handler({
    Artifact: {
      BucketName: 'myBucket',
      ObjectKey: 'foo.bar',
    },
  });

  expect(result.Extension).toBeUndefined();

  AWS.restore('S3');
});
