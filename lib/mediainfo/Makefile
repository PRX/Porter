
build-MediaInfoLambdaLayer:
	mkdir -p "$(ARTIFACTS_DIR)/bin"
	curl https://mediaarea.net/download/binary/mediainfo/24.06/MediaInfo_CLI_24.06_Lambda_x86_64.zip --output "$(ARTIFACTS_DIR)/MediaInfo_CLI_24.06_Lambda_x86_64.zip"
	tar xf "$(ARTIFACTS_DIR)/MediaInfo_CLI_24.06_Lambda_x86_64.zip" -C "$(ARTIFACTS_DIR)/bin"
	mv "$(ARTIFACTS_DIR)/bin/bin/mediainfo" "$(ARTIFACTS_DIR)/bin"
	chmod +x "$(ARTIFACTS_DIR)/bin/mediainfo"
	rm "$(ARTIFACTS_DIR)/MediaInfo_CLI_24.06_Lambda_x86_64.zip"
	rm -r "$(ARTIFACTS_DIR)/bin/bin"
