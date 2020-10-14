FROM amazonlinux:latest

LABEL org.prx.app="yes"

RUN yum update -y \
    && yum install -y python-pip tar wget xz \
    && yum clean all
RUN pip install boto3

ENV APP_HOME /ftp
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

ADD ftp.py ./
RUN chmod +x ./ftp.py

ENTRYPOINT ["./ftp.py"]
