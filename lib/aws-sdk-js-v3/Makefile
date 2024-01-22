build-AwsSdkJsV3LambdaLayer:
	mkdir -p "$(ARTIFACTS_DIR)/nodejs"
	npm install --prefix "$(ARTIFACTS_DIR)/nodejs" @aws-sdk/util-retry
	npm install --prefix "$(ARTIFACTS_DIR)/nodejs" @aws-sdk/middleware-retry
	npm install --prefix "$(ARTIFACTS_DIR)/nodejs" @aws-sdk/client-cloudwatch
	npm install --prefix "$(ARTIFACTS_DIR)/nodejs" @aws-sdk/client-s3
	npm install --prefix "$(ARTIFACTS_DIR)/nodejs" @aws-sdk/client-sns
	npm install --prefix "$(ARTIFACTS_DIR)/nodejs" @aws-sdk/client-sqs
	npm install --prefix "$(ARTIFACTS_DIR)/nodejs" @aws-sdk/client-sfn
	npm install --prefix "$(ARTIFACTS_DIR)/nodejs" @aws-sdk/client-sts
	npm install --prefix "$(ARTIFACTS_DIR)/nodejs" @aws-sdk/client-eventbridge
	npm install --prefix "$(ARTIFACTS_DIR)/nodejs" @aws-sdk/client-transcribe
	npm install --prefix "$(ARTIFACTS_DIR)/nodejs" @aws-sdk/lib-storage
