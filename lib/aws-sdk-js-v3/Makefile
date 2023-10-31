build-AwsSdkJsV3LambdaLayer:
	mkdir -p "$(ARTIFACTS_DIR)/nodejs/node_modules"
	yarn add @aws-sdk/util-retry
	yarn add @aws-sdk/middleware-retry
	yarn add @aws-sdk/client-cloudwatch
	yarn install --modules-folder "$(ARTIFACTS_DIR)/nodejs/node_modules"
