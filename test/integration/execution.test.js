// require('dotenv').config();

// const AWS = require('aws-sdk');
// const stepfunctions = new AWS.StepFunctions({
//   apiVersion: '2016-11-23',
//   region: 'us-east-1',
// });

test('integration test', async () => {
  //   expect.assertions(1);
  //   const req = await stepfunctions
  //     .startExecution({
  //       stateMachineArn: process.env.PORTER_STATE_MACHINE_ARN,
  //       input: JSON.stringify({
  //         Job: {
  //           Id: 'porter-test-no-op',
  //           Source: {
  //             Mode: 'HTTP',
  //             URL: 'http://example.com/',
  //           },
  //         },
  //       }),
  //     })
  //     .promise();
  //   await new Promise((r) => setTimeout(r, 5000));
  //   const desc = await stepfunctions
  //     .describeExecution({
  //       executionArn: req.executionArn,
  //     })
  //     .promise();
  //   const output = JSON.parse(desc.output);
  //   await expect(output.JobResult.Job.Id).resolves().toEqual('porter-test-no-op');
});
