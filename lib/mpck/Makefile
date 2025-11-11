build-MpckLambdaLayer:
	curl --fail https://checkmate.gissen.nl/checkmate-0.21.tar.gz --output "$(ARTIFACTS_DIR)/checkmate-0.21.tar.gz"
	tar xvzf "$(ARTIFACTS_DIR)/checkmate-0.21.tar.gz" -C "$(ARTIFACTS_DIR)"
	(cd "$(ARTIFACTS_DIR)/checkmate-0.21" && ./configure --disable-dependency-tracking --prefix="$(ARTIFACTS_DIR)" && make && make install)
	rm "$(ARTIFACTS_DIR)/checkmate-0.21.tar.gz"
	rm -rf "$(ARTIFACTS_DIR)/checkmate-0.21"
