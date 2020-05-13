FROM amazonlinux:latest

LABEL org.prx.app="yes"

RUN yum update -y \
    && yum install -y aws-cli jq tar wget xz \
    && yum clean all

ENV APP_HOME /transcode
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

RUN wget https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz
RUN tar xvf ffmpeg-git-amd64-static.tar.xz

ADD transcode.sh ./
RUN chmod +x ./transcode.sh

ENTRYPOINT ["./transcode.sh"]
