const url = require('url');
const querystring = require('querystring');
const http = require('http');
const https = require('https');
const AWSXRay = require('aws-xray-sdk');

const AWS = AWSXRay.captureAWS(require('aws-sdk'));

const sns = new AWS.SNS({ apiVersion: '2010-03-31' });
const sqs = new AWS.SQS({ apiVersion: '2012-11-05' });

function httpRequest(event, message) {
  return (new Promise((resolve, reject) => {
    const options = url.parse(event.Callback.URL);
    options.method = event.Callback.Method;
    options.headers = {};

    let body;
    if (event.Callback['Content-Type'] === 'application/json') {
      body = JSON.stringify(message);
    } else if (event.Callback['Content-Type'] === 'application/x-www-form-urlencoded') {
      body = querystring.encode(message);
    } else {
      reject(new Error('Unknown HTTP Content-Type'));
    }

    if (event.Callback.Method === 'GET') {
      // TODO This will clobber an existing query string
      options.search = `${event.Callback.Name}=${querystring.encode(message)}`;
    }

    options.headers['Content-Type'] = event.Callback['Content-Type'];
    options.headers['Content-Length'] = Buffer.byteLength(body);

    const h = options.protocol === 'https:' ? https : http;
    const req = h.request(options, (res) => {
      res.setEncoding('utf8');

      let resData = '';
      res.on('data', (chunk) => resData += chunk );

      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve();
        } else {
          const error = new Error(`Error ${res.statusCode}: ${resData}`);
          reject(error);
        }
      });
    });

    req.on('error', error => reject(error));

    req.write(body);
    req.end();
  }));
}

// Ex. input: { "Callback": { "Mode": "SNS", "Topic": "arn:aws…" }, "JobResult": { "Job": { … }, "Result": { … } } }
// Ex. error: { "Callback": { "Mode": "SNS", "Topic": "arn:aws…" }, "JobResult": { "Job": { … }, "Error": { … } } }
// Ex. msg:   { "JobResult": { "Job": { … }, "Result": { … } } }
// Ex. msg:   { "JobResult": { "Job": { … }, "Error": { … } } }
exports.handler = async (event) => {
  const msg = {};
  if (event.JobResult) { Object.assign(msg, { JobResult: event.JobResult }); }
  if (event.TaskResult) { Object.assign(msg, { TaskResult: event.TaskResult }); }

  if (event.Callback.Mode === 'SNS') {
    const TopicArn = event.Callback.Topic;
    const Message = JSON.stringify(msg);

    await sns.publish({ Message, TopicArn }).promise();
  } else if (event.Callback.Mode === 'SQS') {
    const QueueUrl = event.Callback.Queue;
    const MessageBody = JSON.stringify(msg);

    await sqs.sendMessage({ QueueUrl, MessageBody }).promise();
  }  else if (event.Callback.Mode === 'HTTP') {
    await httpRequest(event, msg);
  }
};
