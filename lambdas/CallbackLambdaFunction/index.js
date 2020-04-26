const url = require('url');
const querystring = require('querystring');
const AWSXRay = require('aws-xray-sdk');

const AWS = AWSXRay.captureAWS(require('aws-sdk'));
const http = AWSXRay.captureHTTPs(require('http'));
const https = AWSXRay.captureHTTPs(require('https'));

const sns = new AWS.SNS({ apiVersion: '2010-03-31' });
const sqs = new AWS.SQS({ apiVersion: '2012-11-05' });
const sts = new AWS.STS({ apiVersion: '2011-06-15' });
const cloudwatch = new AWS.CloudWatch({ apiVersion: '2010-08-01' });

function httpRequest(event, message, redirectCount) {
  return new Promise((resolve, reject) => {
    const options = url.parse(event.Callback.URL);
    options.method = event.Callback.Method;
    options.headers = {};

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
    const req = h.request(options, res => {
      res.setEncoding('utf8');

      let resData = '';
      res.on('data', (chunk) => (resData += chunk));

      res.on('end', async () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
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
  let key;
  let id;

  if (message.JobReceived) {
    id = message.JobReceived.Execution.Id.split(':').pop();
    key = '/job_received.json';
  } else if (message.TaskResult) {
    id = message.TaskResult.Execution.Id.split(':').pop();
    key = `/task_result.${event.TaskIteratorIndex}.json`;
  } else if (message.JobResult) {
    id = message.JobResult.Execution.Id.split(':').pop();
    key = '/job_result.json';
  } else {
    id = message.JobResult.Execution.Id.split(':').pop();
    key = `/unknown_${+new Date()}.json`;
  }

  const role = await sts
    .assumeRole({
      RoleArn: process.env.S3_DESTINATION_WRITER_ROLE,
      RoleSessionName: 'porter_s3_callback',
    })
    .promise();

  const s3 = new AWS.S3({
    apiVersion: '2006-03-01',
    accessKeyId: role.Credentials.AccessKeyId,
    secretAccessKey: role.Credentials.SecretAccessKey,
    sessionToken: role.Credentials.SessionToken,
  });

  await s3
    .putObject({
      Bucket: event.Callback.BucketName,
      Key: [event.Callback.ObjectPrefix, id, key].join(''),
      Body: JSON.stringify(message),
    })
    .promise();
}

async function putErrorMetric() {
  await cloudwatch
    .putMetricData({
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
    })
    .promise();
}

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const now = new Date();
  const msg = { Time: now.toISOString(), Timestamp: now / 1000 };

  if (event.Message) {
    Object.assign(msg, event.Message);
  }

  console.log(JSON.stringify({ msg: 'Callback message body', body: msg }));

  // Keep track of how many JobResult callbacks indicated any sort of job
  // execution problem in a custom CloudWatch Metric
  // TODO Maybe move this to its own Lambda; this is kind of a weird spot for it
  if (msg.hasOwnProperty('JobResult')) {
    const hasFailedTask =
      msg.JobResult.hasOwnProperty('FailedTasks') &&
      msg.JobResult.FailedTasks.length;
    const hasJobProblem =
      msg.JobResult.hasOwnProperty('State') && msg.JobResult.State !== 'DONE';

    if (hasFailedTask || hasJobProblem) {
      await putErrorMetric();
    }
  }

  if (event.Callback.Type === 'AWS/SNS') {
    const TopicArn = event.Callback.Topic;
    const Message = JSON.stringify(msg);

    await sns.publish({ Message, TopicArn }).promise();
  } else if (event.Callback.Type === 'AWS/SQS') {
    const QueueUrl = event.Callback.Queue;
    const MessageBody = JSON.stringify(msg);

    await sqs.sendMessage({ QueueUrl, MessageBody }).promise();
  } else if (event.Callback.Type === 'AWS/S3') {
    await s3Put(event, msg);
  } else if (event.Callback.Type === 'HTTP') {
    await httpRequest(event, msg);
  }
};
