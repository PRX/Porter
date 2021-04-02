const {
  handler,
} = require('../../../lambdas/NormalizeInputLambdaFunction/index');

test('inserts Tasks array when not included', async () => {
  const result = await handler({ Input: { Job: {} } });
  expect(Object.prototype.hasOwnProperty.call(result.Job, 'Tasks')).toBe(true);
  expect(result.Job.Tasks).toEqual([]);
});

test('replaces non-Array Tasks with array', async () => {
  const result = await handler({ Input: { Job: { Tasks: 42 } } });
  expect(Object.prototype.hasOwnProperty.call(result.Job, 'Tasks')).toBe(true);
  expect(result.Job.Tasks).toEqual([]);
});

test('maintains proper Tasks array', async () => {
  const result = await handler({
    Input: { Job: { Tasks: [{ Type: 'foo' }] } },
  });
  expect(Object.prototype.hasOwnProperty.call(result.Job, 'Tasks')).toBe(true);
  expect(result.Job.Tasks).toEqual([{ Type: 'foo' }]);
});

test('throws error on malform task', async () => {
  await expect(
    handler({ Input: { Job: { Tasks: [{ NoType: 'foo' }] } } }),
  ).rejects.toThrow();
});

test('Adds FFmpeg properties', async () => {
  const result = await handler({
    Input: { Job: { Tasks: [{ Type: 'Transcode' }] } },
  });
  expect(
    Object.prototype.hasOwnProperty.call(result.Job.Tasks[0], 'FFmpeg'),
  ).toBe(true);
  expect(
    Object.prototype.hasOwnProperty.call(
      result.Job.Tasks[0].FFmpeg,
      'GlobalOptions',
    ),
  ).toBe(true);
  expect(
    Object.prototype.hasOwnProperty.call(
      result.Job.Tasks[0].FFmpeg,
      'InputFileOptions',
    ),
  ).toBe(true);
  expect(
    Object.prototype.hasOwnProperty.call(
      result.Job.Tasks[0].FFmpeg,
      'OutputFileOptions',
    ),
  ).toBe(true);
});

test('inserts Callbacks array when not included', async () => {
  const result = await handler({ Input: { Job: {} } });
  expect(Object.prototype.hasOwnProperty.call(result.Job, 'Callbacks')).toBe(
    true,
  );
  expect(result.Job.Callbacks).toEqual([]);
});

test('replaces non-Array Callbacks with array', async () => {
  const result = await handler({ Input: { Job: { Callbacks: 42 } } });
  expect(Object.prototype.hasOwnProperty.call(result.Job, 'Callbacks')).toBe(
    true,
  );
  expect(result.Job.Callbacks).toEqual([]);
});

test('maintains proper Callbacks array', async () => {
  const result = await handler({
    Input: { Job: { Callbacks: [{ Foo: 'bar' }] } },
  });
  expect(Object.prototype.hasOwnProperty.call(result.Job, 'Callbacks')).toBe(
    true,
  );
  expect(result.Job.Callbacks).toEqual([{ Foo: 'bar' }]);
});

test('inserts SerializedJobs array when not included', async () => {
  const result = await handler({ Input: { Job: {} } });
  expect(
    Object.prototype.hasOwnProperty.call(result.Job, 'SerializedJobs'),
  ).toBe(true);
  expect(result.Job.SerializedJobs).toEqual([]);
});

test('replaces non-Array SerializedJobs with array', async () => {
  const result = await handler({ Input: { Job: { SerializedJobs: 42 } } });
  expect(
    Object.prototype.hasOwnProperty.call(result.Job, 'SerializedJobs'),
  ).toBe(true);
  expect(result.Job.SerializedJobs).toEqual([]);
});

test('maintains proper SerializedJobs array', async () => {
  const result = await handler({
    Input: { Job: { SerializedJobs: [{ Foo: 'bar' }] } },
  });
  expect(
    Object.prototype.hasOwnProperty.call(result.Job, 'SerializedJobs'),
  ).toBe(true);
  expect(result.Job.SerializedJobs).toEqual([{ Foo: 'bar' }]);
});

test('inserts ExecutionTrace array when not included', async () => {
  const result = await handler({ Input: { Job: {} } });
  expect(
    Object.prototype.hasOwnProperty.call(result.Job, 'ExecutionTrace'),
  ).toBe(true);
  expect(result.Job.ExecutionTrace).toEqual([]);
});

test('replaces non-Array ExecutionTrace with array', async () => {
  const result = await handler({ Input: { Job: { ExecutionTrace: 42 } } });
  expect(
    Object.prototype.hasOwnProperty.call(result.Job, 'ExecutionTrace'),
  ).toBe(true);
  expect(result.Job.ExecutionTrace).toEqual([]);
});

test('maintains proper ExecutionTrace array', async () => {
  const result = await handler({
    Input: { Job: { ExecutionTrace: [{ Foo: 'bar' }] } },
  });
  expect(
    Object.prototype.hasOwnProperty.call(result.Job, 'ExecutionTrace'),
  ).toBe(true);
  expect(result.Job.ExecutionTrace).toEqual([{ Foo: 'bar' }]);
});

test('state defaults to DONE', async () => {
  const result = await handler({ Input: { Job: {} } });
  expect(result.State).toEqual('DONE');
});
