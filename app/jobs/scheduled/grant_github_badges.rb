# frozen_string_literal: true

module DiscourseGithubPlugin
  class UpdateJob < ::Jobs::Scheduled
    every 4.hours

    def execute(args)
      return unless SiteSetting.enable_discourse_github_plugin?
      return unless SiteSetting.github_badges_enabled?
      return unless SiteSetting.discourse_github_api_token.present?

      GithubRepo.repos.each do |repo|
        CommitsPopulator.new(repo).populate!
      end
      GithubBadges.grant!
    end
  end
end
