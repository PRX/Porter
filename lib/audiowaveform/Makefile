build-AudiowaveformLambdaLayer:
	mkdir -p "$(ARTIFACTS_DIR)/bin"
	curl --fail https://media.prx.org/tech/bin-audiowaveform.tar.gz --output "$(ARTIFACTS_DIR)/bin-audiowaveform.tar.gz"
	tar xf "$(ARTIFACTS_DIR)/bin-audiowaveform.tar.gz" -C "$(ARTIFACTS_DIR)/bin"
	chmod +x "$(ARTIFACTS_DIR)/bin/audiowaveform"
	rm "$(ARTIFACTS_DIR)/bin-audiowaveform.tar.gz"
