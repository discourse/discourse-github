module Jobs
  class CreateGithubLinkback < Jobs::Base
    def execute(args)
      return unless SiteSetting.github_linkback_enabled?


    end
  end
end
