# frozen_string_literal: true

require 'uri'
require 'json'
require 'net/http'

module Eufycam
  class Client
    attr_accessor :email, :password, :auth_token, :auth_message, :verify_code, :token_expires_at

    def initialize(email:, password:, auth_token:nil, verify_code:nil)
      @email = email
      @password = password
      @auth_token = auth_token
      @verify_code = verify_code
    end

    def post(path, body = nil)
      uri = URI("https://mysecurity.eufylife.com/api/v1/#{path}")

      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        if block_given?
          yield http.request(request(path, body))
        else
          http.request(request(path, body))
        end
      end
    end

    def request(path, body = nil)
      uri = URI("https://mysecurity.eufylife.com/api/v1/#{path}")

      Net::HTTP::Post.new(uri).tap do |post|
        post.body = body.to_json
        post['x-auth-token'] = auth_token unless auth_token.nil?
      end
    end

    def generate_auth_token
      body = { email: @email, password: @password }
      body[:verify_code] = @verify_code if verify_code

      post('passport/login', body) do |response|
        resp = JSON.parse(response.body)
        if resp.dig('code') == 26006
          @auth_message = resp['msg']
          @auth_token = nil
          @verify_code = nil
        else
          @auth_token = resp['data']['auth_token']
          @token_expires_at = resp['data']['token_expires_at']
          @auth_message = nil
          @verify_code = nil
          if resp.dig('msg') == "need validate code"
            send_verify_code
            @auth_message = "Verification code sent to the #{email}. Please login again with the verification code."
          end
        end
      end
    end

    def send_verify_code
      post('/sms/send/verify_code', {"message_type":2}) {|f|}
    end

    def list_devices
      @auth_token ||= generate_auth_token
      return false if auth_token.nil?

      post('app/get_devs_list') do |response|
        JSON.parse(response.body)['data']
      end
    end

    def get_device(device_name:)
      @auth_token ||= generate_auth_token
      return false if auth_token.nil?

      list_devices
             .detect { |d| d['device_name'] == device_name }
             .slice('station_sn', 'device_sn')
    end

    def start_stream(device_name:)
      @auth_token ||= generate_auth_token
      return false if auth_token.nil?

      device = get_device(device_name: device_name)
      return "Failed to find #{device_name}" if device.blank

      post('web/equipment/start_stream', device) do |response|
        JSON.parse(response.body)['data']
      end
    end

    def capture_image(url, filename)
      system('ffmpeg', '-hide_banner', '-loglevel', 'panic', '-i', url.to_s, '-r', '5', filename.to_s)
    end

    def get_event_history(device_name:)
      @auth_token ||= generate_auth_token
      return false if auth_token.nil?

      device = get_device(device_name: device_name)
      return "Failed to find #{device_name}" if device.blank

      body = device.slice('device_sn')
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
