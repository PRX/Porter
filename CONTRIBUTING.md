# Porter

#### Useful Resources

- [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/welcome.html)

### Misc

There are a number of shell scripts in this repo. They assume you have a profile in `~/.aws/config` called `prx-legacy`, which is configured to access the `prx-legacy` AWS account.

The template is intended to deployed using the [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-command-reference.html). You can run `sam deploy` if you already have a `samconfig.toml`, or `sam deploy -g` if you don't. Additionally, there is a VS Code task that supports deploying various environments (staging, producdtion, etc), which expects files called `samconfig.[stag|prod].toml`, and will use the correct one.

Various APIs and SDKs are inconsistent in how they refer to S3 buckets and objects. To be consistent throughout this project, they should be called `BucketName` and `ObjectKey` until they are passed to an API.

For the sake of clarity, when building states always include the `InputPath`, `ResultPath`, and `OutputPath`, even if they are set to the default value.

Timestamps should always be in seconds.

Create Lambda Layers for external dependencies, rather than including them in the deployment package.

The job input format should generally avoid using input formats specific to particular tools or libraries. The underlying tools used to perform any given task could change over time.

When a state fails, in general the desired outcome is that the error gets caught by the state machine and a callback is sent with notifying the user of the issue. By catching errors, it is no longer possible to detect or count task errors by looking for state machine execution failures. Instead the resources themselves (Lambdas functions, etc) must be monitored.

Fargate tasks (like Transcode) run in a VPC that does not have internet access. Access to AWS APIs is provided by [VPC endpoints](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-endpoints.html). If you have a Fargate task running in the VPC that needs access to a new AWS API, you'll have to add a new endpoint for it.

### S3 Access Permissions

There are two common reasons that a given state's resource (like a Lambda function or Fargate task) would need access to S3: reading from the artifact bucket, and writing new files to the destination buckets.

In the case of reading from the artifact bucket, there is a managed IAM policy that provides the necessary permissions: `ArtifactBucketReadOnlyAccessPolicy`. You can include this in the list of `ManagedPolicyArns` for IAM roles you create for your stack resources.

Permissions for writing files to destination buckets is handled **by the buckets themselves**, through bucket policies (see the README for more information). The bucket policies will grant access to a specific IAM role that Porter publishes. Thus, any S3 operations against destination buckets must always use credentials for that IAM role. Any state resources (Lambda functions, Fargate tasks, etc), must request temporary credentials for that role, and use those credentials to sign any S3 requests to the destination buckets.

To recap, when adding new tasks or states to Porter's CloudFormation template:

1. Create an execution role for a given Lambda function/Fargate Task/etc. This would have policies needed for the task to execute *excluding* writing files to S3 destination buckets (e.g., publishing SNS messages, getting files from S3, writing files to the S3 artifact bucket, etc)
2. Ensure that that execution role is included as a principal in the `S3DestinationWriterRole` trust policy. This allows the execution role to assume the `S3DestinationWriterRole` role.
3. Design the task so that it assumes the `S3DestinationWriterRole` role, and uses the temporary credentials generated to sign any S3 requests to the destination buckets. (Note: A task may deal with other S3 buckets, so you may end up with multiple S3 service objects, which have different permissions.)

There's also `ArtifactBucketWriteAccessPolicy`, which provides write access to the artifact bucket. The artifact bucket is primarily used to store the source file for a task execution, but if you have a task that needs to persist metadata somewhere for the duration of an execution (such as to pass a value between decoupled services, or to store a large file that requires further processing), the artifact bucket can be used for those needs as well. Take care to make sure anything you're writing to the artifact bucket can't interfer with another execution's data. Common practice is to prefix any objects you create with the state machine execution ID. Objects in the artifact bucket expire very quickly, so it should never be used as the final destination for any critical data.

## Internal Messaging

How data is passed between the various states of the Step Function is key to building a reliable state machine, and understanding the flow of data in invaluable when developing this project. The following is a detailed look at the lifecycle of inputs and outputs of the state machine internals. The code examples are meant to demonstrate important structural aspects, and are not necessarily 100% accurate.

[Input and output processsing](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-input-output-filtering.html) is used extensively to ensure that the data being passed between states is clean, and the data being passed to task resources (Lambda functions, etc) is appropriately scoped. A good understanding of how the state I/O and task resource I/O interact is crucial.

In some cases, states will use a result path of `$.Void` if their return values are unwanted. These are largely treated in the documentation below as though they don't exist.

### Execution Input

This is the input provided by the end user as raw JSON. The format is covered in detail in the [README](https://github.com/PRX/Porter/blob/master/README.md). `Job.Id` and `Job.Source` are consider required.

```
{ "Job": { "Id": "1234567890asdfghjkl", "Source": { "Mode": "AWS/S3" } } }
```

### Input Normalization

Some states in the machine assume that certain properties exist in the input. In order for those properties to be optional for the user providing the input, the execution input it normalized as the first step.

This state does no input or output processing at the machine level. It takes in the complete execution input, passes the entire input to the Lambda function, and uses the result of the Lambda function as the entire output result.

- `InputPath`: `$`, `{ Job: { … } }`
- `Parameters`: n/a, `{ Job: { … } }`
- `ResultPath`: `$`, `{ Job: { … } }`
- `OutputPath`: `$`, `{ Job: { … } }`

### Job Received Callbacks

This pattern is shared by all three callback-sending states in the machine. Callbacks can be sent to an arbitrary number of endpoints, determined by the size of the `Job.Callbacks` array in the input, which is set as the `ItemsPath` of the `Map` state.

Each iteration receives input based on the `Parameters` of the `Map` state. The input is an object with two properties: `Callback` and `Message`. `Callback` is the current value of the iterator (i.e., an element of the `Job.Callbacks` array). `Message` is the value that will be sent as the callback payload.

Within the iterator, no additional I/O processing is done on the state that sends the callback, so the data that's is available in the Lambda function is the `Callback`/`Message` object. The result of the Lambda function is the output of the inner state.

The output of the map state itself is an array whose elements are the results of each iteration. Because the callback Lambda function has no return value, the result of the `Map` will be something like `[null, null, null]`, in the case of a job with three callback endpoints. That array is assigned to `$.Void` in the `ResultPath` and can be ignored.

#### Map

- `InputPath`: `$`, `{ Job: { … } }`
- `Parameters`: `{ Callback: { … }, Message: { … } }`
- `ResultPath`: `$.Void`, `{ Job: { … }, Void: [ … ] }`
- `OutputPath`: `$`, `{ Job: { … }, Void: [ … ] }`

#### Iterator

- `InputPath`: `$`, `{ Callback: { … }, Message: { … } }`
- `Parameters`: n/a, `{ Callback: { … }, Message: { … } }`
- `ResultPath`: `$`, `null`
- `OutputPath`: `$`, `null`

### Ingest Source File

The Ingest function relies on the `Job.Source` data. It also uses the Step Function execution ID to isolate work it's doing. The entire input must remain available to later states, so there's no `InputPath`. The necessary data is passed to the Lambda function as `Parameters`, including the interpolated execution ID.

The result of the Lambda function is inserted into the output under the `Artifact` property, and the entire output (the input with the `Artifact`) is passed to the next state.

- `InputPath`: `$`, `{ Job: { … } }`
- `Parameters`: `{ Job: { Source }, Execution: { Id }}`
- `ResultPath`: `$.Artifact`, `{ Job: { … }, Artifact: { … } }`
- `OutputPath`: `$`, `{ Job: { … }, Artifact: { … } }`

### Source File Type Detection

This Lambda function requires only the `Artifact` from the input, but, as before, the entire input must be maintained in the output.

The output of the Lambda function is added to the `Artifact` object under the `Descriptor` key, and the entire output (the input with the amended `Artifact`) is passed to the next state.

- `InputPath`: `$`, `{ Job: { … }, Artifact: { … } }`
- `Parameters`: `{ Arifact: {} }`
- `ResultPath`: `".Artifact.Descriptor`, `{ Job: { … }, Artifact: { … } }`
- `OutputPath`: `$`, `{ Job: { … }, Artifact: { … } }`

### Execute Tasks

This is another `Map` state, which iterates over every element of the `Job.Tasks` array.

The `Parameters` for each iteration are constructed to provide all the information needed to execute each task. That includes: the job ID, the execution ID, the artifact, the current value of the iterator (i.e., a task), the current index of the iterator, and all the callback endpoints defined on the job.

The result of the iterator (an array of each task's results) is assigned to `$.TaskResults`.

#### Map

- `InputPath`: `$`, `{ Job: { … }, Artifact: { … } }`
- `Parameters`: `{ Job, Execution, Artifact, Index, Task, Callbacks }`
- `ResultPath`: `$.TaskResults`, `{ Job: { … }, Artifact: { … }, TaskResults: [ … ] }`
- `OutputPath`: `$`, `{ Job: { … }, Artifact: { … }, TaskResults: [ … ] }`

#### Iterator

The iterator (unlike the callbacks iterator, which included only a single state), has several components. A `Choice` state is used to inspect the `Task.Type`, which determines the next task-specific state to run. (E.g., When iterating over a task that include `"Type": "Copy"`, the state machine will follow a branch to the copy task state.)

Each task-speicfic state creates a set of parameters determined by the needs of that task, but they all will map their output to `$.TaskResult`.

After a task has completed, callbacks are sent. This follows the same pattern as described above, thus the callback iterator exists within the task iterator. The result of the callback iterator is mapped to `$.Void`, and the `OutputPath` is set to `$.TaskResult`. The effect of this is that even though the callbacks are at the end of the chain, and final output of the entire `Maps` state of tasks is all the individual task results, and only those results.

### Job Callbacks

As with the previous callbacks, this follows a similar iterator pattern. Each job callback contains a complete set of tasks results for all tasks that were run by the job. The results that are included in the callback message are filtered from the entire list of results using the [JsonPath](https://github.com/json-path/JsonPath) query: `$.TaskResults.[?(@.Task && @.Task != 'Null')]`. This removes any null task results, which result from unknown task types being included in a job.

The output of this state should pass along the input. It may contain additional data from the individual callback executions, but because callbacks are optional, those values may not exist.

- `InputPath`: `$`, `{ Job: { … }, Artifact: { … }, TaskResults: [ … ] }`
- `Parameters`: `{ Callback: { … }, Message: { … } }`
- `OutputPath`: `$`, `{ Job: { … }, Artifact: { … }, TaskResults: [ … ], Void: [ … ] } }`

### Job Serializer

The job serializer is an iterator that comes into play if a job includes an `SerializedJobs`. It has no impact on the other aspects of the state machine execution, has no meaningful output, and only deals with the `SerializedJobs` that was originally defined on the input job message.

- `InputPath`: `$`, `{ Job: { … }, Artifact: { … }, TaskResults: [ … ] }`
- `Parameters`: `{ Execution: { … }, ExecutionTrace: [ … ], SerializedJob: { … } }`
- `ResultPath`: `$.Void`,  `{ Job: { … }, Artifact: { … }, TaskResults: [ … ], Void: [ … ] } }`
- `OutputPath`: `$`, `{ Job: { … }, Artifact: { … }, TaskResults: [ … ], Void: [ … ] } }`

### Output Normalization

After callbacks have been sent, there's a final step that normalizes the output of the state machine. The resulting value is intended to match the message sent as part of each job callback.

As with the timestamps included in all callbacks, the timestamps in the state machine output represent the time that the output was generated, not the time that any other specific aspect of the state machine occurred. I.e., even if a given execution only has a single callback, the timestamps in the callback message and the execution output will almost certainly be different.

- `InputPath`: `$`, `{ Job: { … }, Artifact: { … }, TaskResults: [ … ] } }`
- `Parameters`: `{ Message: { … } }`
- `ResultPath`: `$`, `{ Time, Timestamp, JobResult }`
- `OutputPath`: `$`, `{ Time, Timestamp, JobResult }`

This state is the true end of the state machine.

## Adding Task Types

- Create a new choice matcher in the `RouteTaskType` state to identify the `Type` of the new task, and route it to a new state within the iterator
- Add the new state with a resource that can execute the task. Look at existing states for examples that use Lambda and Fargate. Construct `Parameters` for the task as necessary, and set the `ResultPath` to `$.TaskResult`. Be sure that `SendTaskCallbacks` is called `Next`.
- For Lambda functions that generate data which needs to be returned through the callbacks, ensure that the return value includes a `Task` property (such as `"Task": "Copy"`). Fargate-backed states cannot currently retun data from their execution environment to the state machine. If necessary, you can write the data to a file in S3, and use a Lambda function state that runs after the Fargate task to fetch and return the data.
