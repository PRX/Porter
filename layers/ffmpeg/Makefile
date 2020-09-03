build-FfmpegLambdaLayer:
	# TODO Build this layer, rather than copy a static asset
	curl https://media.prx.org/tech/bin-ffmpeg.zip --output "$(ARTIFACTS_DIR)/bin-ffmpeg.zip"
	unzip "$(ARTIFACTS_DIR)/bin-ffmpeg.zip" -d "$(ARTIFACTS_DIR)"
	rm "$(ARTIFACTS_DIR)/bin-ffmpeg.zip"
