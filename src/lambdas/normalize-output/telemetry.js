import {
  CloudWatchClient,
  PutMetricDataCommand,
} from '@aws-sdk/client-cloudwatch';

const cloudwatch = new CloudWatchClient({ apiVersion: '2010-08-01' });

/** @typedef {import("@aws-sdk/client-cloudwatch").MetricDatum} MetricDatum */

export default async function send(event) {
  // This is to avoid sending metrics during the test suite
  if (event.StateMachine) {
    // These are counted for all jobs
    /** @type {MetricDatum[]} */
    const metricsData = [
      // Count that the job completed; this does not mean it was successful
      {
        MetricName: 'JobsCompleted',
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
        MetricName: 'JobsCompleted',
        Dimensions: [
          {
            Name: 'StateMachineArn',
            Value: event.StateMachine.Id,
          },
          {
            Name: 'JobResultState',
            Value: event.Message.JobResult.State,
          },
        ],
        Value: 1,
        Unit: 'Count',
      },
      // Count the number of successful tasks
      {
        MetricName: 'TasksSucceeded',
        Dimensions: [
          {
            Name: 'StateMachineArn',
            Value: event.StateMachine.Id,
          },
        ],
        Value: event.Message.JobResult.TaskResults.length,
        Unit: 'Count',
      },
      // Count the number of failed tasks
      {
        MetricName: 'TasksFailed',
        Dimensions: [
          {
            Name: 'StateMachineArn',
            Value: event.StateMachine.Id,
          },
        ],
        Value: event.Message.JobResult.FailedTasks.length,
        Unit: 'Count',
      },
    ];

    const hasFailedTask = event.Message.JobResult.FailedTasks.length > 0;
    const hasJobProblem = event.Message.JobResult.State !== 'DONE';

    if (hasFailedTask || hasJobProblem) {
      // Any jobs with failed tasks or didn't complete in a DONE state are
      // considered failed
      metricsData.push({
        MetricName: 'JobsFailed',
        Dimensions: [
          {
            Name: 'StateMachineArn',
            Value: event.StateMachine.Id,
          },
        ],
        Value: 1,
        Unit: 'Count',
      });
    } else {
      // Count fully-successful jobs
      metricsData.push({
        MetricName: 'JobsSucceeded',
        Dimensions: [
          {
            Name: 'StateMachineArn',
            Value: event.StateMachine.Id,
          },
        ],
        Value: 1,
        Unit: 'Count',
      });
    }

    await cloudwatch.send(
      new PutMetricDataCommand({
        Namespace: 'PRX/Porter',
        MetricData: metricsData,
      }),
    );
  }
}
