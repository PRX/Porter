FROM amazonlinux:latest
RUN yum -y install aws-cli
RUN yum -y install wget
RUN yum -y install tar
RUN yum -y install xz

ENV APP_HOME /transcode
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

RUN wget https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz
RUN tar xvf ffmpeg-git-amd64-static.tar.xz

ADD transcode.sh ./
RUN chmod +x ./transcode.sh

RUN ls

ENTRYPOINT ["./transcode.sh"]
