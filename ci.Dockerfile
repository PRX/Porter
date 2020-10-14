FROM amazonlinux:latest

RUN amazon-linux-extras install ruby2.6
RUN amazon-linux-extras install python3.8

RUN yum update -y
RUN yum install -y gcc-c++ make \
    && curl -sL https://rpm.nodesource.com/setup_12.x | bash - \
    && yum install -y nodejs
RUN yum clean all

ENV APP_HOME /app
ENV HOME=$APP_HOME
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

ADD . .

# ADD package.json .
RUN npm install

# ADD Gemfile .
RUN gem install bundler
RUN bundle install

# ADD requirements.txt .
RUN /usr/bin/pip3.8 install -r requirements.txt

ENTRYPOINT [ "make" ]
