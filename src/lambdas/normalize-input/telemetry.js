/* eslint-disable import/no-extraneous-dependencies */
const AWS = require('aws-sdk');

const cloudwatch = new AWS.CloudWatch({ apiVersion: '2010-08-01' });

module.exports = {
  async send(event) {
    // This is to avoid sending metrics during the test suite
    if (event.StateMachine) {
      await cloudwatch
        .putMetricData({
          Namespace: 'PRX/Porter',
          MetricData: [
            {
              MetricName: 'JobsStarted',
              Dimensions: [
                {
                  Name: 'StateMachineArn',
                  Value: event.StateMachine.Id,
                },
              ],
              Value: 1,
              Unit: 'Count',
            },
            {
              MetricName: 'TasksRequested',
              Dimensions: [
                {
                  Name: 'StateMachineArn',
                  Value: event.StateMachine.Id,
                },
              ],
              Value: event.Input.Job.Tasks.length,
              Unit: 'Count',
            },
          ],
        })
        .promise();
    }
  },
};
