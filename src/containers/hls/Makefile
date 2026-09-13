bootstrap:
	bundle install

test:
	bundle exec ruby -Itest -e 'Dir.glob("test/**/*_test.rb").sort.each { |f| require File.expand_path(f) }'

# Run the end-to-end local test: test/harness/run_local.rb.
SAMPLES := $(abspath ../../../test/samples)
SOURCE ?= $(SAMPLES)/big-buck-bunny-30s.mp4
OUT ?= out
BREAKS ?= 10.5,14.717,20.383

hls-local:
	@mkdir -p $(OUT)
	bundle exec ruby test/harness/run_local.rb $(SOURCE) $(OUT) $(BREAKS)

# Same, but with the container's ffmpeg -- the version that actually runs in prod.
hls-local-docker:
	docker build -t porter-hls .
	@mkdir -p $(OUT)
	docker run --rm \
	  -v $(SAMPLES):/samples:ro \
	  -v $(abspath $(OUT)):/out \
	  --entrypoint ruby porter-hls \
	  test/harness/run_local.rb /samples/$(notdir $(SOURCE)) /out $(BREAKS)

.PHONY: bootstrap test hls-local hls-local-docker
