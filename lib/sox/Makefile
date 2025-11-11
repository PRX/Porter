build-SoxLambdaLayer:
	mkdir -p "$(ARTIFACTS_DIR)/bin"
	curl --fail https://raw.githubusercontent.com/serverlesspub/sox-aws-lambda-binary/master/vendor/bin/sox --output "$(ARTIFACTS_DIR)/bin/sox"
	chmod +x "$(ARTIFACTS_DIR)/bin/sox"

# This library is likely needed for SoX to function, but this source has
# vanished. Currently SoX is not used, so this isn't causing any problems, but
# it would need to be resolved in the future if SoX is needed.
# 	mkdir -p "$(ARTIFACTS_DIR)/lib64"
# 	curl --fail https://raw.githubusercontent.com/jsonmaur/lambda-audio/master/lib64/libgomp.so.1 --output "$(ARTIFACTS_DIR)/lib64/libgomp.so.1"
