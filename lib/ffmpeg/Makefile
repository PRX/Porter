build-FfmpegLambdaLayer:
	curl https://media.prx.org/tech/ffmpeg-git-amd64-static.tar.xz --output "$(ARTIFACTS_DIR)/ffmpeg-release-amd64-static.tar.xz"
	tar xf "$(ARTIFACTS_DIR)/ffmpeg-release-amd64-static.tar.xz" -C "$(ARTIFACTS_DIR)"
	rm "$(ARTIFACTS_DIR)/ffmpeg-release-amd64-static.tar.xz"
	mkdir -p "$(ARTIFACTS_DIR)/bin"
	find "$(ARTIFACTS_DIR)" -type f -name "ffmpeg" -exec mv {} "$(ARTIFACTS_DIR)/bin/ffmpeg" \;
	find "$(ARTIFACTS_DIR)" -type f -name "ffprobe" -exec mv {} "$(ARTIFACTS_DIR)/bin/ffprobe" \;
	find "$(ARTIFACTS_DIR)" -type d -name "ffmpeg-*" -exec rm -r {} +
