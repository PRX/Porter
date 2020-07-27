const handler = require('../../../lambdas/WavWrapLambdaFunction/index').handler;

const AWS = require('aws-sdk-mock');

// Callbacks
test('wraps an mp2', async () => {
  AWS.mock('S3', 'getObject', {
    Body: Buffer.from(require('fs').readFileSync('test/samples/test.mp2')),
  });
  AWS.mock('S3', 'upload', true);
  AWS.mock('STS', 'assumeRole', {
    Credentials: { SecretAccessKey: 'key', SessionToken: 'token' },
  });
  process.env.S3_DESTINATION_WRITER_ROLE = 'arn:thisisafake';

  const result = await handler(
    {
      Artifact: {
        BucketName: 'myStackName-artifactbucket-1hnyu12xzvbel',
        ObjectKey:
          'test000-1111-aaaa-2222-616797212639/c6cd0af8-ac3d-424b-bbb7-fac5f9189a60/test.mp2',
        Descriptor: {
          Extension: 'mp2',
          MIME: 'audio/mpeg',
        },
      },
      Task: {
        Mode: 'AWS/S3',
        BucketName: 'SourceBucket',
        ObjectKey: 'test.mp2',
        Destination: {
          Mode: 'AWS/S3',
          BucketName: 'myStackName-artifactbucket-1hnyu12xzvbel',
          ObjectKey: 'wxyz/sound-opinions/30000.wav',
        },
        Chunks: {
          cart: {
            version: '0101',
            cutId: '30000',
            title:
              'SOUNDOPI: 20191129: 731: 06: Thanksgiving Leftovers & DJ Shadow',
            artist: 'Sound Opinions',
            startDate: '2020/05/31',
            startTime: '10:00:00',
            endDate: '2020/06/10',
            endTime: '10:00:00',
            producerAppId: 'PRX',
            producerAppVersion: '3.0',
          },
        },
      },
    },
    { awsRequestId: '12345abcde' },
  );

  AWS.restore('STS');
  AWS.restore('S3');
});
