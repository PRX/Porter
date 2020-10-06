# Porter

Porter is built using the [AWS Serverless Application Model](https://aws.amazon.com/serverless/sam/) (SAM) framework, and is launched and managed using the associated [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-reference.html#serverless-sam-cli) toolchain. SAM is a layer on top of [AWS CloudFormation](https://aws.amazon.com/cloudformation/).

## Deploying

The standard method of deploying Porter is to use `sam deploy` with a `samconfig.toml` file. There are five required template parameters that should be listed as `parameter_overrides` in the config file:

- `EnvironmentType`
- `OpsWarnMessagesSnsTopicArn`
- `OpsErrorMessagesSnsTopicArn`
- `TranscodeJobNamePrefix`
- `TranscodeEcsTaskDefinitionImage`

There are additional template parameters that can be set if needed. Check out the template for a complete list of parameters.

The values for these parameters, as well as the SAM deploy config, will depend on the Porter instance being deployed. See `samconfig.example.toml` for a sample file. There is currently no way to use any file other than `samconfig.toml` with the `deploy` command, so you may want to maintain separate config files for each Porter instance you deal with (e.g., `samconfig.prod.toml`, `samconfig.dev.toml`), and swap them into the correct file.

```
cp samconfig.prod.toml samconfig.toml && sam deploy && rm samconfig.toml
```

Deploying a Porter stack creates a number of AWS resources that will be retained if the stack is deleted. This includes S3 buckets, some VPC components, etc. These are retained for a variety of reasons; see the documentation for each resource type for more information.

### VS Code

There is a VS Code task called `SAM:Deploy` that can help with managing multiple config files. The task defines several application environments (e.g, `prod`, `test`), and will automatically copy the corresponding config file to `samconfig.toml` before the `deploy` command, and clean it up after the deploy completes.

## Building

The application template utilizes the [build](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-cli-command-reference-sam-build.html) capabilities of AWS SAM to make development and deployment easier. This allows the template to reference local files and code packages relative to the template, rather than files that are only accessible to CloudFormation (such as ZIP files in S3).

Because of this, the local code must be built and prepared before deploying. Building will package each AWS Lambda function defined in the template and send the package to S3. It will also build any Lambda [layers](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/building-layers.html) that have been defined, and publishes a new vesion of the layer if necessary.

Once built, the references to local files in the SAM template will be replaced during a deploy with the artifacts that were created.

Because some build components require native binaries that must work in the AWS Lambda runtime environment, you should use the `--use-container` flag, to execute the build inside a Lambda-like Docker container.

### Build command

`sam build --use-container`
