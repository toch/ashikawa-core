# -*- encoding : utf-8 -*-
require 'unit/spec_helper'
require 'ashikawa-core/document'
require 'ashikawa-core/database'

describe Ashikawa::Core::Document do
  let(:database) { instance_double('Ashikawa::Core::Database') }
  let(:id) { '23914039/25880119' }
  let(:path) { 'document/23914039/25880119' }
  let(:key) { '25880119' }
  let(:revision) { '13728680' }
  let(:first_name) { 'Jeff' }
  let(:last_name) { 'Lebowski' }
  let(:more_info) { 'This is valuable information' }
  let(:delete_payload) { { delete: {} } }
  let(:raw_data) do
    {
      '_id' => id,
      '_key' => key,
      '_rev' => revision,
      'first_name' => first_name,
      'last_name' => last_name
    }
  end
  let(:raw_data_without_id) do
    {
      'first_name' => first_name,
      'last_name' => last_name
    }
  end

  describe 'initializing' do
    subject { Ashikawa::Core::Document }

    let(:additional_data) do
      {
        more_info: more_info
      }
    end

    it 'should initialize with data including ID' do
      document = subject.new(database, raw_data)
      expect(document.id).to eq(id)
      expect(document.key).to eq(key)
      expect(document.revision).to eq(revision)
    end

    it 'should initialize with data not including ID' do
      document = subject.new(database, raw_data_without_id)
      expect(document.id).to eq(:not_persisted)
      expect(document.revision).to eq(:not_persisted)
    end

    it 'should initialize with additional data' do
      document = subject.new(database, raw_data, additional_data)
      expect(document['more_info']).to eq(more_info)
    end
  end

  describe 'initialized with a garaph' do
    let(:graph) { double('Ashikawa::Core::Graph', name: 'my-graph') }
    let(:additional_data_with_graph) { { graph: graph, more_info: more_info } }
    subject { Ashikawa::Core::Document.new(database, raw_data, additional_data_with_graph) }

    its(['more_info']) { should eq(more_info) }
    its(:graph) { should eq(graph) }

    it 'should send requests through the graph module' do
      expect(database).to receive(:send_request)
        .with("gharial/my-graph/vertex/#{id}", {})

      subject.send(:send_request_for_document, {})
    end
  end

  describe 'initialized document with ID' do
    subject { Ashikawa::Core::Document.new(database, raw_data) }

    let(:new_last_name) { 'Dudemeister' }
    let(:raw_data_without_id_and_new_last_name) do
      {
        'first_name' => first_name,
        'last_name' => new_last_name
      }
    end

    its(['first_name']) { should be(first_name) }
    its(['no_name']) { should be_nil }
    its(:to_h) { should be_instance_of Hash }
    its(:to_h) { should include('first_name' => first_name) }

    it 'should be deletable' do
      expect(database).to receive(:send_request).with(path, delete_payload)
      subject.delete
    end

    it 'should store changes to the database' do
      expect(database).to receive(:send_request).with(path,
                                                      { put: raw_data_without_id_and_new_last_name }
      )

      subject['last_name'] = new_last_name
      subject.save
    end

    it 'should be refreshable' do
      expect(database).to receive(:send_request)
        .with(path, {})
        .and_return({ 'name' => 'Jeff' })

      refreshed_subject = subject.refresh
      expect(refreshed_subject).to eq(subject)
      expect(subject['name']).to eq('Jeff')
    end
  end

  describe 'initialized document without ID' do
    subject { Ashikawa::Core::Document.new database, raw_data_without_id }

    its(['first_name']) { should be(first_name) }
    its(['no_name']) { should be_nil }

    it 'should not be deletable' do
      expect(database).not_to receive :send_request
      expect { subject.delete }.to raise_error Ashikawa::Core::DocumentNotFoundException
    end

    it 'should not store changes to the database' do
      expect(database).not_to receive :send_request
      expect { subject.save }.to raise_error Ashikawa::Core::DocumentNotFoundException
    end
  end
end
