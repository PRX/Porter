# Porter

Porter is built using the [AWS Serverless Application Model](https://aws.amazon.com/serverless/sam/) (SAM) framework, and is launched and managed using the associated [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-reference.html#serverless-sam-cli) toolchain. SAM is a layer on top of [AWS CloudFormation](https://aws.amazon.com/cloudformation/).

### Standard deployment

Most deploys will use the included **`make deploy`** command, with a specific target environment, like `make deploy env=prod`. This will build, test, lint, and deploy the application. Continue reading for more details about those steps.

For additional details about setting up a development environment see the [CONTRIBUTING](https://github.com/PRX/Porter/blob/master/CONTRIBUTING.md) documentation.

## Building

The SAM template defines a number of Lambda [layers](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/building-layers.html) resources that must build before they can be deployed. The [build](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-cli-command-reference-sam-build.html) command will execute the Makefile for each layer, and generate build artifacts (in `.aws-sam/build`) from the result. These artifact will be utilized automatically by the CLI during a deploy.

The build command will also create a new version of the template, with file references updated to point to the build artifacts. For example, in the source template the `AwsXraySdkLambdaLayer` resource includes `ContentUri: lib/aws-xray-sdk`. The rebuilt template (which also lives in `.aws-sam/build`) replaces that with `ContentUri: AwsXraySdkLambdaLayer` to reference the build artifact.

The SAM build command does not publish anything to S3 or elsewhere. It only creates local artifacts.

The build command will also create build artifacts for every Lambda function in the template, but the artifacts are identical to the source, since they don't include a Makefile or any packages.

Because some build components require native binaries that must work in the AWS Lambda runtime environment, you should use the `--use-container` flag, to execute the build inside a Lambda-like Docker container.

If you need to build the project without deploying, you should use `make build` or `make clean && make build`, to use a standard set of build command options. Generally, you won't need to explicitly build the project, as it will happen during the deploy process.

## Deploying

Deploying Porter is handled largely by the SAM CLI [deploy](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-cli-command-reference-sam-deploy.html) command. It will inspect the template being deployed for any local file references (such as for Lambda function code or Lambda layer content), upload those files to S3, and transparently deploy a version of the template with the local references replaced by the resulting S3 URIs.

**Be aware** that the `deploy` command _will_ deploy either the source template or a build artifact template. Both templates are perfectly valid SAM templates, but deploying the source template **will not produce the results you expect**. This is because the source template references unbuilt files for the included Lambda layers. Deploying the source template will create Lambda layers that include only a Makefile (like the one found in `lib/ffmpeg`), rather than the library, package, or npm module that's expected.

Be sure to always run `deploy` only once build artifacts have been created.

The options for any `deploy` are controlled using the `samconfig.toml` file, which should includes command parameters for a variety of deployment environments (prod, stag, etc). These command parameters include a set of template parameters. There are five required template parameters that should be listed as `parameter_overrides` in the config file:

- `EnvironmentType`
- `OpsWarnMessagesSnsTopicArn`
- `OpsErrorMessagesSnsTopicArn`
- `TranscodeJobNamePrefix`
- `TranscodeEcsTaskDefinitionImage`

There are additional template parameters that can be set if needed. Check out the template for a complete list of parameters. See `samconfig.example.toml` for a complete sample of a multi-environment configuration.

Rather than calling `sam deploy` directly, you should use `make deploy env=stag`, where `stag` is a table of parameters that exists in `samconfig`, and can be replaced with any other target you need. `make deploy` will run tests and code checks and build the project prior to deploying. If you are unsure of the age of your build artifacts, you can run `make clean` first to ensure that all artifacts are rebuilt fresh.

The tests that are run as part of the deploy run locally (i.e., not in Docker). They will require project dependencies like Ruby gems being installed (`bundle install`) and Node packages being installed (`npm install`).

Deploying a Porter stack creates a number of AWS resources that will be retained if the stack is deleted. This includes S3 buckets, some VPC components, etc. These are retained for a variety of reasons; see the documentation for each resource type for more information.

### VS Code

There is a VS Code task called `SAM:Deploy` that will call `make deploy` for a number of pre-configured targets.
