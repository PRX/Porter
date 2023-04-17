FROM public.ecr.aws/amazonlinux/amazonlinux:2023

RUN dnf update -y \
    && dnf install -y wget tar xz \
    && dnf install -y ruby3.2

# See https://docs.aws.amazon.com/linux/al2023/release-notes/all-packages.html
# to figure out which specific version of Ruby is installed using the ruby3.2
# package.

ENV APP_HOME /transcode
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

RUN wget https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz
RUN tar xvJf ffmpeg-git-amd64-static.tar.xz
RUN mkdir -p ffmpeg-bin
RUN mv ffmpeg-git-*-amd64-static/ffmpeg ffmpeg-bin/
RUN mv ffmpeg-git-*-amd64-static/ffprobe ffmpeg-bin/

ADD Gemfile .
ADD Gemfile.lock .
RUN bundle install

ADD transcode.rb .
RUN chmod +x ./transcode.rb

ENTRYPOINT ["./transcode.rb"]
