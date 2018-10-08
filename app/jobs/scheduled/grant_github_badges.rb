module ::GithubBadges
  class UpdateJob < ::Jobs::Scheduled
    every 1.day

    def execute(args)
      return unless SiteSetting.github_badges_enabled?
      GithubBadges.badge_grant!
    end
  end
end
