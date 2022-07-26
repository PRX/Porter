FROM public.ecr.aws/amazonlinux/amazonlinux:latest

LABEL org.prx.app="yes"

RUN yum update -y \
  && amazon-linux-extras enable ruby2.6 \
  && yum install -y ruby ruby-irb ruby-devel rubygems rubygem-rake rubygem-json rubygem-io-console \
  && gem install bundler \
  && yum clean metadata \
  && rm -rf /var/cache/yum

ENV APP_HOME /ftp
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

ADD Gemfile* ./
RUN bundle install
ADD *.rb ./

ADD run ./
RUN chmod +x ./ftp.rb
RUN chmod +x ./get-ecs-task-public-ip.rb
RUN chmod +x ./run

ENTRYPOINT ["./run"]
