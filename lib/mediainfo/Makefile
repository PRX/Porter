
build-MediaInfoLambdaLayer:
	mkdir -p "$(ARTIFACTS_DIR)/bin"
	curl https://mediaarea.net/download/binary/mediainfo/24.06/MediaInfo_CLI_24.06_Lambda_x86_64.zip --output "$(ARTIFACTS_DIR)/MediaInfo_CLI_24.06_Lambda_x86_64.zip"
	unzip -j "$(ARTIFACTS_DIR)/MediaInfo_CLI_24.06_Lambda_x86_64.zip" bin/mediainfo -d "$(ARTIFACTS_DIR)/bin"
	chmod +x "$(ARTIFACTS_DIR)/bin/mediainfo"
	rm "$(ARTIFACTS_DIR)/MediaInfo_CLI_24.06_Lambda_x86_64.zip"
