const handler = require('../../NormalizeInputLambdaFunction/index').handler;

// Callbacks
test('inserts callbacks when not incldued', async () => {
  const result = await handler({ Job: {} });
  expect(result.Job.hasOwnProperty('Callbacks')).toBe(true);
  expect(result.Job.Callbacks).toEqual([]);
});

test('maintains empty callbacks array', async () => {
  const result = await handler({ Job: { Callbacks: [] } });
  expect(result.Job.Callbacks).toEqual([]);
});

test('non array callbacks replaced with empty array', async () => {
  const result = await handler({ Job: { Callbacks: {} } });
  expect(result.Job.Callbacks).toEqual([]);
});

// Copy
test('inserts copy when not included', async () => {
  const result = await handler({ Job: {} });

  expect(result.Job.hasOwnProperty('Copy')).toBe(true);
  expect(result.Job.Copy.hasOwnProperty('Perform')).toBe(true);
  expect(result.Job.Copy.Perform).toBe(false);
});

test('empty destinations is not performed', async () => {
  const result = await handler({ Job: { Copy: { Destinations: [] } } });

  expect(result.Job.Copy.hasOwnProperty('Perform')).toBe(true);
  expect(result.Job.Copy.Perform).toBe(false);
});

test('bogus destinations is not performed', async () => {
  const result = await handler({ Job: { Copy: { Destinations: 'bogus' } } });

  expect(result.Job.Copy.hasOwnProperty('Perform')).toBe(true);
  expect(result.Job.Copy.Perform).toBe(false);
});

test('copy with destinations is performed', async () => {
  const result = await handler({ Job: { Copy: { Destinations: [{}, {}] } } });

  expect(result.Job.Copy.hasOwnProperty('Perform')).toBe(true);
  expect(result.Job.Copy.Perform).toBe(true);
});

// Transcode
test('inserts transcode when not included', async () => {
  const result = await handler({ Job: {} });

  expect(result.Job.hasOwnProperty('Transcode')).toBe(true);
  expect(result.Job.Transcode.hasOwnProperty('Perform')).toBe(true);
  expect(result.Job.Transcode.Perform).toBe(false);
});

test('empty encodings is not performed', async () => {
  const result = await handler({ Job: { Transcode: { Encodings: [] } } });

  expect(result.Job.Transcode.hasOwnProperty('Perform')).toBe(true);
  expect(result.Job.Transcode.Perform).toBe(false);
});

test('bogus encodings is not performed', async () => {
  const result = await handler({ Job: { Transcode: { Encodings: 'bogus' } } });

  expect(result.Job.Transcode.hasOwnProperty('Perform')).toBe(true);
  expect(result.Job.Transcode.Perform).toBe(false);
});

test('transcode with encodings is performed', async () => {
  const result = await handler({ Job: { Transcode: { Encodings: [{}, {}] } } });

  expect(result.Job.Transcode.hasOwnProperty('Perform')).toBe(true);
  expect(result.Job.Transcode.Perform).toBe(true);
});

// Inspect
test('inserts inspect when not included', async () => {
  const result = await handler({ Job: {} });

  expect(result.Job.hasOwnProperty('Inspect')).toBe(true);
  expect(result.Job.Inspect.hasOwnProperty('Perform')).toBe(true);
  expect(result.Job.Inspect.Perform).toBe(false);
});

test('bogus inspect is not performed', async () => {
  const result = await handler({ Job: { Inspect: { Perform: 'bogus' } } });

  expect(result.Job.Inspect.hasOwnProperty('Perform')).toBe(true);
  expect(result.Job.Inspect.Perform).toBe(false);
});

test('inspect is not performed', async () => {
  const result = await handler({ Job: { Inspect: { Perform: false } } });

  expect(result.Job.Inspect.hasOwnProperty('Perform')).toBe(true);
  expect(result.Job.Inspect.Perform).toBe(false);
});

test('inspect is performed', async () => {
  const result = await handler({ Job: { Inspect: { Perform: true } } });

  expect(result.Job.Inspect.hasOwnProperty('Perform')).toBe(true);
  expect(result.Job.Inspect.Perform).toBe(true);
});
