# frozen_string_literal: true

module DiscourseGithubPlugin
  class CommitsPopulator
    MERGE_COMMIT_REGEX = /^Merge pull request/
    HISTORY_COMPLETE = "history-complete"

    ROLES = {
      committer: 0,
      contributor: 1
    }

    def initialize(repo)
      @repo = repo
      @client = Octokit::Client.new(access_token: SiteSetting.github_linkback_access_token, per_page: 100)
    end

    def populate!
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
        build_history!(start_at: commit.commit.committer.date)
      end
    rescue Octokit::Error => err
      Rails.logger.warn("#{err.class}: #{err.message}")
    end

    private

    def is_pr?(commit)
      commit.commit.author.name != commit.commit.committer.name && commit.commit.committer.name != "GitHub"
      # GitHub has a special account that acts as the committer of commits that are
      # created via the UI. For example when you merge your own PR (but not someone else's)
      # If this account is the committer of a commit then don't count it as a PR
    end

    def fetch_new_commits!(stop_at)
      batch = @client.commits(@repo.name)
      response = @client.last_response
      done = false
      commits = []
      while !done
        batch.each do |c|
          if c.sha == stop_at
            done = true
            break
          end
          commits << commit_to_hash(c)
        end
        break if done
        response = response.rels[:next]&.get
        batch = response&.data || []
        done = batch.size == 0
      end
      return if commits.size == 0
      existing_shas = @repo.commits.pluck(:sha)
      commits.reject! { |c| existing_shas.include?(c[:sha]) }
      batch_to_db(commits, simplified: true)
      set_front_commit(commits.first[:sha])
    end

    # detect if a force push happened and commit is lost
    def removed?(sha)
      commit = @client.commit(@repo.name, sha)
      found = @client.commits(@repo.name, until: commit.commit.committer.date, page: 1, per_page: 1).first
      commit.sha != found.sha
    end

    def build_history!(start_at: nil)
      params = start_at.present? ? { until: start_at } : {}
      batch = @client.commits(@repo.name, params)
      response = @client.last_response
      batch.shift if start_at.present?
      set_front_commit(batch.first.sha) if !start_at.present?

      while batch.size > 0
        batch_to_db(batch)
        set_back_commit(batch.last.sha)

        response = response.rels[:next]&.get
        batch = response&.data || []
      end
      set_back_commit(HISTORY_COMPLETE)
    end

    def batch_to_db(batch, simplified: false)
      fragments = []
      batch.each do |c|
        hash = simplified ? c : commit_to_hash(c)
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
        sha: commit.sha,
        email: commit.commit.author.email,
        repo_id: @repo.id,
        committed_at: commit.commit.committer.date,
        merge_commit: commit.commit.message.match?(MERGE_COMMIT_REGEX),
        role_id: is_pr?(commit) ? ROLES[:contributor] : ROLES[:committer]
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
  end
end
