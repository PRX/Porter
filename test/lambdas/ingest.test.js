const filenameFromSource = require('../../IngestLambdaFunction/index').filenameFromSource;

test('extracts filenames from flat S3 objects', async () => {
  const filename = filenameFromSource({ Mode: 'AWS/S3', BucketName: 'myBucket', ObjectKey: 'foo.bar' });
  expect(filename).toEqual('foo.bar');
});

test('extracts filenames from deep S3 objects', async () => {
  const filename = filenameFromSource({ Mode: 'AWS/S3', BucketName: 'myBucket', ObjectKey: 'a/b/c/d/e/foo.bar' });
  expect(filename).toEqual('foo.bar');
});

test('extracts filenames from simple HTTP URLs', async () => {
  const filename = filenameFromSource({ Mode: 'HTTP', URL: 'http://example.com/foo.bar' });
  expect(filename).toEqual('foo.bar');
});

test('extracts filenames from HTTP URLs with query string', async () => {
  const filename = filenameFromSource({ Mode: 'HTTP', URL: 'http://example.com/foo.bar?baz=1' });
  expect(filename).toEqual('foo.bar');
});

test('extracts filenames from complex HTTP URLs', async () => {
  const filename = filenameFromSource({ Mode: 'HTTP', URL: 'http://example.com:8888/path/to/foo.bar?baz=1#boo' });
  expect(filename).toEqual('foo.bar');
});

test('extracts filenames from root HTTP URLs', async () => {
  const filename = filenameFromSource({ Mode: 'HTTP', URL: 'http://example.com/' });
  expect(filename).toEqual('example.com');
});
