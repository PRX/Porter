FROM public.ecr.aws/amazonlinux/amazonlinux:2023

RUN dnf update -y \
    && dnf install -y ruby3.2 ruby-devel make gcc

ENV APP_HOME=/ftp
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

ADD Gemfile* ./
RUN bundle config set without 'development test' && bundle install
ADD *.rb ./

ADD run ./
RUN chmod +x ./ftp.rb
RUN chmod +x ./get-ecs-task-public-ip.rb
RUN chmod +x ./run

ENTRYPOINT ["./run"]
