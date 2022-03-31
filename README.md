# Porter

Porter is a general-purpose file processing system. It is designed to work asynchronously – jobs are sent to Porter from other applications, and the results can be returned to the applications via callbacks. It supports a variety of tasks that can be run on the file included in each job. Some are generic tasks (such as copying a file to a new location), and some are specific to certain file types (such as resizing an image, or transcoding an audio file).

Porter is built on top of [AWS Step Functions](https://aws.amazon.com/step-functions/), as well a number of other AWS services. Each job that is sent to Porter for processing corresponds to a single state machine [execution](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-state-machine-executions.html) of the Step Function. Each Porter job represents one (and only one) input file, which is considered the job's _source file_. Every task that the job definition includes is run against that original source file in parallel.

The system is designed to be highly scalable, both in terms of the number of jobs that can be processed, as well as the number of tasks an individual job can include. Many of the states that the Step Function orchestrates are built on [AWS Lambda](https://aws.amazon.com/lambda/) and [AWS Fargate](https://aws.amazon.com/fargate/), which are serverless compute platforms and support that scalability. As such, there are no prioritization options or explicit queueing controls available. It can be assumed that jobs begin to execute as soon as they are received by Porter.

Porter utilizes the robust [error handling](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-error-handling.html) and retry logic that Step Functions offer to ensure that tasks are resilient to transient service issues. In cases where a job execution is not able to complete all its tasks, Porter sends callbacks to indicate the failure, and the application must decide how to attempt to retry the work.

Job executions within Porter are not intended to be inspected directly or in real time by other applications. An application that's submitting jobs should be designed to track the state of its jobs based on the callback messages that it has or has not received. Callback messages are sent at various points during a job execution, which is explained in more detail [below](#callback-messages).

Many input and output methods are supported to allow flexibility with other applications. For example, [source files](#job-source) can come from HTTP or S3 endpoints, and callback messages can be sent via HTTP, [SNS](https://aws.amazon.com/sns/), and [SQS](https://aws.amazon.com/sqs/). The list of supported source and destination methods will grow over time; see below for a more complete list of methods that each aspect of the job execution support.

### Table of Contents

-   [Introduction](#porter)
-   [Execution Model](#execution-model)
-   [Messaging I/O](#messaging-io)
    -   [Starting a Job](#starting-a-job)
    -   [Input Message Format](#input-message-format)
    -   [Callback Messages](#callback-messages)
-   [Telemetry](#telemetry)
-   [Tasks](#tasks)
    -   [Inspect](#inspect)
    -   [Copy](#copy)
    -   [Image Transform](#image-transform)
    -   [Transcode](#transcode)
    -   [Transcribe](#transcribe)
    -   [WAV Wrap](#wav-wrap)
    -   [Detect Silence](#detect-silence)
    -   [Detect Tone](#detect-tone)
-   [Serialized Jobs](#serialized-jobs)
-   [S3 Read Permissions](#s3-read-permissions)
-   [S3 Destination Permissions](#s3-destination-permissions)

## Execution Model

A Porter job represents a set of work (tasks) to be done for a source file. Each job has only a single source file, and that file is immutable in the context of the job execution. If a task does work to copy, transform, or otherwise manipulate the source file, the result of that operation will be a new file, leaving the source file unchanged. Individual tasks define the locations for those resulting files to be persisted.

Job tasks are isolated and independent from each other. They are run in parallel, and the output of one task **cannot** be used as the input for another task. The order in which tasks are started is not guaranteed. A job will run until all its tasks have either succeeded or failed. If a job includes multiple tasks and one task fails, that will not cause the rest of the execution to halt or fail.

In some cases, a job may encounter an issue before it can start any of its tasks, such as if the source file is unavailable.

Except in cases where Porter is unable to send callbacks, every Porter job will return a result, regardless of how successful it was. The result may indicate that the job was entirely successful, partially successful, or entirely unsuccessful. Applications consuming callbacks from Porter should be designed to handle that spectrum of results.

Individual task results, on the other hand, are binary: a task is either successful and returns the result of the task operation, or the task failed and it reports the failure.

## Messaging I/O

Porter receives messages to start jobs, and sends messages while jobs are running and when jobs are done.

### Starting a Job

When you want to start a job, a message must be sent to Porter. There are a number of methods supported.

**Step Functions API**

Directly through the [AWS Step Functions API](https://docs.aws.amazon.com/step-functions/latest/apireference/Welcome.html)

```python
import boto3
stepfunctions = boto3.client('stepfunctions')
stepfunctions.start_execution(
    stateMachineArn='arn:aws:states:us-east-2:1234512345:stateMachine:StateMachine-u827adsf8',
    input='{"Job": { … }}'
)
```

**SNS**

By way of an SNS topic that is created along side the state machine when the CloudFormation stack is launched:

```python
import boto3
sns = boto3.client('sns')
sns.publish(
    TopicArn='arn:aws:sns:us-east-2:1234512345:SnsTopic-ABCDE1234',
    Message='{"Job": { … }}'
)
```

**EventBridge**

Events can be sent to a bus in [Amazon EventBridge](https://aws.amazon.com/eventbridge/). When the stack is launched a rule is added to both the default event bus as well as a custom event bus whose name can be found in the stack's outputs. Events can be sent to either bus. You can disable the default bus rule using the stack's parameters. Only an event's `detail` is sent to the state machine. If you have multiple Porter instances in a single AWS account, all instances will receive all jobs sent to the default bus.

The event detail type must be `Porter Job Execution Submission`.

```python
import boto3
events = boto3.client('events')
events.put_events(
    Entries=[
        {
            'Source': 'com.example.app',
            'DetailType': 'Porter Job Execution Submission',
            'Detail': '{"Job": { … }}'
        }
    ]
)
```

**Optional SQS Queue**

If the `EnableSqsJobExecution` stack parameter is set to `True`, an [Amazon SQS](https://aws.amazon.com/sqs/) queue will also be created when the Porter stack is launched, and messages sent to the queue will be [processed](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html) and forwarded to the state machine automatically. Be aware that enabling this option relies on regularly polling the queue, and there are costs associated with that even when no messages are being sent.

```python
import boto3
sqs = boto3.client('sqs')
sqs.send_message(
    QueueUrl='https://sqs.us-east-2.amazonaws.com/1234512345/Porter1234-JobExecutionSqsQueue',
    MessageBody='{"Job": { … }}'
)
```

### Input Message Format

Input messages are represented as JSON data. The root JSON object must include a `Job` key. All information needed to define the job will be enclosed in the `Job` object.

```json
{
    "Job": {
        "Id": "1234567890asdfghjkl",
        "Source": {
            "Mode": "AWS/S3",
            "BucketName": "myBucket",
            "ObjectKey": "myObject.jpg"
        },
        "Tasks": [
            {
                "Type": "Inspect"
            }
        ],
        "Callbacks": [
            {
                "Type": "AWS/SNS",
                "Topic": "arn:aws:sns:us-east-1:123456789012:my-callback-topic"
            }
        ]
    }
}
```

#### Job ID

The job ID is a user-defined value, and does not need to be unique. It is distinct from any execution IDs created or assigned when the job runs. The `Job.Id` is sent in all callback messages. **It is required.** The job ID is commonly used to match a job with a record or entity in an application, such as by setting it to the record's primary key.

#### Job Source

A job's source is the file that all tasks in the job will be performed on. One immutable copy of the source file is made for every Porter job execution, and each tasks uses that copy to do its work. `Source.Mode` is required and indicates the protocol used to fetch the source file. When the mode is set to `AWS/S3`, `Source.BucketName` and `Source.ObjectKey` are also required. When the mode is set to `HTTP`, `Source.URL` is also required, which can use either an `http://` or `https://` protocol. When the mode is set to `Data/URI`, `Source.URI` is also required, and must be in the format: `data:<media type>;base64,<data>`.

##### S3 Read Permissions

The IAM role used to access S3 objects defined as job source files has `s3:GetObject*` to all (`*`) resources. This should provide read access to any files in the same AWS account that Porter is deployed into (unless bucket policies are in place to prevent it). For source files in buckets in a different account, a bucket policy must exist that grants the role access to the source file object.

The role's ARN is published as an output on the CloudFormation stack. The following example bucket policy gives the role read access to all objects in a bucket:

```json
{
    "Statement": [
        {
            "Sid": "Grant object read access to Porter",
            "Action": "s3:GetObject",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::123456789012:role/porter-prod-IngestLambdaIamRole-TKTKTKTKTK"
            },
            "Resource": "arn:aws:s3:::myBucket/*"
        }
    ],
    "Version": "2012-10-17"
}
```

See also: [S3 Destination Permissions](#s3-destination-permissions)

#### Job Tasks

`Tasks` is an array of individual operations the state machine should perform. Every member of the array should be an object with a `Type` property. Valid types are: [`Inspect`](#inspect), [`Copy`](#copy), [`Image`](#image-transform), [`Transcode`](#transcode), [`Transcribe`](#transcribe), [`WavWrap`](#wav-wrap). Tasks with invalid types are ignored. The other properties of any given task are determined by their type (see below).

#### Job Callbacks

`Callbacks` is an array of endpoints to which callback messages about the job execution will be sent. Each endpoint object has a `Type` (supported types are `AWS/SNS`, `AWS/SQS`, `AWS/S3`, `AWS/EventBridge`, and `HTTP`). Different modes will have additional required properties.

`HTTP` callbacks require a 'URL' property. When using methods like `POST` or `PUT`, they also require a `Content-Type`. Possible values are `application/json` and `application/x-www-form-urlencoded`. When using HTTP `GET`, the entire callback message is sent as a URL query parameter value. The `QueryParameterName` property is required and determines the name of the query parameter used to send the message. Other query parameters on the callback URL are preserved, but the chosen parameter is replaced if it exists. There is no guarantee that callback messages will fit within the normal limits of a URL's length, therefore `GET` callbacks are not recommended. The endpoint should respond with an HTTP `200` to acknowledge receipt of the callback.

`AWS/SNS` callbacks must include a `Topic` ARN, and `AWS/SQS` callbacks must include a `Queue` in the form of a URL. An `AWS/EventBridge` callback can optionally include an `EventBusName`; if excluded the callback will be sent to the default event bus.

`AWS/S3` callbacks require both the `BucketName` and `ObjectPrefix` properties. Each callback result will be written to S3 individually (i.e., one file for each task result, and one file for the job result). The object name will be one of the following:

-   `[ObjectPrefix][Execution ID]/job_received.json`
-   `[ObjectPrefix][Execution ID]/job_result.json`
-   `[ObjectPrefix][Execution ID]/task_result.[index].json`

The `ObjectPrefix` property is required, but it can be an empty string, which will result in no prefix being added. An example of a prefix would be `porter_results/`, though the trailing slash is also not required. The `index` value in a task result's file name matches the index of that task from the original job (zero-based numbering). The `Execution ID` is only the final segment of the execution ID ARN.

### Callback Messages

Callback messages are dispatched at various points throughout the execution of a job. Whenever callback messages are sent, messages are always sent to all callbacks defined in the job. Callbacks are optional, and any value in `Job.Callbacks` other than an array will be ignored. Empty arrays are okay.

Each callback includes `Time` and `Timestamp` values. These represent approximately the time at which that specific callback was sent. If multiple callbacks are provided for a job, they may (and likely will) have slightly different timestamps, even though they are sent in parallel. These time values are in addition to the ones included with individual task results, and should always be later (greater than) the task-specific values.

#### Job Received Callbacks

Callbacks are sent when a job has been received (after the input has been normalized). These callbacks will contain a `JobReceived` key.

```json
{
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp": 1356093296.123,
    "JobReceived": {
        "Job": {
            "Id": "1234567890asdfghjkl"
        },
        "Execution": {
            "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
        },
        "State": "RECEIVED"
    }
}
```

#### Task Callbacks

Callbacks are sent as individual tasks succeed or fail. For example, if a job includes three `Copy` destinations, a callback will be sent after each copy task completes. (Tasks are processed in parallel, so callbacks may arrive in any order). Task callbacks can be identified by the `TaskResult` key. The original task definition is also included in the callback under the `Task` key.

The JSON message for a successful `Copy` task callback looks like this:

```json
{
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp": 1356093296.123,
    "Task": {
        "Type": "Copy",
        "Mode": "AWS/S3",
        "BucketName": "myBucket",
        "ObjectKey": "myObject.ext"
    },
    "TaskResult": {
        "Job": {
            "Id": "1234567890asdfghjkl"
        },
        "Execution": {
            "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
        },
        "Result": {
            "Task": "Copy",
            "Time": "2012-12-21T12:34:50Z",
            "Timestamp": 1356093290.123,
            (Additional task-specific results)
        }
    }
}
```

The JSON message for a failed task will have an `TaskResult.Error` key rather than a `TaskResult.Result` key, like this:

```json
{
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp": 1356093296.123,
    "Task": {
        "Type": "Copy",
        "Mode": "AWS/S3",
        "BucketName": "myBucket",
        "ObjectKey": "myObject.ext"
    },
    "TaskResult": {
        "Job": {
            "Id": "1234567890asdfghjkl"
        },
        "Execution": {
            "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
        },
        "Error": {
            "Error": "…",
            "Cause": "…"
        }
    }
}
```

#### Job Result Callback

Callbacks are also sent when the job completes. Job callbacks can be identified by the `JobResult` key. There are three properties that can be inspected to determine the result of the job. All three of these are present for all `JobResult` callbacks; you must check the values, not simply whether the keys exist.

##### Job State

Each job result will include a `JobResult.State`, which will be one of the following values:

-   `"DONE"`
-   `"NORMALIZE_INPUT_ERROR"`
-   `"SOURCE_FILE_INGEST_ERROR"`
-   `"SOURCE_FILE_TYPE_DETECTION_ERROR"`
-   `"ITERATOR_ERROR"`

`DONE` indicates that the job was able to attempt all the tasks. This is **not** an indication that all the tasks were successful. The other states will appear if an execution step prior to the tasks running fails. `SOURCE_FILE_INGEST_ERROR`, for example, indicates that the artifact copy of the source file couldn't be created.

The list of possible states may change over time.

##### Task Results

`JobResult.TaskResults` is an array of task results for those tasks that completed successfully. If there were no successful tasks in a job, the array will be empty. The data included in a task result is described below for each task type.

##### Failed Task

`JobResult.FailedTasks` is an array of tasks (from the job input) that did not complete successfully. If there were no unsuccessful tasks in a job, the array will be empty. Please note that error information related to individual failed tasks is **not** included in job result callbacks. In order to capture task error details, they must be captured from the [task callbacks](#task-callbacks).

##### Job Result Examples

Here's an example of a job that had no errors:

```json
{
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp": 1356093296.123,
    "JobResult": {
        "Job": {
            "Id": "1234567890asdfghjkl"
        },
        "Execution": {
            "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
        },
        "State": "DONE",
        "FailedTasks": [],
        "TaskResults": [
            {
                "Task": "Copy"
                (Additional task-specific results)
            }, {
                "Task": "Copy"
                (Additional task-specific results)
            }, {
                "Task": "Transcode"
                (Additional task-specific results)
            }, {
                "Task": "Inspect"
                (Additional task-specific results)
            }
        ]
    }
}
```

Here's an example of a job that included one successful task and one failed task. Please note that `TaskResults` have a `Task` key, and `FailedTasks` have a `Type` key.

```json
{
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp": 1356093296.123,
    "JobResult": {
        "Job": {
            "Id": "1234567890asdfghjkl"
        },
        "Execution": {
            "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
        },
        "State": "DONE",
        "FailedTasks": [
            {
                "Type": "Copy"
                (Additional task-specific results)
            }
        ],
        "TaskResults": [
            {
                "Task": "Copy"
                (Additional task-specific results)
            }
        ]
    }
}
```

This is an example of a job that included two tasks, but whose source file could not be ingested:

```json
{
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp": 1356093296.123,
    "JobResult": {
        "Job": {
            "Id": "1234567890asdfghjkl"
        },
        "Execution": {
            "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
        },
        "State": "SOURCE_FILE_INGEST_ERROR",
        "FailedTasks": [],
        "TaskResults": []
    }
}
```

**Example:** If you have a job with three copy tasks, and two callbacks, you would expect to get a total of six `TaskResult` and two `JobResult` messages, across all of the endpoints.

### Job Success and Failure

A job is considered successful when it completes to a `DONE` state and zero tasks failed. All other jobs are considered to have failed.

## Serialized Jobs

A job can include any number of additional jobs that will be started after all tasks have succeeded. This allows you to easily perform tasks on files that resulted from an initial job.

As an example, you may have a job with an MP2 source file and a transcode task that produces an MP3 version of that file. You could include a serialized job which then performs a transcribe task on that resulting MP3 file.

Serialized jobs are **not** called recursively as part of the initial job execution. They are simply additional jobs that have their own state machine execution, and are entirely self-contained in their definition and execution. They have their own job ID, source, callbacks, tasks, etc, even additional serialized jobs. There is no inheritance from or referencing to the initial job or its outputs. The only benefit to using serialized jobs is that Porter provides the convenience of starting the job executions for you.

If a job includes any serialized jobs, they are executed after all job result callbacks have been sent. Each serialized job is sent to the SNS topic mentioned previously. As such, the serialized executions are entirely decoupled from the initial execution. It will do nothing to ensure, and have no visibility into, the progress or success of the serialized jobs. Aside from this, including serialized jobs in a job has no impact on the job itself; callbacks will not indicate in any way that a job included serialized jobs, and individual tasks will not be aware of any of the future work that is expected to occur.

When constructing jobs that include serialized jobs, it's the constructor's responsibility to build sequential jobs with meaningful values. If the serialized job needs to do work on the result of the initial job's task, the two job definitions must be explicitly constructed in such a way that the resulting file of the task and the source file of the serialized job align.

In some cases it could be acceptable or beneficial for a job and some of its serialized jobs to share a job ID, but this would depend enitrely on how the app that sent the job works, and how it handles the callbacks.

When a job is started via this method, it will include an additional parameter in the definition called `ExecutionTrace`. This is array containing the execution ID of the job that started it, as well as the ID of the job that started that job, etc (if applicable). The last element in the array is the execution ID of the job that started the job being executed.

All jobs included directly as members of `SerializedJobs` are started simultaneously.

```json
{
    "Job": {
        "Id": "1234567890asdfghjkl",
        "Source": {
            "Mode": "AWS/S3",
            "BucketName": "farski-sandbox-prx",
            "ObjectKey": "130224.mp2"
        },
        "SerializedJobs": [
            {
                "Job": {
                    "Id": "1234567890asdfghjkl",
                    "Source": {
                        "Mode": "AWS/S3",
                        "BucketName": "farski-sandbox-prx",
                        "ObjectKey": "130224.mp2"
                    }
                }
            },
            {
                "Job": {
                    "Id": "1234567890asdfghjkl",
                    "Source": {
                        "Mode": "AWS/S3",
                        "BucketName": "farski-sandbox-prx",
                        "ObjectKey": "130224.mp2"
                    }
                }
            }
        ]
    }
}
```

## Telemetry

Porter publishes the following CloudWatch Metrics related to job executions. Remember that job metrics and Step Function execution metrics are tracking different things. A Step Function execution, for example, can succeed while the Porter job it's running fails, and the metrics will reflect that.

The following metrics are available with the `StateMachineArn` dimension:

- `JobsStarted`: The number of jobs that were able to begin execution. If a job's input message is too malformed it may not be able to execute and will not be counted.

- `TasksRequested`: The number of tasks included in jobs that were able to begin execution.

- `JobsCompleted`: The number of jobs that completed, regardless of how successful the job was.

- `TasksSucceeded`: The total number of tasks that completed successfully.

- `TasksFailed`: The total number of tasks that failed.

- `JobsSucceeded`: The number of jobs that completed successfully, with no failed tasks.

- `JobsFailed`: The number of jobs that completed but were unable to successfully complete all tasks.

The following metrics are available with the `StateMachineArn` and `JobResultState` dimensions:

- `JobsCompleted`: The number of jobs that completed, regardless of how successful the job was, with a specific job result state (such as `DONE`, `SOURCE_FILE_INGEST_ERROR`, etc)

## Tasks

### Copy

`Copy` tasks create copies of the job's source file. Each copy task creates one copy, but a job can include any number of copy tasks. Currently supported destination modes are `AWS/S3` and `FTP`. Copy tasks **do not** check if an object already exists in the given location.

The `Time` and `Timestamp` in the output represent approximately when the file finished being copied.

#### AWS/S3

S3 copy operations are done by the [copyObject()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property) method in the AWS Node SDK. Copying files larger than 5 GB is not supported by the AWS API.

The `BucketName` and `ObjectKey` properties are required.

The default behavior is to preserve all metadata except for the ACL, which is set to private. To set new metadata on the copy, use the optional `Parameters` property on the destination. `MetadataDirective` must be set to `REPLACE` for the operation to honor the new metadate. The contents of `Parameters` are passed directly to the [copyObject()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property) method.

If you set the optional `ContentType` property to `REPLACE`, the content type of the newly created copy will be set to a [heuristically-determined](https://www.npmjs.com/package/file-type) value. This would replace the content type copied from the source object, if such a value existed. If the content type could not be determined heuristically, this property has no effect. Setting `ContentType` to `REPLACE` will also set `MetadataDirective` to `REPLACE`. If a `ContentType` value is explicitly defined in `Parameters` that value will take precedence.

Input:

```json
{
    "Type": "Copy",
    "Mode": "AWS/S3",
    "BucketName": "myBucket",
    "ObjectKey": "myObject.ext"
}
```

Input with additional parameters:

```json
{
    "Type": "Copy",
    "Mode": "AWS/S3",
    "BucketName": "myBucket",
    "ObjectKey": "myObject.ext",
    "ContentType": "REPLACE",
    "Parameters": {
        "ACL": "public-read",
        "ContentDisposition": "attachment",
        "Metadata": {
            "MyMetadataKey": "MyMetadataValue"
        },
        "MetadataDirective": "REPLACE"
    }
}
```

Output:

```json
{
    "Task": "Copy",
    "BucketName": "myBucket",
    "ObjectKey": "myObject.ext",
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp": 1356093296.123
}
```

#### FTP

FTP operations are handled in the FTP container, using Ruby's `Net::FTP` module.

The `Mode` property can be one of `FTP/Passive`, `FTP/Active`, or `FTP/Auto`. When `FTP/Auto` is used, both passive and active modes will be used if necessary, in order to try to complete the transfer.

The `URL` property is required. It should be formatted as follows:

```
ftp://user:password@host:port/path/file.extension
```

If port is not specified, it will default to the standard FTP command port, `21`.

There are additional parameters to specify how the file is transferred:

`MD5`: The default is `false`, to indicate the md5 file should not be written.
If set to `true` Porter will write an md5 file, containing the md5 hash of the input file (e.g. `<input file>.md5`).
This is useful both as a semaphore file, as it is written after the primary file is written successfully,
and useful to validate the file was transferred without error by checking the md5 signature.

`Timeout`: The default is `1800` (30 minutes). The number of seconds that each FTP transfer should be given to complete. Note that the FTP copy task will internally make multiple attempts to transfer a file, and this is the timeout for each attempt, not for the task itself.

The task output will include a `Mode` value, which may not match the `Mode` value from the input. The output will indicate the FTP transfer mode that was actually used to sucessfully transfer the file. When `FTP/Auto` is selected for a task, this allows you to inspect which mode was used internally to complete the transfer.

Input:

```json
{
    "Type": "Copy",
    "Mode": "FTP/Auto",
    "URL": "ftp://usr:pwd@ftp.example.com:21/path/to/file.ext",
    "MD5": false,
    "Timeout": 500
}
```

Output:

```json
{
    "Type": "Copy",
    "URL": "ftp://usr:pwd@ftp.example.com:21/path/to/file.ext",
    "Mode": "FTP/Passive",
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp": 1356093296.123
}
```

### Image Transform

`Image` tasks perform image manipulations on the source file. These are intended for static image files (eg, jpeg, png, webp, gif, svg). Currently the only supported destination mode is `AWS/S3`. A job can include any number of image tasks; each will perform the operation against the original state of the source file.

Resize supports the following parameters: `Fit`, `Height`, `Position`, and `Width`. These follow the same rules as [sharp's](http://sharp.pixelplumbing.com/en/stable/api-resize/#parameters) parameters. The `Resize` property is optional; if excluded the task will not attempt to resize the image. All child properties of the `Resize` object are optional.

`Format` indicates the desired output format. Supported formats are: `jpeg`, `png`, `webp`, and `tiff`. The `Format` property is optional; if excluded the output format will be inferred from the file extension of the destination object.

By default all image metadata (EXIF, XMP, IPTC, etc) is stripped away during processing. If you set `Metadata` to `PRESERVE`, metadata from the input file will be included in the output file. This property is optional, and other values have no effect.

#### AWS/S3

S3 image destinations are handled by the [upload()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#upload-property) method in the AWS Node SDK.

The `BucketName` and `ObjectKey` properties are required.

To set metadata on the new image object, use the optional `Parameters` property on the destination. The contents of `Parameters` are passed directly to the [upload()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#upload-property) method.

If you set the optional `ContentType` property to `REPLACE`, the content type of the newly created image will be set to a [heuristically-determined](https://www.npmjs.com/package/file-type) value from the job's source file. If the content type could not be determined heuristically, this property has no effect. If a `ContentType` value is explicitly defined in `Parameters` that value will take precedence.

Input:

```json
{
    "Type": "Image",
    "Format": "png",
    "Metadata": "PRESERVE",
    "Resize": {
        "Fit": "cover",
        "Height": 300,
        "Position": "centre",
        "Width": 300
    },
    "Destination": {
        "Mode": "AWS/S3",
        "BucketName": "myBucket",
        "ObjectKey": "myObject.png",
        "ContentType": "REPLACE",
        "Parameters": {
            "ContentDisposition": "attachment",
            "Metadata": {
                "MyMetadataKey": "MyMetadataValue"
            }
        }
    }
}
```

Output:

```json
{
    "Task": "Image",
    "BucketName": "myBucket",
    "ObjectKey": "myObject.ext",
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp": 1356093296.123
}
```

### Transcode

`Transcode` tasks encode and otherwise manipulate the source file. These are intended for audio and video source files, though could operate on any file formats supported by FFmpeg. A job can include any number of transcode tasks; each will perform the operation against the original state of the source file. Currently the only supported destination mode is `AWS/S3`.

A `Format` is required, and is used to explicitly set the output format of the encoding operation; it is not implictly determined by the file extension. The available formats are indicted [in this list](https://johnvansickle.com/ffmpeg/release-readme.txt) with an `E`.

The `FFmpeg` property is optional. When included, each of `GlobalOptions`, `InputFileOptions`, and `OutputFileOptions` properties are also optional. The task constructs a call to FFmpeg that looks like `ffmpeg [global opts] [input file opts] -i input [output file opts] -f [format] output`.

For `AWS/S3` destinations, the contents of `Parameters` are passed directly to the [upload_file()](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3.html#S3.Client.upload_file) method as `ExtraArgs`. S3 will default the `content-type` to `binary/octet-stream`, so you may generally want to define that parameter.

The output for the task includes the destination bucket, object key, transcoded file size in bytes, and duration in milliseconds (see example below).

Input:

```json
{
    "Type": "Transcode",
    "Format": "flac",
    "FFmpeg": {
        "GlobalOptions": "-loglevel info",
        "InputFileOptions": "-t 500",
        "OutputFileOptions": "-metadata title=some_title"
    },
    "Destination": {
        "Mode": "AWS/S3",
        "BucketName": "myBucket",
        "ObjectKey": "myObject.flac",
        "Parameters": {
            "ContentType": "audio/flac"
        }
    }
}
```

Output:

```json
{
    "Task": "Transcode",
    "BucketName": "myBucket",
    "ObjectKey": "myObject.flac",
    "Duration": 23222.857,
    "Size": 186035
}
```

### Inspect

`Inspect` tasks performs an analysis of the job's source file, and returns a set of metadata. The method of analysis and resulting data are determined by the type of the source file.

If the optional `EBUR128` property is set to `true`, several loudness measurements will be taken based on the [EBU R 128](https://en.wikipedia.org/wiki/EBU_R_128) standard. Given that this takes significantly longer than the rest of the inspection task, when submitting jobs that include loudness measurement, you may want to include two `Inspect` tasks, so that one can return results more quickly.

Input:

```json
{
    "Type": "Inspect",
    "EBUR128": true
}
```

Output:

```json
{
    "Task": "Inspect",
    "Inspection": {
        (The results of the analysis.)
    }
}
```

### Transcribe

`Transcribe` tasks use [Amazon Transcribe](https://aws.amazon.com/transcribe/) speech-to-text functionality to generate transcriptions from audio and video files. The source file must be an mp3, mp4, wav, ogg, amr, webm or flac file for transcriptions to work. The `LanguageCode` property is required. The destination property is required, and the only mode currently supported is `AWS/S3`. The output of this task is a JSON file, and it's recommended that the destination file uses a `.json` extension, though it's not required.

By default, the `MediaFormat` is set based on the [heuristically-determined](https://www.npmjs.com/package/file-type) file type extension of the source file, which may not match the source file's actual extension. For example, an Ogg source file with a `.oga` extension may have a default `MediaFormat` of `ogg`. Some common detected `MediaFormat` values are automatically remapped to a valid value, such as `m4a` to `mp4`. If necessary, you can override this to a different valid format by setting the optional `MediaFormat` property of the `Task`.

`SubtitleFormats` is optional. If included, it must be an array that includes one or more of these values: `vtt`, `srt`. When any `SubtitleFormats` are included in the task, additional files will be created, alongside the default JSON transcription file. If the JSON file is named `myTranscript.json`, the subtitle files would be named `myTranscript.json/subtitles.vtt` or `myTranscript.json/subtitles.srt` (i.e., `[JSON file name]/subtitles.[subtitle format]`).

Additional transcribe task settings are not supported at this time.

Input:

```json
{
    "Type": "Transcribe",
    "LanguageCode": "en-US",
    "MediaFormat": "mp3",
    "SubtitleFormats": ["vtt", "srt"],
    "Destination": {
        "Mode": "AWS/S3",
        "BucketName": "myBucket",
        "ObjectKey": "myTranscript.json"
    }
}
```

Output:

```json
{
    "Task": "Transcribe",
    "Mode": "AWS/S3",
    "BucketName": "myBucket",
    "ObjectKey": "myTranscript.json",
    "SubtitleFormats": ["vtt", "srt"]
}
```

### WAV Wrap

`WavWrap` tasks create a [WAV](https://en.wikipedia.org/wiki/WAV) file from an audio artifact, and apply data to specific chunks of the WAV wrapper.

It accepts MPEG audio files, and any of the chunks supported by [prx-wavefile](https://github.com/PRX/prx-wavefile), including all Broadcast Wave Format chunks and `cart` chunks.

`prx-wavefile` will attempt to set the `fmt`, `mext`, `bext`, `fact`, and `data` chunks from the source file, e.g. analyzing the MPEG audio to set the `fmt` sample rate, bit rate, and number of channels.

The `cart` chunk is optional, and won't be set unless it's included in the `Task.Chunks` array, as in the example below.

The Output includes a `WavfileChunks` array with the attributes set on the `prx-wavefile` chunks.

Input:

```json
{
    "Type": "WavWrap",
    "Destination": {
        "Mode": "AWS/S3",
        "BucketName": "myBucket",
        "ObjectKey": "myTranscript.json"
    },
    "Chunks": [
        {
            "ChunkId": "cart",
            "Version": "0101",
            "CutId": "12345",
            "Title": "Title",
            "Artist": "Artist",
            "StartDate": "2020/01/01",
            "StartTime": "00:00:00",
            "EndDate": "2020/01/14",
            "EndTime": "00:00:00",
            "ProducerAppId": "PRX",
            "ProducerAppVersion": "3.0"
        }
    ]
}
```

Output:

```json
{
    "Task": "WavWrap",
    "Mode": "AWS/S3",
    "BucketName": "myBucket",
    "ObjectKey": "myTranscript.json",
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp": 1356093296.123,
    "WavefileChunks": [
        {
            "chunkId": "cart",
            "chunkSize": 2048,
            "version": "0101",
            "title": "Title",
            "artist": "Artist",
            "cutId": "12345",
            "clientId": "",
            "category": "",
            "classification": "",
            "outCue": "",
            "startDate": "2020/01/01",
            "startTime": "00:00:00",
            "endDate": "2020/01/14",
            "endTime": "10:00:00",
            "producerAppId": "PRX",
            "producerAppVersion": "3.0",
            "userDef": "",
            "levelReference": 0,
            "postTimer": [],
            "reserved": "",
            "url": "",
            "tagText": ""
        }
    ]
}
```

#### AWS/S3

S3 destinations are handled by the [upload()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#upload-property) method in the AWS Node SDK.

The `BucketName` and `ObjectKey` properties are required.

To set metadata on the new audio file object, use the optional `Parameters` property on the destination. The contents of `Parameters` are passed directly to the [upload()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#upload-property) method.

### Detect Silence

`DetectSilence` tasks identify periods of silence in audio files. All source audio files are mixed down to a single channel prior to detection.

`Threshold.Duration` and `Threshold.Value` are optional. They determine what sample data will be considered silence. Samples that are above (i.e., louder than) `Threshold.Value` will never be considered silence. Periods of silence shorter than `Threshold.Duration` (in seconds) will not be included in the output. If both properties are excluded, the `Threshold` property can also be excluded.

The default values are `0.2` for `Duration` and `0.001` for `Value`.

Input:

```json
{
    "Type": "DetectSilence",
    "Threshold": {
      "Duration": "1.0",
      "Value": "0.005"
    }
}
```

Output:

```json
{
    "Task": "DetectSilence",
    "Silence": {
      "Ranges": [
        { "Start": 10.105, "End": 19.988 }
      ]
    }
}
```

### Detect Tone

`DetectTone` tasks identify periods of tones in audio files. All source audio files are mixed down to a single channel prior to detection. The `Frequency` property determines which tone is being detected and is required.

`Threshold.Duration` and `Threshold.Value` are optional. They determine what sample data will be considered tone. Only samples that are above (i.e., louder than) `Threshold.Value` will be considered tone. Periods of tone shorter than `Threshold.Duration` (in seconds) will not be included in the output. If both properties are excluded, the `Threshold` property can also be excluded.

The default values are `0.2` for `Duration` and `0.025` for `Value`.

Input:

```json
{
    "Type": "DetectTone",
    "Frequency": 440,
    "Threshold": {
      "Duration": "1.0",
      "Value": "0.005"
    }
}
```

Output:

```json
{
    "Task": "DetectTone",
    "Tone": {
      "Frequency": 440,
      "Ranges": [
        { "Start": 10.105, "End": 19.988, "Minimum": 0, "Maximum": 0.00098160235211 }
      ]
    }
}
```

## S3 Destination Permissions

Several task types produce new files, and [Amazon S3](https://aws.amazon.com/s3/) is a supported destination. When a task includes S3 as a destination, the destination bucket must grant access via its [bucket policy](https://docs.aws.amazon.com/AmazonS3/latest/dev/using-iam-policies.html). Porter creates a IAM role that is always used to perform S3 actions on destination buckets, so the bucket policies must allow the necessary actions for that policy. The role's ARN is published as an output on the CloudFormation stack.

Generally, for buckets in the same AWS account where Porter is deployed, this permission is granted implicitly by default, so the bucket policy is not required.

The following is an example of the bucket policy used for granting Porter access to a bucket called `myBucket`:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Grant bucket-level list access to Porter",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::123456789012:role/porter-prod-S3DestinationWriterRole-TKTKTKTKTK"
            },
            "Action": "s3:ListBucketMultipartUploads",
            "Resource": "arn:aws:s3:::myBucket"
        },
        {
            "Sid": "Grant object-level write access to Porter",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::123456789012:role/porter-prod-S3DestinationWriterRole-TKTKTKTKTK"
            },
            "Action": [
                "s3:PutObject*",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": "arn:aws:s3:::myBucket/*"
        }
    ]
}
```

See also: [S3 Read Permissions](#s3-read-permissions)
