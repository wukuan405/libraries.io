require 'rails_helper'

describe MaintenanceStats::Contributors do
  let!(:auth_token) { create(:auth_token) }
  let(:client) { AuthToken.client }
  let(:query_klass) { MaintenanceStats::RepositoryContributorsQuery.new(client) }
  let(:query_params) { {full_name: repository.full_name} }

  let(:stat) { described_class.new(query_results) }

  context "with a valid repository" do
    let(:repository) { create(:repository) }
    let(:query_results) do
        VCR.use_cassette('github/rails_api', :match_requests_on => [:body]) do
           return query_klass.query(params: query_params)
        end
    end

    it "should have repository contributor stats" do
        results = stat.get_stats

        expected_keys = %W(total_contributors).map(&:to_sym)

        expect(results.keys).to eql expected_keys
        
        # check values against the VCR cassette data
        expect(results[:total_contributors]).to eql 380
    end
  end
  
  context "repository with no commits" do
    let(:repository) { create(:repository, full_name: 'buddhamagnet/heidigoodchild') }
    let(:query_results) do
        VCR.use_cassette('github/empty_repository', :match_requests_on => [:body]) do
           return query_klass.query(params: query_params)
        end
    end

    it "should handle no data from query" do
        results = stat.get_stats

        expected_keys = %W(total_contributors).map(&:to_sym)

        expect(results.keys).to eql expected_keys

        # check values against the VCR cassette data
        expect(results[:total_contributors]).to eql nil
    end
  end
end