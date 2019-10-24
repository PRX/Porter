const url = require('url');
const querystring = require('querystring');
const AWSXRay = require('aws-xray-sdk');

const AWS = AWSXRay.captureAWS(require('aws-sdk'));
const http = AWSXRay.captureHTTPs(require('http'));
const https = AWSXRay.captureHTTPs(require('https'));

const sns = new AWS.SNS({ apiVersion: '2010-03-31' });
const sqs = new AWS.SQS({ apiVersion: '2012-11-05' });

function httpRequest(event, message, redirectCount) {
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

      res.on('end', async () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve();
        } else if (res.statusCode === 301 || res.statusCode === 302) {
          try {
            if (redirectCount > +process.env.MAX_HTTP_REDIRECTS) {
              reject(new Error('Too many redirects'));
            }

            console.log(JSON.stringify({
              msg: `Following HTTP redirect`,
              location: res.headers.location,
              count: redirectCount
            }));

            const count = redirectCount ? (redirectCount + 1) : 1;
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

    req.on('error', error => reject(error));

    req.write(body);
    req.end();
  }));
}

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const now = new Date;
  const msg = { Time: now.toISOString(), Timestamp: (now / 1000) };

  if (event.Message) { Object.assign(msg, event.Message); }

  console.log(JSON.stringify({ msg: 'Callback message body', body: msg }));

  if (event.Callback.Type === 'AWS/SNS') {
    const TopicArn = event.Callback.Topic;
    const Message = JSON.stringify(msg);

    await sns.publish({ Message, TopicArn }).promise();
  } else if (event.Callback.Type === 'AWS/SQS') {
    const QueueUrl = event.Callback.Queue;
    const MessageBody = JSON.stringify(msg);

    await sqs.sendMessage({ QueueUrl, MessageBody }).promise();
  }  else if (event.Callback.Type === 'HTTP') {
    await httpRequest(event, msg);
  }
};
