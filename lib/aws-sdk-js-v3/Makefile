build-AwsSdkJsV3LambdaLayer:
	mkdir -p "$(ARTIFACTS_DIR)/nodejs/node_modules"
	yarn add @aws-sdk/util-retry
	yarn add @aws-sdk/middleware-retry
	yarn add @aws-sdk/client-cloudwatch
	yarn add @aws-sdk/client-s3
	yarn add @aws-sdk/client-sns
	yarn add @tokenizer/s3
	yarn install --modules-folder "$(ARTIFACTS_DIR)/nodejs/node_modules"
