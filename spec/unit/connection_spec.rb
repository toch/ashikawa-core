# -*- encoding : utf-8 -*-
require 'unit/spec_helper'
require 'ashikawa-core/connection'

describe Ashikawa::Core::Connection do
  let(:request_stub) { Faraday::Adapter::Test::Stubs.new }
  let(:response_headers) { { 'content-type' => 'application/json; charset=utf-8' } }
  let(:options) { instance_double('Hash') }
  subject { Ashikawa::Core::Connection.new(ARANGO_HOST, '_system', adapter: [:test, request_stub]) }

  its(:scheme) { should eq('http') }
  its(:host) { should eq('localhost') }
  its(:port) { should eq(8529) }

  describe 'initialization' do
    it 'should create the Faraday connection using FaradayFactory' do
      options = double('Options')
      expect(Ashikawa::Core::FaradayFactory).to receive(:create_connection)
        .with('http://localhost:8529/_db/my_db/_api', options)
      Ashikawa::Core::Connection.new('http://localhost:8529', 'my_db', options)
    end
  end

  it 'should include include the x-arango-version header in each request' do
    [:get, :post, :put, :delete].each do |http_verb|
      request_stub.send(http_verb, '/_db/_system/_api/my/path') do |request|
        expect(request[:request_headers][:'X-Arango-Version']).to eq '20200'
        [200, response_headers, JSON.generate({ 'name' => 'dude' })]
      end

      subject.send_request 'my/path', http_verb => {}

      request_stub.verify_stubbed_calls
    end
  end

  it 'should send a get request' do
    request_stub.get('/_db/_system/_api/my/path') do
      [200, response_headers, JSON.generate({ 'name' => 'dude' })]
    end

    subject.send_request 'my/path'

    request_stub.verify_stubbed_calls
  end

  it 'should send a post request' do
    request_stub.post('/_db/_system/_api/my/path') do |request|
      expect(request[:body]).to eq("{\"name\":\"new_collection\"}")
      [200, response_headers, JSON.generate({ 'name' => 'dude' })]
    end

    subject.send_request 'my/path', post: { name: 'new_collection' }
    request_stub.verify_stubbed_calls
  end

  it 'should send a put request' do
    request_stub.put('/_db/_system/_api/my/path') do |request|
      expect(request[:body]).to eq('{"name":"new_collection"}')
      [200, response_headers, JSON.generate({ 'name' => 'dude' })]
    end

    subject.send_request 'my/path', put: { name: 'new_collection' }
    request_stub.verify_stubbed_calls
  end

  it 'should send a delete request' do
    request_stub.delete('/_db/_system/_api/my/path') do |_|
      [200, response_headers, JSON.generate({ 'name' => 'dude' })]
    end

    subject.send_request 'my/path', delete: {}
    request_stub.verify_stubbed_calls
  end

  context 'with database suffix' do
    let(:database_name) { 'ashikawa' }
    subject do
      Ashikawa::Core::Connection.new(ARANGO_HOST, database_name, adapter: [:test, request_stub])
    end

    its(:database_name) { should eq database_name }

    it 'should be able to send a request without database suffix' do
      expect(subject).to receive(:send_request)
        .with("#{ARANGO_HOST}/_api/some_endpoint", options)

      subject.send_request_without_database_suffix('some_endpoint', options)
    end
  end

  context 'without database suffix' do
    subject do
      Ashikawa::Core::Connection.new(ARANGO_HOST, '_system', adapter: [:test, request_stub])
    end

    its(:database_name) { should eq '_system' }
    it 'should be able to send a request without database suffix' do
      expect(subject).to receive(:send_request)
        .with("#{ARANGO_HOST}/_api/some_endpoint", options)

      subject.send_request_without_database_suffix('some_endpoint', options)
    end
  end

  describe 'authentication' do
    it 'should have authentication turned off by default' do
      expect(subject.authentication?).to be_falsey
    end

    it 'should tell if authentication is enabled' do
      subject.authenticate_with('testuser', 'testpassword')
      expect(subject.authentication?).to be_truthy
    end

    it 'should send the authentication data with every GET request' do
      skip 'Find out how to check for basic auth via Faraday Stubs'

      request_stub.get('/_db/_system/_api/my/path') do |_|
        [200, response_headers, JSON.generate({ 'name' => 'dude' })]
      end

      subject.authenticate_with username: 'user', password: 'pass'
      subject.send_request 'my/path'

      request_stub.verify_stubbed_calls
    end
  end

  describe 'exception handling' do
    let(:error_message) { 'cannot write file' }
    let(:error_num) { 15 }

    it "should throw a general client error for I'm a teapot" do

      request_stub.get('/_db/_system/_api/bad/request') do
        [
          418,
          response_headers,
          JSON.generate({ 'error' => true, 'errorNum' => error_num, 'errorMessage' => error_message })
        ]
      end

      expect do
        subject.send_request('bad/request')
      end.to raise_error(Ashikawa::Core::ClientError, "#{error_num}: #{error_message}")

      request_stub.verify_stubbed_calls
    end

    it 'should throw its own exception when doing a bad request' do
      request_stub.get('/_db/_system/_api/bad/request') do
        [400, response_headers, '{}']
      end

      expect do
        subject.send_request('bad/request')
      end.to raise_error(Ashikawa::Core::BadSyntax)

      request_stub.verify_stubbed_calls
    end

    it 'should throw its own exception when doing a bad request' do
      request_stub.get('/_db/_system/_api/secret') do
        [401, response_headers, '']
      end

      expect do
        subject.send_request('secret')
      end.to raise_error(Ashikawa::Core::AuthenticationFailed)

      request_stub.verify_stubbed_calls
    end

    it 'should throw a general server error for the generic server error' do
      request_stub.get('/_db/_system/_api/bad/request') do
        [
          500,
          response_headers,
          JSON.generate({ 'error' => true, 'errorNum' => error_num, 'errorMessage' => error_message })
        ]
      end

      expect do
        subject.send_request('bad/request')
      end.to raise_error(Ashikawa::Core::ServerError, "#{error_num}: #{error_message}")

      request_stub.verify_stubbed_calls
    end

    it 'should raise an exception if a document is not found' do
      request_stub.get('/_db/_system/_api/document/4590/333') do
        [404, response_headers, '']
      end

      expect { subject.send_request 'document/4590/333' }.to raise_error(Ashikawa::Core::DocumentNotFoundException)

      request_stub.verify_stubbed_calls
    end

    it 'should raise an exception if a collection is not found' do
      request_stub.get('/_db/_system/_api/collection/4590') do
        [404, response_headers, '']
      end

      expect { subject.send_request 'collection/4590' }.to raise_error(Ashikawa::Core::CollectionNotFoundException)

      request_stub.verify_stubbed_calls
    end

    it 'should raise an exception if an index is not found' do
      request_stub.get('/_db/_system/_api/index/4590/333') do
        [404, response_headers, '']
      end

      expect { subject.send_request 'index/4590/333' }.to raise_error(Ashikawa::Core::IndexNotFoundException)

      request_stub.verify_stubbed_calls
    end

    context 'handle 404 in the gharial module' do
      let(:request_url) { '/_db/_system/_api/gharial/vertex/42' }

      it 'should raise GraphNotFoundException if the graph could not be found' do
        request_stub.get(request_url) do
          [404, response_headers, { 'errorMessage' => 'graph not found' }]
        end

        expect { subject.send_request 'gharial/vertex/42' }.to raise_error(Ashikawa::Core::GraphNotFoundException)

        request_stub.verify_stubbed_calls
      end

      it 'should raise CollectionNotFoundException the collection could not be found' do
        request_stub.get(request_url) do
          [404, response_headers, { 'errorMessage' => 'collection not found' }]
        end

        expect { subject.send_request 'gharial/vertex/42' }.to raise_error(Ashikawa::Core::CollectionNotFoundException)

        request_stub.verify_stubbed_calls
      end

      it 'should raise DocumentNotFoundException the document could not be found' do
        request_stub.get(request_url) do
          [404, response_headers, { 'errorMessage' => 'document not found' }]
        end

        expect { subject.send_request 'gharial/vertex/42' }.to raise_error(Ashikawa::Core::DocumentNotFoundException)

        request_stub.verify_stubbed_calls
      end
    end

    it 'should raise an exception for unknown pathes' do
      request_stub.get('/_db/_system/_api/unknown_path/4590/333') do
        [404, response_headers, '']
      end

      expect { subject.send_request 'unknown_path/4590/333' }.to raise_error(Ashikawa::Core::ResourceNotFound)

      request_stub.verify_stubbed_calls
    end

    it 'should raise an error if a malformed JSON was returned from the server' do
      request_stub.get('/_db/_system/_api/document/4590/333') do
        [200, response_headers, '{"a":1']
      end

      expect { subject.send_request 'document/4590/333' }.to raise_error(Ashikawa::Core::JsonError)

      request_stub.verify_stubbed_calls
    end
  end
end
