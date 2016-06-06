#!/usr/bin/env ruby
require 'rubygems'
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'sinatra'


# Get Thee PuppetURL from an environment variable, and automatically
# protect from people adding a slash to the end of their URL's
puppet_url = ENV['PUPPET_URL'].chomp('/')

# Base URL of the PuppetDB database; default if undefined
HOST_URL = puppet_url ||= 'http://puppet:8080'
# Number of seconds to cache the previous results for
CACHE_SECONDS = ENV['CACHE_SECONDS'].to_i ||= 1800

class PuppetDB

  def initialize
    @resources = nil
    @facts = nil
    @resources_fetched_at = nil
    @facts_fetched_at = nil
  end

  def get_json(url, form_data = nil)
    uri = URI.parse( url )
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Get.new(uri.path)
    if form_data
      request.set_form_data( form_data )
      request = Net::HTTP::Get.new( uri.path+ '?' + request.body )
    end
    request.add_field("Accept", "application/json")

    response = http.request(request)
    json = JSON.parse(response.body)
  end

  def resources
    if !@resources_fetched_at || Time.now > @resources_fetched_at + CACHE_SECONDS
      #    	puts "Getting new PuppetDB resources: #{Time.now} > #{@resources_fetched_at} + #{CACHE_SECONDS}"
      @resources = get_resources
      @resources_fetched_at = Time.now
    end
    @resources
  end

  def get_resources
    puppetdb_resource_query = {'query'=>'["=", "type", "Class"],]'}
    url = "#{HOST_URL}/v3/resources"
    resources = get_json(url, puppetdb_resource_query)
  end

  def facts
    if !@facts_fetched_at || Time.now > @facts_fetched_at + CACHE_SECONDS
      #    	puts "Getting new PuppetDB facts: #{Time.now} > #{@facts_fetched_at} + #{CACHE_SECONDS}"
      @facts = get_facts
      @facts_fetched_at = Time.now
    end
    @facts
  end

  def get_facts
    url = "#{HOST_URL}/v3/facts"
    facts = get_json(url)
  end

  def nodes
    if !@nodes_fetched_at || Time.now > @nodes_fetched_at + CACHE_SECONDS
      #    	puts "Getting new PuppetDB nodes: #{Time.now} > #{@nodes_fetched_at} + #{CACHE_SECONDS}"
      @nodes = get_nodes
      @nodes_fetched_at = Time.now
    end
    @nodes
  end

  def get_nodes
    url = "#{HOST_URL}/v3/nodes"
    nodes = get_json(url)
  end
end

class Rundeck
  def initialize(puppetdb)
    @resources = Hash.new
    @resources_built_at = nil
    @puppetdb = puppetdb
  end

  def puppetdb
    @puppetdb
  end

  def build_resources
    # Create a new resources hash which automatically creates new
    # hash values when a new key is first assigned
    resources = Hash.new { |k,v| k[v] = {} }

    @puppetdb.nodes.each do |n|
      resources[n['name']] ||= {}
    end

    @puppetdb.facts.each do |d|
      next if d['name'] == "hostname"

      host  = d['certname']
      name  = d['name']
      value = d['value']

      resources[host][name] = value

    end
    resources
  end

  def resources
    if !@resources_built_at || Time.now > @resources_built_at + CACHE_SECONDS
      @resources = build_resources
      @resources_built_at = Time.now
    end
    @resources
  end
end

puppetdb = PuppetDB.new
rundeck  = Rundeck.new(puppetdb)

set :bind, '0.0.0.0'

get '/' do
  content_type 'application/yaml'
  rundeck.resources.to_yaml
end
