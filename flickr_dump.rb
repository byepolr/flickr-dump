#!/usr/bin/env ruby
require 'yaml'
require 'byebug'
require 'flickraw'
require 'rubygems'
require 'mechanize'
require 'io/console'
require 'optparse'
require 'net/http'
require 'json'
require 'time'
require 'fileutils'

class FlickrDump
  SETTINGS_FILE = 'settings.yml'.freeze
  DEFAULT_PATH = './images'.freeze

  def self.run(options)
    new(options).run
  end

  def initialize(options)
    @path = options['path'] || DEFAULT_PATH
    FlickRaw.api_key = options['api_key']
    FlickRaw.shared_secret = options['api_secret']

    load_credentials

    if @access_token.nil? || @access_secret.nil?
      authorize_account
    else
      flickr.access_token = @access_token
      flickr.access_secret = @access_secret
      puts "You are now authenticated as #{flickr.test.login.username}"
    end
  end

  def authorize_account
    token = flickr.get_request_token
    auth_url = flickr.get_authorize_url(token['oauth_token'], perms: 'read')

    puts "Open url in browser to complete authentication process: #{auth_url}"
    puts 'Copy here the number given when you complete the process.'
    verify = gets.strip

    flickr.get_access_token(token['oauth_token'], token['oauth_token_secret'], verify)
    puts "You are now authenticated as #{flickr.test.login.username}"

    save_credentials(flickr.access_token, flickr.access_secret)
  rescue FlickRaw::FailedResponse => e
    puts "Authentication failed : #{e.msg}"
  end

  def load_credentials
    return unless File.file?(SETTINGS_FILE)

    settings = YAML::load_file(SETTINGS_FILE)
    @access_token = settings[:access_token]
    @access_secret = settings[:access_secret]
  end

  def save_credentials(access_token, access_secret)
    settings = {
      access_token: access_token,
      access_secret: access_secret
    }
    File.open(SETTINGS_FILE, 'w') do |file|
      file.write settings.to_yaml
    end
  end

  def run
  end
end

def help_menu_and_exit
puts <<-"EOHELP"
Download all files from flickr:

Usage: #{__FILE__} --path=/path/to/download/location --api_key=apc123... --api_secret=somesecret --access_token=mytoken --access_secret=secret

OPTIONS
--path : /path/to/download/files/to
--api_key : API key for your flickr application
--api_secret : API secret for your flickr application
--help : help

EOHELP
  exit(0)
end

if File.expand_path($PROGRAM_NAME) == File.expand_path(__FILE__)
  options = {}
  parser = OptionParser.new do |opts|
    opts.on('-p', '--path path') do |path|
      options['path'] = path
    end

    opts.on('-k', '--api_key api_key') do |api_key|
      options['api_key'] = api_key
    end

    opts.on('-s', '--api_secret api_secret') do |api_secret|
      options['api_secret'] = api_secret
    end

    opts.on('-h', '--help', 'help menu') do
      help_menu_and_exit
    end
  end

  begin
    parser.parse!
    FlickrDump.run(options)
  rescue => ex
    puts ex
    puts ex.backtrace
    help_menu_and_exit
  end
end

