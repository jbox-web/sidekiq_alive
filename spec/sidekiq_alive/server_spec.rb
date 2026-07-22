# frozen_string_literal: true

require 'spec_helper'
require 'openssl'
require 'tempfile'

RSpec.describe(SidekiqAlive::Server) do
  include Rack::Test::Methods

  subject(:app) { described_class }

  describe '#run!' do
    subject(:app_run) { app.run! }

    before { allow(Rackup::Handler).to(receive(:get).with('webrick').and_return(fake_webrick)) }

    let(:fake_webrick) { double }

    it 'runs the handler with sidekiq_alive logger, host and no access logs' do
      expect(fake_webrick).to receive(:run).with(described_class, hash_including(Logger: SidekiqAlive.logger, Host: '0.0.0.0', AccessLog: []))

      app_run
    end

    context 'when we change the host config' do
      around do |example|
        ENV['SIDEKIQ_ALIVE_HOST'] = '1.2.3.4'
        SidekiqAlive.config.set_defaults

        example.run

        ENV['SIDEKIQ_ALIVE_HOST'] = nil
      end

      it 'respects the SIDEKIQ_ALIVE_HOST environment variable' do
        expect(fake_webrick).to receive(:run).with(described_class, hash_including(Host: '1.2.3.4'))
        app_run
      end
    end
  end

  describe 'responses' do
    it 'responds with success when the service is alive' do
      allow(SidekiqAlive).to(receive(:alive?).and_return(true))
      get '/'
      expect(last_response).to(be_ok)
      expect(last_response.body).to(eq('Alive!'))
    end

    it 'responds with a 503 error when the service is not alive' do
      allow(SidekiqAlive).to(receive(:alive?).and_return(false))
      get '/'
      expect(last_response).not_to(be_ok)
      expect(last_response.status).to(eq(503))
      expect(last_response.body).to(eq("Can't find the alive key"))
    end

    it 'responds not found on an unknown path' do
      get '/unknown-path'
      expect(last_response).not_to(be_ok)
      expect(last_response.body).to(eq('Not found'))
    end
  end

  describe 'SidekiqAlive setup host' do
    before do
      ENV['SIDEKIQ_ALIVE_HOST'] = '1.2.3.4'
      SidekiqAlive.config.set_defaults
    end

    after do
      ENV['SIDEKIQ_ALIVE_HOST'] = nil
    end

    it 'respects the SIDEKIQ_ALIVE_HOST environment variable' do
      expect(described_class.host).to(eq('1.2.3.4'))
    end
  end

  describe 'SidekiqAlive setup port' do
    before do
      ENV['SIDEKIQ_ALIVE_PORT'] = '4567'
      SidekiqAlive.config.set_defaults
    end

    after do
      ENV['SIDEKIQ_ALIVE_PORT'] = nil
    end

    it 'respects the SIDEKIQ_ALIVE_PORT environment variable' do
      expect(described_class.port).to(eq('4567'))
      expect(described_class.server).to(eq('webrick'))
    end
  end

  describe 'SidekiqAlive setup server' do
    before do
      ENV['SIDEKIQ_ALIVE_SERVER'] = 'puma'
      SidekiqAlive.config.set_defaults
    end

    after do
      ENV['SIDEKIQ_ALIVE_SERVER'] = nil
    end

    it 'respects the SIDEKIQ_ALIVE_PORT environment variable' do
      expect(described_class.server).to(eq('puma'))
    end
  end

  describe 'SidekiqAlive setup path' do
    before do
      ENV['SIDEKIQ_ALIVE_PATH'] = '/sidekiq-probe'
      SidekiqAlive.config.set_defaults
    end

    after do
      ENV['SIDEKIQ_ALIVE_PATH'] = nil
    end

    it 'respects the SIDEKIQ_ALIVE_PORT environment variable' do
      expect(described_class.path).to(eq('/sidekiq-probe'))
    end

    it 'responds ok to the given path' do
      allow(SidekiqAlive).to(receive(:alive?).and_return(true))
      get '/sidekiq-probe'
      expect(last_response).to(be_ok)
    end
  end

  describe 'TLS' do
    let(:tls_key) { OpenSSL::PKey::RSA.new(2048) }

    let(:tls_cert) do
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = 1
      cert.subject = OpenSSL::X509::Name.parse('/CN=sidekiq-alive-test')
      cert.issuer = cert.subject
      cert.public_key = tls_key.public_key
      cert.not_before = Time.now
      cert.not_after = Time.now + 3600
      cert.sign(tls_key, OpenSSL::Digest.new('SHA256'))
      cert
    end

    let(:cert_file) { Tempfile.new(['cert', '.pem']).tap { |f| f.write(tls_cert.to_pem) }.tap(&:close) }
    let(:key_file) { Tempfile.new(['key', '.pem']).tap { |f| f.write(tls_key.to_pem) }.tap(&:close) }

    after do
      cert_file.unlink
      key_file.unlink
    end

    describe '.tls_enabled?' do
      it 'is false when no cert/key is configured' do
        expect(described_class).not_to(be_tls_enabled)
      end

      it 'is true when both cert and key are configured' do
        SidekiqAlive.config.tls_cert_file = cert_file.path
        SidekiqAlive.config.tls_key_file = key_file.path
        expect(described_class).to(be_tls_enabled)
      end

      it 'is false when only one of cert/key is configured' do
        SidekiqAlive.config.tls_cert_file = cert_file.path
        expect(described_class).not_to(be_tls_enabled)
      end
    end

    describe '.tls_options' do
      before do
        SidekiqAlive.config.tls_cert_file = cert_file.path
        SidekiqAlive.config.tls_key_file = key_file.path
      end

      it 'builds the webrick SSL options from the cert/key files' do
        options = described_class.tls_options
        expect(options[:SSLEnable]).to(be(true))
        expect(options[:SSLCertificate]).to(be_a(OpenSSL::X509::Certificate))
        expect(options[:SSLPrivateKey]).to(be_a(OpenSSL::PKey::PKey))
      end

      it 'reads a non-RSA (EC) private key without assuming the key type' do
        ec_key_file = Tempfile.new(['ec_key', '.pem'])
        ec_key_file.write(OpenSSL::PKey::EC.generate('prime256v1').to_pem)
        ec_key_file.close
        SidekiqAlive.config.tls_key_file = ec_key_file.path

        expect(described_class.tls_options[:SSLPrivateKey]).to(be_a(OpenSSL::PKey::EC))
      ensure
        ec_key_file.unlink
      end

      it 'fails fast on an unsupported server instead of serving plaintext' do
        SidekiqAlive.config.server = 'puma'
        expect { described_class.tls_options }.to(raise_error(ArgumentError, /only supported with.*webrick/i))
      end
    end

    describe '.run! with TLS' do
      let(:fake_webrick) { double }

      before do
        allow(Rackup::Handler).to(receive(:get).with('webrick').and_return(fake_webrick))
        SidekiqAlive.config.tls_cert_file = cert_file.path
        SidekiqAlive.config.tls_key_file = key_file.path
      end

      it 'passes the SSL options to the handler' do
        expect(fake_webrick).to(receive(:run).with(described_class, hash_including(SSLEnable: true)))
        described_class.run!
      end
    end
  end
end
