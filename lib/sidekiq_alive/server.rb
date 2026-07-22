# frozen_string_literal: true

module SidekiqAlive
  class Server
    class << self
      def run!
        handler = Rackup::Handler.get(server)

        Signal.trap('TERM') { handler.shutdown }

        options = { Port: port, Host: host, AccessLog: [], Logger: SidekiqAlive.logger }
        options.merge!(tls_options) if tls_enabled?

        handler.run(self, options)
      end

      def host
        SidekiqAlive.config.host
      end

      def port
        SidekiqAlive.config.port
      end

      def path
        SidekiqAlive.config.path
      end

      def server
        SidekiqAlive.config.server
      end

      def tls_enabled?
        tls_cert_file && tls_key_file
      end

      def tls_cert_file
        SidekiqAlive.config.tls_cert_file
      end

      def tls_key_file
        SidekiqAlive.config.tls_key_file
      end

      def tls_options
        ensure_tls_supported!

        require 'webrick/https'
        require 'openssl'

        {
          SSLEnable: true,
          SSLCertificate: OpenSSL::X509::Certificate.new(File.read(tls_cert_file)),
          # PKey.read auto-detects the key type (RSA, EC, Ed25519, ...) instead
          # of assuming RSA, which would raise on any other key.
          SSLPrivateKey: OpenSSL::PKey.read(File.read(tls_key_file)),
        }
      end

      # Fail fast: only webrick can terminate TLS here. Silently returning {}
      # would start the probe in plaintext despite cert/key being configured.
      def ensure_tls_supported!
        return if server == 'webrick'

        raise(ArgumentError,
              "SidekiqAlive: TLS is only supported with the 'webrick' server (got #{server.inspect}); " \
              'remove tls_cert_file/tls_key_file or set config.server = \'webrick\'.')
      end

      def call(env)
        if Rack::Request.new(env).path != path
          [404, {}, ['Not found']]
        elsif SidekiqAlive.alive?
          [200, {}, ['Alive!']]
        else
          response = "Can't find the alive key"
          SidekiqAlive.logger.error(response)
          [503, {}, [response]]
        end
      end
    end
  end
end
