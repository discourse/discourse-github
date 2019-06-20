# frozen_string_literal: true

# name: discourse-github
# about: Github Linkback, Github Badges, Github Permalinks
# version: 0.1
# authors: Robin Ward, Sam Saffron
# url: https://github.com/discourse/discourse-github

gem 'sawyer', '0.8.2'
gem 'octokit', '4.14.0'

after_initialize do
  [
    '../app/models/github_commit.rb',
    '../app/models/github_repo.rb',
    '../app/lib/github_linkback.rb',
    '../app/lib/github_badges.rb',
    '../app/lib/github_permalinks.rb',
    '../app/lib/commits_populator.rb',
    '../app/jobs/regular/create_github_linkback.rb',
    '../app/jobs/scheduled/grant_github_badges.rb',
    '../app/jobs/regular/replace_github_non_permalinks.rb'
  ].each { |path| require File.expand_path(path, __FILE__) }

  DiscourseEvent.on(:post_created) do |post|
    if SiteSetting.github_linkback_enabled?
      GithubLinkback.new(post).enqueue
    end
  end

  DiscourseEvent.on(:post_edited) do |post|
    if SiteSetting.github_linkback_enabled?
      GithubLinkback.new(post).enqueue
    end
  end

  DiscourseEvent.on(:before_post_process_cooked) do |doc, post|
    if SiteSetting.github_permalinks_enabled?
      GithubPermalinks.replace_github_non_permalinks(post)
    end
  end
end
