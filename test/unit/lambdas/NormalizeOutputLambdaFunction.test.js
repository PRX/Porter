const {
  handler,
} = require('../../../lambdas/NormalizeOutputLambdaFunction/index');

test('includes Timestamp', async () => {
  const result = await handler({ Job: {} });
  expect(typeof result.Timestamp).toBe('number');
});

test('includes Time', async () => {
  const result = await handler({ Job: {} });
  expect(result.Time).toBe(new Date(result.Time).toISOString());
});
