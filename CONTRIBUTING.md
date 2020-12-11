# Porter

#### Useful Resources

- [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/welcome.html)
- [Amazon States Language](https://states-language.net/)
- [AWS Serverless Application Model](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html)
- [AWS SAM CLI Command Reference](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-command-reference.html)
- [FFmpeg Static Builds](https://www.johnvansickle.com/ffmpeg/)
- [FFmpeg CLI Command Reference](https://ffmpeg.org/ffmpeg.html)

## Project Standards & Guidelines

Porter integrates a number of different services, technologies, frameworks, and programming languages. In order to help with project maintenance and reducing mental overhead when working on the project, please follow the standards and guidelines described in this section. Whenever possible, ensure that any new or changed standards are documented here and are enforced automatically, such as by tests and IDEs.

### Security

Take a _least privilege_ approach to all aspects of security. Create discrete IAM roles for each Lambda function, Fargate task, etc, and only give the role the permissions it needs to operate. Use the private VPC subnets with VPC endpoints unless it's absolutely necessary that something have access to the public internet.

### Git & Source Control

Git commits always should follow the [seven rules](https://chris.beams.io/posts/git-commit/#seven-rules).

The `package-lock.json` file is not under version control. The NPM packages it tracks are only used in development, and the versions are largely irrelevant, so ignoring the lock file reduces unnecessary Git churn. The packages listed as `dependencies` are in there only to satisfy ESLint's path resolution checks.

### Code Style

Basic code style guidelines, such as tabs versus spaces, are captured in the project's [`.editorconfig`](https://editorconfig.org/) file. Different file types may follow different style guides. Ensure that you editor or IDE is set up to follow that configuration automatically. If necessary, create an application-specific configuration (such as with the `.vscode` directory for VS Code) that matches `.editorconfig`, and check it in so that others can benefit.

Language-specific code styles are handled by various libraries, such as [ESLint](https://eslint.org/) for JavaScript. Here's a list of all the linters and code checkers that are used by the project

- [ESLint](https://eslint.org/)
- [TypeScript](https://www.typescriptlang.org/docs/handbook/compiler-options.html)
- [Prettier](https://prettier.io/)
- [cfn-python-lint](https://github.com/aws-cloudformation/cfn-python-lint)
- [RuboCop](https://rubocop.org)

You should set up realtime checking with these tools in your IDE, such as type checking with TypeScript and linting with ESLint. You should also enable Prettier to format in realtime or on save. The test suite will fail if there are rules violations, so it's much easier to be validation code changes as you go.

While the project utilizes TypeScript for type checking and other other JavaScript syntax checking, Node.js-relate code should be written in vanilla JavaScript, and not TypeScript.

### Commands & Toolchain

The project includes a `Makefile` to centralize various commands used in development and operation. When new commands are required, be sure to add them to the `Makefile`, even if it calls out to something else, like `npm run-script`.

Besides language runtimes, package managers, and command line programs, tooling should be written to assume that libraries are installed within the package, not globally available on the system. I.e, do not asusme the `eslint` or `prettier` are install globally.

## Getting Started

After cloning the Git repository for Porter, run `make bootstrap` to install all necessary development dependencies. This requires already having Node.js, Ruby, and Python 3 installed on your system.

## Deploying

See the [INSTALL](https://github.com/PRX/Porter/blob/master/INSTALL.md) guide for detailed information about deploying Porter to AWS.

## State Machine Guidelines

Various APIs and SDKs are inconsistent in how they refer to S3 buckets and objects. To be consistent throughout this project, they should be called `BucketName` and `ObjectKey` until they are passed to an API.

For the sake of clarity, when building states in ASL always include the `InputPath`, `ResultPath`, and `OutputPath`, even if they are set to the default value.

Timestamps should always be in seconds.

Create Lambda Layers for external dependencies. Do not include packages and libraries in the deployable Lambda code iteself.

The job input format should generally avoid using parameters specific to particular tools or libraries. The underlying tools used to perform any given task could change over time. In some cases, such as with FFmpeg where recreating the entire API would be impractical, this rule can be adapted.

When a state fails, in general the desired outcome is that the error gets caught by the state machine and a callback is sent, notifying the user of the issue. By catching errors, it is no longer possible to detect or count task errors by looking for state machine execution failures. Instead the resources themselves (Lambdas functions, etc) must be monitored.

Fargate tasks (like Transcode) run in a VPC that does not have internet access. Access to AWS APIs is provided by [VPC endpoints](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-endpoints.html). If you have a Fargate task running in the VPC that needs access to a new AWS API, you'll have to add a new endpoint for it.

### S3 Access Permissions

There are two common reasons that a given state's resource (like a Lambda function or Fargate task) would need access to S3: reading from the artifact bucket, and writing new files to the destination buckets. (Reading the source file for the task should only ever be done by the ingest state.)

In the case of reading from the artifact bucket, there is a managed IAM policy that provides the necessary permissions: `ArtifactBucketReadOnlyAccessPolicy`. You can include this in the list of `ManagedPolicyArns` for IAM roles you create for your stack resources.

Permissions for writing files to destination buckets is handled **by the buckets themselves**, through bucket policies (see the README for more information). The bucket policies will grant access to a specific IAM role that Porter publishes. Thus, any S3 operations against destination buckets must always use credentials for that IAM role. Any state resources (Lambda functions, Fargate tasks, etc), must request temporary credentials for that role, and use those credentials to sign any S3 requests to the destination buckets.

To recap, when adding new tasks or states to Porter's CloudFormation template:

1. Create an execution role for a given Lambda function/Fargate Task/etc. This would have policies needed for the task to execute *excluding* writing files to S3 destination buckets (e.g., publishing SNS messages, getting files from S3, writing files to the S3 artifact bucket, etc)
2. Ensure that that execution role is included as a principal in the `S3DestinationWriterRole` trust policy. This allows the execution role to assume the `S3DestinationWriterRole` role.
3. Design the task so that it assumes the `S3DestinationWriterRole` role, and uses the temporary credentials generated to sign any S3 requests to the destination buckets. (Note: A task may deal with other S3 buckets, so you may end up with multiple S3 service objects, which have different permissions.)

There's also `ArtifactBucketWriteAccessPolicy`, which provides write access to the artifact bucket. The artifact bucket is primarily used to store the source file for a task execution, but if you have a task that needs to persist metadata somewhere for the duration of an execution (such as to pass a value between decoupled services, or to store a large file that requires further processing), the artifact bucket can be used for those needs as well. Take care to make sure anything you're writing to the artifact bucket can't interfer with another execution's data. Common practice is to prefix any objects you create with the state machine execution ID. Objects in the artifact bucket expire very quickly, so it should never be used as the final destination for any critical data.

### Internal Messaging

How data is passed into and between between the various states of the Step Function is key to building a reliable state machine, and understanding the flow of data in invaluable when developing this project. The following is a detailed look at the lifecycle of inputs and outputs of the state machine internals. The code examples are meant to demonstrate important structural aspects, and are not necessarily 100% accurate.

[Input and output processsing](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-input-output-filtering.html) is used extensively to ensure that the data being passed between states is clean, and the data being passed to task resources (Lambda functions, etc) is appropriately scoped. A good understanding of how the state I/O and task resource I/O interact is crucial.

In some cases, states will use a result path of `$.Void` if their return values are unwanted.

### Execution Overview

**Input:** Job execution input provided by the end user as raw JSON (via SNS, EventBridge, etc). The format is covered in detail in the [README](https://github.com/PRX/Porter/blob/master/README.md). The input is normalized to ensure that certain properties exist. This allows properties to be optional in the job input, even when the state machine definition requires them to exist. As soon as the input has been normalized, callbacks are sent inform the client that the job was recieved.

**Pre-processing:** While the heart of any given job execution is the individual tasks that are passed in, there are a number of things that happen in the state maching prior to the tasks starting (including the previously mentioned normalization). The source file is downloaded and a copy is created in the artifact S3 bucket. This is the file that tasks will do their work against. It's helpful to reliably know what the type of the source file is, so some number of bytes of the artifact are examined to detect the file type with a high degree of accuracy. This information is available to subsequent states as both a MIME type and the common extension of the determined type.

Once all pre-processing has completed, the internal state of the machine is sufficient for task execution. If any pre-processing steps fail, each one is configured to fail to a unique `Pass` state, which injects a paramater into the state indicating where the failure occurred. Any additonal pre-processing states that are added should use their own `Pass` state for failures, with a unique `Result` value output to `$.State`.

**Callbacks:** Callbacks can be sent to an arbitrary number of endpoints, determined by the size of the `Job.Callbacks` array in the job input. This can be any combination of various types of endpoints (HTTP, SNS, etc). While there are several differnt flavors of callbacks sent (or not) at various points during job exectuion (job recieved, task completesd, task failed, etc), they are all handled by a single Lambda function. Each function invocation handles a single callback message (i.e., one message being sent to one endpoint).

The state input sent to the Lambda function (i.e., the `event` parameter) is defined by the `Parameters` property of a `Map` state that wraps the `Task` states which actually invoke the callback Lambda function. The payload sent in each callback message is *always* the JSON (string) representation of the `Message` property on the maps `Parameters`, regardless callback type or endpoint type. If data needs to be included in a callback message, it must appear in the state machine ASL. The exception to this are the `Time` and `Timestamp` values that get injected at the time the callback messages are sent.

**Task Execution:** For each item in the job input's `Tasks` list, a `Map` state's iterator will run once. This is a complex iterator that is responsible for routing the execution on the correct path based on the task type (and potentially other properties). For example a `Copy` task will be sent to a state with a Lambda function that handles file copying, while a `Transcode` task will be sent to a series of states, including Lambda functions and Fargate tasks, to transcode audio and video. All of that routing logic happens inside the map's iterator.

Within the iterator, the states responsible for execution the tasks have failure handling that also is isolated within the iterator. When a task state fail, it is caught handled by a task error callback state that exists within the iterator. This means that in a job with multiple tasks, one run of the iterator could fail and another could succeed; they are isolated. This is distinct from the task `Map` state itself failing. If the iterator itself or something within the iterator fail in a way that can't be handled gracefully, the map state fails to a `Pass` state, similar to the pre-processing states.

Each task type or subtype will have its own execution path. These paths can be any size and including their own branching if necessary. As described before, they can be as simple as the single-state copy task, or more complex like the transcode task. Regardless of a path's shape, the output for any run of the iterator must be consistent. Task callbacks are always the last thing to happen within the iterator, so the input sent to the callback map state must meet the expected requirements. The task results sent to the callback map must include a `TaskResult` property.

For example, if there's a `Add` task, which adds numbers using a Lambda function, the function would return a value like `{ Sum: 42 }` (not JSON), and the ASL state definition would include `"ResultPath": "$.TaskResult"` to set that value as the task result, along with `"OutputPath": "$"` to ensure the callback map gets all the other state information it needs to do its job. This is true regardless of which resource or services backs the state, even when it's not a Lambda function. Sometimes it's necessary to include an additional Lambda-based state to provide the correct output, such as with Fargate-based tasks, since Faragte does not return any output to the state machine.

By convention, the `TaskResult` should include a `Task` property whose value is set to the task type (e.g., `"Task": "Sum"`), as well as properties that include any relevant data generated by the task (e.g., `"Sum": 42`). The `TaskResult` should also include properties that uniquely identify the specific task that produced the result. For example, if a job includes multiple S3 copy tasks, the bucket name and object key can act to match the result with the original task request. If the result of a `Sum` task is only `{ "Sum": 42 }`, there would be no way for a client to distinguis that result from other `Sum` task results included in the same job. Always assume that a job can include any number of a given task type.

**Post-processing:** After task execution has concluded (regardless of how successful the individual tasks were), there are some additional steps the state machine takes. Callbacks are sent with a complete job result, if there are any serialized jobs they are started asynchronously, and the final state machine output is normalized. This normalization is done so that the execution output of the job in Step Functions matches the payload sent as the `JobResult` callback as closely as possible.

## Adding Task Types

Here's a very generalized approach to adding a new task type, which should cover many cases:

- In the state machine ASL, create a new choice matcher in the `Route Task By Type` state to identify the `Type` of the new task (or any other properties), and route it to a new state within the iterator.
- Add the new state or states with a resource that can execute the task. Look at existing states for examples that use Lambda and Fargate. Construct `Parameters` for the task as necessary, and set the `ResultPath` to `$.TaskResult`. Be sure that `TaskResult Callbacks Map` is called `Next`, and `TaskResult Error Callback Map` is used in the `Catch` definition.
- For Lambda functions that generate data which needs to be returned through the callbacks, ensure that the return value includes a `Task` property (such as `"Task": "Copy"`). Fargate-backed states cannot currently retun data from their execution environment to the state machine. If necessary, you can write the data to a file in S3, and use a Lambda function state that runs after the Fargate task to fetch and return the data.
- Update this CONTRIBUTING document if there are any significant changes to the **Execution Overview** or other areas.
- Add documentation to the README to describe the task input requirementss and the task result output.
