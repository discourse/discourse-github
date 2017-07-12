module Jobs
  class CreateGithubLinkback < Jobs::Base
    def execute(args)
      return unless SiteSetting.github_linkback_enabled?
      GithubLinkback.new(Post.find(args[:post_id])).create
    end
  end
end
