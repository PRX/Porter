const querystring = require('querystring');
const AWSXRay = require('aws-xray-sdk');

const http = AWSXRay.captureHTTPs(require('http'), false);
const https = AWSXRay.captureHTTPs(require('https'), false);

const {
  CloudWatchClient,
  PutMetricDataCommand,
} = require('@aws-sdk/client-cloudwatch');
const {
  EventBridgeClient,
  PutEventsCommand,
} = require('@aws-sdk/client-eventbridge');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { SNSClient, PublishCommand } = require('@aws-sdk/client-sns');
const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');
const { STSClient, AssumeRoleCommand } = require('@aws-sdk/client-sts');

const cloudwatchClient = new CloudWatchClient({});
const eventbridgeClient = new EventBridgeClient({});
const snsClient = new SNSClient({});
const sqsClient = new SQSClient({});
const stsClient = new STSClient({});

function httpRequest(event, message, redirectCount) {
  return new Promise((resolve, reject) => {
    const q = new URL(event.Callback.URL);

    const options = {
      host: q.host,
      port: q.port,
      path: `${q.pathname || ''}${q.search || ''}`,
      method: event.Callback.Method,
      headers: {},
    };

    let body;
    if (event.Callback['Content-Type'] === 'application/json') {
      body = JSON.stringify(message);
    } else if (
      event.Callback['Content-Type'] === 'application/x-www-form-urlencoded'
    ) {
      body = querystring.encode(message);
    } else if (event.Callback.Method === 'GET') {
      // TODO This will clobber an existing query string
      options.search = `${event.Callback.Name}=${querystring.encode(message)}`;
    } else {
      reject(new Error('Unknown HTTP Content-Type'));
    }

    options.headers['Content-Type'] = event.Callback['Content-Type'];
    options.headers['Content-Length'] = Buffer.byteLength(body);

    const h = options.protocol === 'https:' ? https : http;
    const req = h.request(options, (res) => {
      res.setEncoding('utf8');

      let resData = '';
      res.on('data', (chunk) => {
        resData += chunk;
        return resData;
      });

      res.on('end', async () => {
        if (
          (res.statusCode >= 200 && res.statusCode < 300) ||
          res.statusCode === 404 ||
          res.statusCode === 410
        ) {
          resolve();
        } else if (res.statusCode === 301 || res.statusCode === 302) {
          try {
            if (redirectCount > +process.env.MAX_HTTP_REDIRECTS) {
              reject(new Error('Too many redirects'));
            }

            console.log(
              JSON.stringify({
                msg: `Following HTTP redirect`,
                location: res.headers.location,
                count: redirectCount,
              }),
            );

            const count = redirectCount ? redirectCount + 1 : 1;
            await httpRequest(res.headers.location, message, count);
            resolve();
          } catch (error) {
            reject(error);
          }
        } else {
          const error = new Error(`Error ${res.statusCode}: ${resData}`);
          reject(error);
        }
      });
    });

    req.on('error', (error) => reject(error));

    req.write(body);
    req.end();
  });
}

async function s3Put(event, message) {
  const id = event.Execution.Id.split(':').pop();

  let key;
  if (message.JobReceived) {
    key = '/job_received.json';
  } else if (message.TaskResult) {
    key = `/task_result.${event.TaskIteratorIndex}.json`;
  } else if (message.JobResult) {
    key = '/job_result.json';
  } else {
    key = `/unknown_${+new Date()}.json`;
  }

  const role = await stsClient.send(
    new AssumeRoleCommand({
      RoleArn: process.env.S3_DESTINATION_WRITER_ROLE,
      RoleSessionName: 'porter_s3_callback',
    }),
  );

  const s3Client = new S3Client({
    credentials: {
      accessKeyId: role.Credentials.AccessKeyId,
      secretAccessKey: role.Credentials.SecretAccessKey,
      sessionToken: role.Credentials.SessionToken,
    },
  });

  await s3Client.send(
    new PutObjectCommand({
      Bucket: event.Callback.BucketName,
      Key: [event.Callback.ObjectPrefix, id, key].join(''),
      Body: JSON.stringify(message),
    }),
  );
}

async function eventBridgePutEvent(event, message, now) {
  // Assign values based on the type of callback message being sent, which is
  // detected by the precense of certain keys
  let DetailType;
  if (message.JobReceived) {
    DetailType = 'Porter Job Received Callback';
  } else if (message.TaskResult) {
    DetailType = 'Porter Task Result Callback';
  } else if (message.JobResult) {
    DetailType = 'Porter Job Result Callback';
  }

  await eventbridgeClient.send(
    new PutEventsCommand({
      Entries: [
        {
          Detail: JSON.stringify(message),
          DetailType,
          ...(event.Callback.EventBusName && {
            EventBusName: event.Callback.EventBusName,
          }),
          EventBusName: 'STRING_VALUE',
          Resources: [event.StateMachine.Id, event.Execution.Id],
          Source: 'org.prx.porter',
          Time: now,
        },
      ],
    }),
  );
}

async function putErrorMetric() {
  await cloudwatchClient.send(
    new PutMetricDataCommand({
      Namespace: 'PRX/Porter',
      MetricData: [
        {
          MetricName: 'ErrorCallbackMessagesSent',
          Dimensions: [
            {
              Name: 'LambdaFunctionName',
              Value: process.env.AWS_LAMBDA_FUNCTION_NAME,
            },
          ],
          Value: 1,
          Unit: 'Count',
        },
      ],
    }),
  );
}

/**
 * @param {object} event
 */
exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const now = new Date();
  const msg = { Time: now.toISOString(), Timestamp: +now / 1000 };

  if (event.Message) {
    Object.assign(msg, event.Message);
  }

  console.log(JSON.stringify({ msg: 'Callback message body', body: msg }));

  // Keep track of how many JobResult callbacks indicated any sort of job
  // execution problem in a custom CloudWatch Metric
  // TODO Maybe move this to its own Lambda; this is kind of a weird spot for it
  if (Object.prototype.hasOwnProperty.call(msg, 'JobResult')) {
    const hasFailedTask =
      Object.prototype.hasOwnProperty.call(msg.JobResult, 'FailedTasks') &&
      msg.JobResult.FailedTasks.length;
    const hasJobProblem =
      Object.prototype.hasOwnProperty.call(msg.JobResult, 'State') &&
      msg.JobResult.State !== 'DONE';

    if (hasFailedTask || hasJobProblem) {
      await putErrorMetric();
    }
  }

  if (event.Callback.Type === 'AWS/SNS') {
    const TopicArn = event.Callback.Topic;
    const Message = JSON.stringify(msg);

    await snsClient.send(new PublishCommand({ TopicArn, Message }));
  } else if (event.Callback.Type === 'AWS/SQS') {
    const QueueUrl = event.Callback.Queue;
    const MessageBody = JSON.stringify(msg);

    await sqsClient.send(new SendMessageCommand({ QueueUrl, MessageBody }));
  } else if (event.Callback.Type === 'AWS/S3') {
    await s3Put(event, msg);
  } else if (event.Callback.Type === 'AWS/EventBridge') {
    await eventBridgePutEvent(event, msg, now);
  } else if (event.Callback.Type === 'HTTP') {
    await httpRequest(event, msg);
  }
};
