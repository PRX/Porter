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
RUN bundle config set --local without development && bundle install

ADD hls.rb telemetry.rb Makefile .
ADD destinations destinations/
ADD presets presets/
ADD lib lib/
ADD test test/
RUN chmod +x ./hls.rb

ENTRYPOINT ["./hls.rb"]
