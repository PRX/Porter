build-AwsSdkJsV3LambdaLayer:
	mkdir -p "$(ARTIFACTS_DIR)/nodejs/node_modules"
	yarn add @aws-sdk/client-cloudwatch
	yarn add @aws-sdk/client-eventbrige
	yarn add @aws-sdk/client-s3
	yarn add @aws-sdk/client-sfn
	yarn add @aws-sdk/client-sns
	yarn add @aws-sdk/client-sqs
	yarn add @aws-sdk/client-sts
	yarn add @aws-sdk/client-transcribe
	yarn install --modules-folder "$(ARTIFACTS_DIR)/nodejs/node_modules"
