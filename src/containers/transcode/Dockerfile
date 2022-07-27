FROM public.ecr.aws/amazonlinux/amazonlinux:latest

RUN amazon-linux-extras install ruby3.0

RUN yum update -y \
    && yum install -y tar wget xz \
    && yum clean all

ENV APP_HOME /transcode
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

RUN wget https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz
RUN tar xvf ffmpeg-git-amd64-static.tar.xz
RUN mkdir -p ffmpeg-bin
RUN mv ffmpeg-git-*-amd64-static/ffmpeg ffmpeg-bin/
RUN mv ffmpeg-git-*-amd64-static/ffprobe ffmpeg-bin/

ADD transcode.py ./
RUN chmod +x ./transcode.rb

ENTRYPOINT ["./transcode.rb"]
