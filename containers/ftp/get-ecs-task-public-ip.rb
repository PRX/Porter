#!/usr/bin/ruby

require 'rubygems'
require 'bundler/setup'
require 'net/http'
require 'json'
require 'uri'
require 'aws-sdk-ec2'
require 'aws-sdk-ecs'

ecs = Aws::ECS::Client.new
ec2 = Aws::EC2::Client.new

# short circuit - no $ECS_CONTAINER_METADATA_URI_V4, then don't bother
exit 1 unless ENV['ECS_CONTAINER_METADATA_URI_V4']

uri = URI.parse(ENV['ECS_CONTAINER_METADATA_URI_V4'])
task_json = Net::HTTP.get(uri.host, File.join(uri.path, 'task'))
meta = JSON.parse(task_json)
exit 1 unless meta['Cluster'] && meta['TaskARN']

ecs_res = ecs.describe_tasks(cluster: meta['Cluster'], tasks: [meta['TaskARN']])
details = ecs_res['tasks'][0]['attachments'][0]['details']
eni_id = details.find { |d| d['name'] == 'networkInterfaceId' }['value']
exit 1 unless eni_id

ec2_res = ec2.describe_network_interfaces(network_interface_ids: [eni_id])
ip = ec2_res['network_interfaces'][0]['association']['public_ip']
exit 1 unless ip

print ip
