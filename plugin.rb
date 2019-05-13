# frozen_string_literal: true

# name: discourse-github
# about: Github Linkback, Github Badges, Github Permalinks
# version: 0.1
# authors: Robin Ward, Sam Saffron
# url: https://github.com/discourse/discourse-github

after_initialize do
  require_dependency File.expand_path('../app/lib/github_linkback.rb', __FILE__)
  require_dependency File.expand_path('../app/lib/github_badges.rb', __FILE__)
  require_dependency File.expand_path('../app/lib/github_permalinks.rb', __FILE__)
  require_dependency File.expand_path('../app/jobs/regular/create_github_linkback.rb', __FILE__)
  require_dependency File.expand_path('../app/jobs/scheduled/grant_github_badges.rb', __FILE__)
  require_dependency File.expand_path('../app/jobs/regular/replace_github_non_permalinks.rb', __FILE__)

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
