FROM public.ecr.aws/amazonlinux/amazonlinux:latest

LABEL org.prx.app="yes"

RUN yum update -y \
    && yum install -y python-pip tar wget xz \
    && yum clean all
RUN pip install boto3

ENV APP_HOME /transcode
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

RUN wget https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz
RUN tar xvf ffmpeg-git-amd64-static.tar.xz

ADD transcode.py ./
RUN chmod +x ./transcode.py

ENTRYPOINT ["./transcode.py"]
