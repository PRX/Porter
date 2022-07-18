const AWS = require('aws-sdk-mock');
const fs = require('fs');

const { handler } = require('../../../src/lambdas/wav-wrap/index');

test('wraps an mp2', async () => {
  AWS.mock('S3', 'getObject', {
    Body: Buffer.from(fs.readFileSync('test/samples/test.mp2')),
  });
  // TODO
  AWS.mock('S3', 'putObject', true);
  AWS.mock('STS', 'assumeRole', {
    Credentials: { SecretAccessKey: 'key', SessionToken: 'token' },
  });
  process.env.S3_DESTINATION_WRITER_ROLE = 'arn:thisisafake';

  const result = await handler({
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
        ContentType: 'audio/wav',
      },
      Chunks: [
        {
          ChunkId: 'cart',
          Version: '0101',
          CutId: '30000',
          Title:
            'SOUNDOPI: 20191129: 731: 06: Thanksgiving Leftovers & DJ Shadow',
          Artist: 'Sound Opinions',
          StartDate: '2020/05/31',
          StartTime: '10:00:00',
          EndDate: '2020/06/10',
          EndTime: '10:00:00',
          ProducerAppId: 'PRX',
          ProducerAppVersion: '3.0',
        },
      ],
    },
  });

  // console.log("WavWrapLambdaFunction result", result);
  const cartChunk = result.WavefileChunks[0];
  expect(cartChunk.chunkId).toEqual('cart');
  expect(cartChunk.version).toEqual('0101');
  expect(cartChunk.cutId).toEqual('30000');
  expect(cartChunk.title).toEqual(
    'SOUNDOPI: 20191129: 731: 06: Thanksgiving Leftovers & DJ Shadow',
  );
  expect(cartChunk.artist).toEqual('Sound Opinions');

  AWS.restore('STS');
  AWS.restore('S3');
});
