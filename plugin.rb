# name: discourse-github-linkback
# about: Links Github content back to a Discourse discussion
# version: 0.1
# authors: Robin Ward

enabled_site_setting :github_linkback_enabled

after_initialize do
  require_dependency File.expand_path('../app/jobs/regular/create_github_linkback.rb', __FILE__)

  DiscourseEvent.on(:post_created) do |post|
    if SiteSetting.github_linkback_enabled?
      Jobs.enqueue(:create_github_linkback, post_id: post.id)
    end
  end
end

