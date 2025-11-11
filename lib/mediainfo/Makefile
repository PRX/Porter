
build-MediaInfoLambdaLayer:
	mkdir -p "$(ARTIFACTS_DIR)/bin"
	curl https://mediaarea.net/download/binary/mediainfo/25.10/MediaInfo_CLI_25.10_Lambda_x86_64.zip --output "$(ARTIFACTS_DIR)/MediaInfo_CLI_25.10_Lambda_x86_64.zip"
	unzip -j "$(ARTIFACTS_DIR)/MediaInfo_CLI_25.10_Lambda_x86_64.zip" bin/mediainfo -d "$(ARTIFACTS_DIR)/bin"
	chmod +x "$(ARTIFACTS_DIR)/bin/mediainfo"
	rm "$(ARTIFACTS_DIR)/MediaInfo_CLI_25.10_Lambda_x86_64.zip"
