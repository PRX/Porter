build-SharpLambdaLayer:
	# TODO Build this layer, rather than copy a static asset
	curl https://media.prx.org/tech/npm-sharp.zip --output "$(ARTIFACTS_DIR)/npm-sharp.zip"
	unzip "$(ARTIFACTS_DIR)/npm-sharp.zip" -d "$(ARTIFACTS_DIR)"
	mv "$(ARTIFACTS_DIR)/nodejs/node_modules" "$(ARTIFACTS_DIR)/node_modules"
	rm -r "$(ARTIFACTS_DIR)/nodejs"
	rm "$(ARTIFACTS_DIR)/npm-sharp.zip"
