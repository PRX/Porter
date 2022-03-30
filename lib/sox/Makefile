build-SoxLambdaLayer:
	mkdir -p "$(ARTIFACTS_DIR)/bin"
	curl https://raw.githubusercontent.com/serverlesspub/sox-aws-lambda-binary/master/vendor/bin/sox --output "$(ARTIFACTS_DIR)/bin/sox"
	chmod +x "$(ARTIFACTS_DIR)/bin/sox"

	mkdir -p "$(ARTIFACTS_DIR)/lib64"
	curl https://raw.githubusercontent.com/jsonmaur/lambda-audio/master/lib64/libgomp.so.1 --output "$(ARTIFACTS_DIR)/lib64/libgomp.so.1"
