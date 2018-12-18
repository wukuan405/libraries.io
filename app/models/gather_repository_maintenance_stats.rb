class GatherRepositoryMaintenanceStats
    def self.gather_stats(repository)
        return unless repository.host_type == "GitHub" # only support Github repos for now
        client = AuthToken.v4_client
        v3_client = AuthToken.client
        stats_to_run = get_stats_to_run(repository)

        clients = {
            v3: v3_client,
            v4: client
        }

        metrics = []

        stats_to_run.each do |stat_run|
            query_to_run = stat_run[:query].new(clients[stat_run[:query].client_type])
            begin
                result = query_to_run.query(params: stat_run[:variables])
                unless check_for_error_response(result, stat_run[:query].client_type)
                    stat_run[:stat_class].each do |stat_class|
                        metrics << stat_class.new(result).get_stats
                    end
                end
            rescue Octokit::Error => e
                Rails.logger.warn(e.message)
                next
            end
        end

        add_metrics_to_repo(repository, metrics)

        metrics
    end

    private

    def self.check_for_error_response(response, client_version)
        if client_version == :v4
            # errors can be stored in the response from Github or can be stored in the response object from HTTP errors
            response.errors.each do |message|
                Rails.logger.warn(message)
            end
            response.data.errors.each do |message|
                Rails.logger.warn(message)
            end unless response.data.errors.nil?
            # if we have either type of error or there is no data return true
            return response.data.nil? || response.errors.any? || response.data.errors.any?
        end
        false
    end

    def self.add_metrics_to_repo(repository, results)
        # create one hash with all results
        results.reduce(Hash.new, :merge).each do |category, value|
            unless value.nil?
                stat = repository.repository_maintenance_stats.find_or_create_by(category: category.to_s)
                stat.update!(value: value.to_s)
                stat.touch unless stat.changed?  # we always want to update updated_at for later querying
            end
        end
    end

    def self.get_stats_to_run(repository)
        now = DateTime.current
        [{
            query: MaintenanceStats::Queries::FullRepoQuery,
            variables: {owner: repository.owner_name, repo_name: repository.project_name},
            stat_class: [MaintenanceStats::Stats::IssueRates, MaintenanceStats::Stats::PullRequestRates, MaintenanceStats::Stats::AverageCommitDate]
        },
        {
            query: MaintenanceStats::Queries::RepositoryContributorsQuery,
            variables: {full_name: repository.full_name},
            stat_class: [MaintenanceStats::Stats::Contributors]
        },
        {
            query: MaintenanceStats::Queries::RepoReleasesQuery,
            variables: {owner: repository.owner_name, repo_name: repository.project_name, end_date: now - 365},
            stat_class: [MaintenanceStats::Stats::ReleaseStats]
        },
        {
            query: MaintenanceStats::Queries::CommitCountQuery,
            variables: {owner: repository.owner_name, repo_name: repository.project_name, start_date: (now - 7).iso8601},
            stat_class: [MaintenanceStats::Stats::LastWeekCommitsStat]
        },
        {
            query: MaintenanceStats::Queries::CommitCountQuery,
            variables: {owner: repository.owner_name, repo_name: repository.project_name, start_date: (now - 30).iso8601},
            stat_class: [MaintenanceStats::Stats::LastMonthCommitsStat]
        },
        {
            query: MaintenanceStats::Queries::CommitCountQuery,
            variables: {owner: repository.owner_name, repo_name: repository.project_name, start_date: (now - 60).iso8601},
            stat_class: [MaintenanceStats::Stats::LastTwoMonthCommitsStat]
        },
        {
            query: MaintenanceStats::Queries::CommitCountQuery,
            variables: {owner: repository.owner_name, repo_name: repository.project_name, start_date: (now - 365).iso8601},
            stat_class: [MaintenanceStats::Stats::LastYearCommitsStat]
        },
        {
            query: MaintenanceStats::Queries::CommitCountQueryV3,
            variables: {full_name: repository.full_name},
            stat_class: [MaintenanceStats::Stats::V3CommitsStat]
        }
    ]
    end
end