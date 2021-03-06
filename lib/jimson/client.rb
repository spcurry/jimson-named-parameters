require 'blankslate'
require 'multi_json'
require 'rest-client'
require 'jimson/request'
require 'jimson/response'

module Jimson
  class ClientHelper
    JSON_RPC_VERSION = '2.0'

    def self.make_id
      rand(10**12)
    end

    def initialize(url, opts = {}, namespace = nil)
      @url = url
      URI.parse(@url) # for the sake of validating the url
      @batch = []
      @opts = opts
      @namespace = namespace
      @opts[:content_type] = 'application/json'
    end

    def process_call(id, sym, args)
      resp = send_single_request(id, sym.to_s, args)

      begin
        data = MultiJson.decode(resp)
      rescue
        raise Client::Error::InvalidJSON.new(resp)
      end

      return process_single_response(data)

      rescue Exception, StandardError => e
        e = Client::Error::StandardError.exception(e) unless e.is_a?(Client::Error::StandardError)
        raise e
    end

    def send_single_request(id, method, args)
      namespaced_method = @namespace.nil? ? method : "#@namespace#{method}"
      post_data = MultiJson.encode({
        'jsonrpc' => JSON_RPC_VERSION,
        'method'  => namespaced_method,
        'params'  => args,
        'id'      => id
      })
      resp = RestClient.post(@url, post_data, @opts)
      if resp.nil? || resp.body.nil? || resp.body.empty?
        raise Client::Error::InvalidResponse.new
      end

      return resp.body
    end

    def send_batch_request(batch)
      post_data = MultiJson.encode(batch)
      resp = RestClient.post(@url, post_data, @opts)
      if resp.nil? || resp.body.nil? || resp.body.empty?
        raise Client::Error::InvalidResponse.new
      end

      return resp.body
    end

    def process_batch_response(responses)
      responses.each do |resp|
        saved_response = @batch.map { |r| r[1] }.select { |r| r.id == resp['id'] }.first
        raise Client::Error::InvalidResponse.new if saved_response.nil?
        saved_response.populate!(resp)
      end
    end

    def process_single_response(data)
      raise Client::Error::InvalidResponse.new if !valid_response?(data)

      response = Response.new(data['id'])
      response.populate!(data)
      return response
    end

    def valid_response?(data)
      return false if !data.is_a?(Hash)

      return false if data['jsonrpc'] != JSON_RPC_VERSION

      return false if !data.has_key?('id')

      return false if data.has_key?('error') && data.has_key?('result')

      if data.has_key?('error')
        if !data['error'].is_a?(Hash) || !data['error'].has_key?('code') || !data['error'].has_key?('message') 
          return false
        end

        if !data['error']['code'].is_a?(Fixnum) || !data['error']['message'].is_a?(String)
          return false
        end
      end

      return true
      
      rescue
        return false
    end

    def push_batch_request(request)
      request.id = self.class.make_id if request.id.blank?
      response = Response.new(request.id)
      @batch << [request, response]
      return response
    end

    def send_batch
      batch = @batch.map(&:first) # get the requests 
      response = send_batch_request(batch)

      begin
        responses = MultiJson.decode(response)
      rescue
        raise Client::Error::InvalidJSON.new(json)
      end

      process_batch_response(responses)
      @batch = []
    end
  end

  class BatchClient < BlankSlate
    reveal :instance_variable_get
    reveal :inspect
    reveal :to_s
    
    def initialize(url, opts = {}, namespace = nil)
      @url, @opts, @namespace = url, opts, namespace
      @helper = ClientHelper.new(url, opts, namespace)
    end

    def push_rpc(id, sym, args = nil)
      request = Jimson::Request.new(sym.to_s, args, id)
      @helper.push_batch_request(request) 
    end

    def execute_batch
      @helper.send_batch
    end
  end

  class Client < BlankSlate
    reveal :instance_variable_get
    reveal :inspect
    reveal :to_s

    def initialize(url, opts = {}, namespace = nil)
      @url, @opts, @namespace = url, opts, namespace
      @helper = ClientHelper.new(url, opts, namespace)
    end

    def execute_rpc(id, method, args = nil)
      @helper.process_call(id, method.to_sym, args)
    end
  end
end

require 'jimson/client/error'
