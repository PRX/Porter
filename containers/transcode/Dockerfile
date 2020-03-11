FROM amazonlinux:latest

LABEL org.prx.app="yes"

RUN yum -y install aws-cli
RUN yum -y install wget
RUN yum -y install tar
RUN yum -y install xz
RUN yum install -y jq

ENV APP_HOME /transcode
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

RUN wget https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz
RUN tar xvf ffmpeg-git-amd64-static.tar.xz

ADD transcode.sh ./
RUN chmod +x ./transcode.sh

ENTRYPOINT ["./transcode.sh"]
