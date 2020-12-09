# frozen_string_literal: true

module DiscourseGithubPlugin
  class CommitsPopulator
    MERGE_COMMIT_REGEX = /^Merge pull request/
    HISTORY_COMPLETE = "history-complete"
    class GraphQLError < StandardError; end

    ROLES = {
      committer: 0,
      contributor: 1
    }

    class PaginatedCommits
      def initialize(octokit, repo, cursor: nil, page_size: 100)
        @client = octokit
        @repo = repo
        @cursor = cursor
        @page_size = page_size
        raise ArgumentError, 'page_size arg must be <= 100' if page_size > 100
        if cursor && !cursor.match?(/^\h{40}\s(\d+)$/)
          raise ArgumentError, 'cursor must be a 40-characters hex string followed by a space and a number'
        end
        fetch_commits
      end

      def next
        info = @data.repository.defaultBranchRef.target.history.pageInfo
        return unless info.hasNextPage
        PaginatedCommits.new(@client, @repo, cursor: info.endCursor, page_size: @page_size)
      end

      def commits
        @data.repository.defaultBranchRef.target.history.nodes
      end

      private

      def fetch_commits
        owner, name = @repo.name.split('/', 2)
        history_args = "first: #{@page_size}"
        if @cursor
          history_args += ", after: #{@cursor.inspect}"
        end

        query = <<~QUERY
          query {
            repository(name: #{name.inspect}, owner: #{owner.inspect}) {
              defaultBranchRef {
                target {
                  ... on Commit {
                    history(#{history_args}) {
                      pageInfo {
                        endCursor
                        hasNextPage
                      }
                      nodes {
                        oid
                        message
                        committedDate
                        associatedPullRequests(first: 1) {
                          nodes {
                            author {
                              login
                            }
                            mergedBy {
                              login
                            }
                          }
                        }
                        author {
                          email
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        QUERY
        response = @client.post("/graphql", { query: query }.to_json)
        raise GraphQLError, response.errors.inspect if response.errors
        @data = response.data
      end
    end

    def initialize(repo)
      @repo = repo
      @client = Octokit::Client.new(access_token: SiteSetting.github_linkback_access_token, per_page: 100)
    end

    def populate!
      return unless SiteSetting.github_badges_enabled?
      return if @client.branches(@repo.name).empty?

      if @repo.commits.size == 0
        build_history!
      else
        front_sha = Discourse.redis.get(front_commit_redis_key)
        front_sha = @repo.commits.order("committed_at DESC").first.sha if !front_sha
        if removed?(front_sha)
          # there has been a force push, next run will rebuild history
          @repo.commits.delete_all
          Discourse.redis.del(back_commit_redis_key)
          Discourse.redis.del(front_commit_redis_key)
          return
        end
        fetch_new_commits!(front_sha)

        back_sha = Discourse.redis.get(back_commit_redis_key)
        return if back_sha == HISTORY_COMPLETE
        back_sha = @repo.commits.order("committed_at ASC").first.sha if !back_sha
        commit = @client.commit(@repo.name, back_sha)
        build_history!(after: commit.sha)
      end
    rescue Octokit::Error => err
      case err
      when Octokit::NotFound
        disable_github_badges_and_inform_admin(
          title: I18n.t("github_commits_populator.errors.repository_not_found_pm_title"),
          raw: I18n.t("github_commits_populator.errors.repository_not_found_pm",
                      repo_name: @repo.name,
                      base_path: Discourse.base_path),
        )
        Rails.logger.warn("Disabled github_badges_enabled site setting due to repository Not Found error ")
      when Octokit::Unauthorized
        disable_github_badges_and_inform_admin(
          title: I18n.t("github_commits_populator.errors.invalid_octokit_credentials_pm_title"),
          raw: I18n.t("github_commits_populator.errors.invalid_octokit_credentials_pm",
                      base_path: Discourse.base_path),
        )
        Rails.logger.warn("Disabled github_badges_enabled site setting due to invalid GitHub authentication credentials via github_linkback_access_token.")
      else
        Rails.logger.warn("#{err.class}: #{err.message}")
      end
    rescue Octokit::InvalidRepository => err
      disable_github_badges_and_inform_admin(
        title: I18n.t("github_commits_populator.errors.repository_identifier_invalid_pm_title"),
        raw: I18n.t("github_commits_populator.errors.repository_identifier_invalid_pm",
                    repo_name: @repo.name,
                    base_path: Discourse.base_path),
      )
      Rails.logger.warn("Disabled github_badges_enabled site setting due to invalid repository identifier")
    end

    private

    def is_contribution?(commit)
      pr = commit.associatedPullRequests.nodes.first
      pr && pr.author && pr.mergedBy && pr.author.login != pr.mergedBy.login
    end

    def fetch_new_commits!(stop_at)
      paginator = PaginatedCommits.new(@client, @repo, page_size: 10)
      batch = paginator.commits
      done = false
      commits = []
      while !done
        batch.each do |c|
          if c.oid == stop_at
            done = true
            break
          end
          commits << c
        end
        break if done
        paginator = paginator.next
        batch = paginator&.commits || []
        break if batch.empty?
      end
      return if commits.size == 0
      existing_shas = @repo.commits.pluck(:sha)
      commits.reject! { |c| existing_shas.include?(c.oid) }
      batch_to_db(commits)
      set_front_commit(commits.first.oid)
    end

    # detect if a force push happened and commit is lost
    def removed?(sha)
      commit = @client.commit(@repo.name, sha)
      found = @client.commits(@repo.name, until: commit.commit.committer.date, page: 1, per_page: 1).first
      commit.sha != found.sha
    end

    def build_history!(after: nil)
      cursor = "#{after} 0" if after.present?
      paginator = PaginatedCommits.new(@client, @repo, cursor: cursor, page_size: 70)
      batch = paginator.commits
      return if batch.empty?
      set_front_commit(batch.first.oid) if after.blank?

      while batch.size > 0
        batch_to_db(batch)
        set_back_commit(batch.last.oid)

        paginator = paginator.next
        batch = paginator&.commits || []
      end
      set_back_commit(HISTORY_COMPLETE)
    end

    def batch_to_db(batch)
      fragments = []
      batch.each do |c|
        hash = commit_to_hash(c)
        fragments << DB.sql_fragment(<<~SQL, hash)
          (:repo_id, :sha, :email, :committed_at, :role_id, :merge_commit, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
      end
      DB.exec(<<~SQL)
        INSERT INTO github_commits
        (repo_id, sha, email, committed_at, role_id, merge_commit, created_at, updated_at) VALUES #{fragments.join(',')}
      SQL
    end

    def commit_to_hash(commit)
      {
        sha: commit.oid,
        email: commit.author.email,
        repo_id: @repo.id,
        committed_at: commit.committedDate,
        merge_commit: commit.message.match?(MERGE_COMMIT_REGEX),
        role_id: is_contribution?(commit) ? ROLES[:contributor] : ROLES[:committer]
      }
    end

    def set_front_commit(sha)
      Discourse.redis.set(front_commit_redis_key, sha)
    end

    def set_back_commit(sha)
      Discourse.redis.set(back_commit_redis_key, sha)
    end

    def front_commit_redis_key
      # this key should refer to the MOST RECENT commit we have in the db
      "discourse-github-front-commit-#{@repo.name}"
    end

    def back_commit_redis_key
      # this key should refer to the OLDEST commit we have in the db
      "discourse-github-back-commit-#{@repo.name}"
    end

    def disable_github_badges_and_inform_admin(title:, raw:)
      SiteSetting.github_badges_enabled = false
      site_admin_usernames = User.where(admin: true).human_users.order('last_seen_at DESC').limit(10).pluck(:username)
      PostCreator.create!(
        Discourse.system_user,
        title: title,
        raw: raw,
        archetype: Archetype.private_message,
        target_usernames: site_admin_usernames,
        skip_validations: true
      )
    end
  end
end
