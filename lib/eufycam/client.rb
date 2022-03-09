# frozen_string_literal: true

require 'uri'
require 'json'
require 'net/http'

module Eufycam
  class Client
    attr_accessor :email, :password, :auth_token, :auth_message, :verify_code

    def initialize(email:, password:, verify_code:)
      @email = email
      @password = password
      @verify_code = verify_code
    end

    def post(path, body = nil)
      uri = URI("https://mysecurity.eufylife.com/api/v1/#{path}")

      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        yield http.request(request(path, body))
      end
    end

    def request(path, body = nil)
      uri = URI("https://mysecurity.eufylife.com/api/v1/#{path}")

      Net::HTTP::Post.new(uri).tap do |post|
        post.body = body.to_json
        p auth_token
        post['x-auth-token'] = auth_token unless auth_token.nil?
      end
    end

    def generate_auth_token
      body = { email: @email, password: @password }
      body[:verify_code] = @verify_code if verify_code

      post('passport/login', body) do |response|
        p JSON.parse(response.body)
        if JSON.parse(response.body).dig('code') == 26006
          @auth_message = JSON.parse(response.body)['msg']
          @auth_token = nil
        else
          @auth_token = JSON.parse(response.body)['data']['auth_token']
          @auth_message = nil
          if JSON.parse(response.body).dig('msg') == "need validate code"
            verify_code
            @auth_message = 'Verification code sent to the account email address. Please login again with the verification code.'
          end
        end
      end
    end

    def verify_code
      post('/sms/send/verify_code', {"message_type":2}) do |response|
        p JSON.parse(response.body)
      end
    end

    def list_devices(auth_token = generate_auth_token)
      return auth_message if auth_token.nil?

      post('app/get_devs_list') do |response|
        p JSON.parse(response.body)
        JSON.parse(response.body)['data']
      end
    end

    def get_device(device_name:)
      @auth_token ||= generate_auth_token
      return auth_message if auth_token.nil?

      list_devices(auth_token)
             .detect { |d| d['device_name'] == device_name }
             .slice('station_sn', 'device_sn')
    end

    def start_stream(device_name:)
      @auth_token ||= generate_auth_token
      return auth_message if auth_token.nil?

      post(
        'web/equipment/start_stream',
        get_device(device_name).slice('device_sn')
      ) do |response|
        JSON.parse(response.body)['data']
      end
    end

    def capture_image(url, filename)
      system('ffmpeg', '-hide_banner', '-loglevel', 'panic', '-i', url.to_s, '-r', '5', filename.to_s)
    end

    def get_event_history(device_name:)
      @auth_token ||= generate_auth_token
      return auth_message if auth_token.nil?

      body = get_device(device_name)
      post("event/app/get_all_history_record", body) do |response|
        JSON.parse(response.body)['data']
      end
    end


    def timelapse(device_name, directory)
      url = start_stream(device_name)

      loop do
        capture_image(url, File.expand_path("#{directory}/#{Time.now.to_i}.png"))
        print '.'
        sleep(1)
      end
    end
  end
end
