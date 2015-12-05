#!/usr/bin/env ruby

require 'date'
require 'delegate'

require 'json'
require 'ostruct'
require 'yaml'

require 'tumblr_client'

require 'erb'
require 'css_parser' 
require 'inline-style'
require 'sendgrid-ruby'

blacklist = File.read('blacklist.txt').lines.map &:split
config_vars = YAML.load_file('config.yml')

class Post < SimpleDelegator
  def render(file)
    template = ERB.new File.new("templates/posts/#{file}.erb").read, nil, "%"
    return template.result(binding)
  end

  def to_s
    render("#{type}_post")
  end
end

Tumblr.configure do |config|
  config.consumer_key = config_vars["tumblr"]["consumer_key"]
  config.consumer_secret = config_vars["tumblr"]["consumer_secret"]
  config.oauth_token = config_vars["tumblr"]["oauth_token"]
  config.oauth_token_secret = config_vars["tumblr"]["oauth_token_secret"]
end

client = Tumblr::Client.new

num_posts = 20
posts = []
body = ""
offset = 0
last_timestamp = Date.today.to_time.to_i
day_ago = Date.today.prev_day.to_time.to_i

while last_timestamp > day_ago
  results = client.dashboard(limit: num_posts, offset: offset)

  posts.concat(results['posts'])

  offset += num_posts
  last_timestamp = results['posts'].last['timestamp']
end

posts_hash = posts.select {|post| post['timestamp'] > day_ago }
posts_hash = posts.select {|post| (post['tags'] & blacklist).empty? }

posts = JSON.parse(posts_hash.to_json, object_class: OpenStruct)

body << File.new("templates/email_header.html").read

posts.each do |post|
  body << Post.new(post).to_s
end

body << File.new("templates/email_footer.html").read

client = SendGrid::Client.new do |c|
  c.api_key = config_vars["sendgrid_key"]
end

mail = SendGrid::Mail.new do |m|
  m.to = config_vars["to_email"]
  m.from = config_vars["from_email"]
  m.subject = "Tumblr Digest for #{Date.today.strftime('%A, %b %e')}"
  m.text = InlineStyle.process(body)
end

res = client.send(mail)