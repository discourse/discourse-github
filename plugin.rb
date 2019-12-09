# frozen_string_literal: true

# name: discourse-github
# about: Github Linkback, Github Badges, Github Permalinks
# version: 0.2
# authors: Robin Ward, Sam Saffron
# url: https://github.com/discourse/discourse-github

gem 'public_suffix', '4.0.1'
gem 'addressable', '2.7.0'
gem 'sawyer', '0.8.2'
gem 'octokit', '4.14.0'

enabled_site_setting :enable_discourse_github_plugin
enabled_site_setting_filter :github

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
    if SiteSetting.github_linkback_enabled? &&
      SiteSetting.enable_discourse_github_plugin?
      GithubLinkback.new(post).enqueue
    end
  end

  DiscourseEvent.on(:post_edited) do |post|
    if SiteSetting.github_linkback_enabled? &&
      SiteSetting.enable_discourse_github_plugin?
      GithubLinkback.new(post).enqueue
    end
  end

  DiscourseEvent.on(:before_post_process_cooked) do |doc, post|
    if SiteSetting.github_permalinks_enabled? &&
      SiteSetting.enable_discourse_github_plugin?
      GithubPermalinks.replace_github_non_permalinks(post)
    end
  end
end
