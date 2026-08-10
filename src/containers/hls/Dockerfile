FROM lscr.io/linuxserver/ffmpeg:latest

RUN apt-get update && \
    apt-get install -y \
    ruby-full \
    build-essential

RUN ruby -v

ENV APP_HOME=/ffmpeg
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

ADD Gemfile .
ADD Gemfile.lock .
ADD .tool-versions .
RUN gem install bundler
RUN bundle install

ADD hls.rb .
ADD telemetry.rb .
ADD destinations/aws/s3.rb .
ADD presets/standard_podcast_2026_v1.rb .
RUN chmod +x ./hls.rb

ENTRYPOINT ["./hls.rb"]
