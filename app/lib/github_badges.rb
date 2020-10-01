# frozen_string_literal: true

module DiscourseGithubPlugin
  module GithubBadges
    BADGE_NAME_BRONZE ||= 'Contributor'
    BADGE_NAME_SILVER ||= 'Great contributor'
    BADGE_NAME_GOLD   ||= 'Amazing contributor'

    COMMITER_BADGE_NAME_BRONZE ||= 'Committer'
    COMMITER_BADGE_NAME_SILVER ||= 'Frequent committer'
    COMMITER_BADGE_NAME_GOLD   ||= 'Amazing committer'

    class Granter
      def initialize(emails)
        @emails = emails
        @badges = []
      end

      def add_badge(badge, as_title:, threshold:)
        @badges << [badge, as_title, threshold]
      end

      def grant!
        email_commits = @emails.group_by { |e| e }.map { |k, l| [k, l.count] }.to_h

        regular_emails = []
        github_name_email = {}
        @emails.each do |email|
          match = email.match(/\A(\d+\+)?(?<name>.+)@users.noreply.github.com\Z/)

          if match
            name = match[:name]
            github_name_email[name] = email
          else
            regular_emails << email
          end
        end

        user_emails = {}
        User.real.where(staged: false).with_email(regular_emails).each do |user|
          user_emails[user] = user.emails
        end

        if github_name_email.any?
          infos = GithubUserInfo.where(screen_name: github_name_email.keys).includes(:user)

          infos.each do |info|
            user_emails[info.user] ||= []
            user_emails[info.user] << github_name_email[info.screen_name]
          end
        end

        user_emails.each do |user, emails|
          commits_count = emails.sum { |email| email_commits[email] || 0 }
          @badges.each do |badge, as_title, threshold|
            if commits_count >= threshold && badge.enabled? && SiteSetting.enable_badges
              BadgeGranter.grant(badge, user)
              if user.title.blank? && as_title
                user.update!(title: badge.name)
              end
            end
          end
        end
      end
    end

    def self.grant!
      grant_committer_badges!
      grant_contributor_badges!
    end

    def self.grant_committer_badges!
      emails = GithubCommit.where(
        merge_commit: false,
        role_id: CommitsPopulator::ROLES[:committer]
      ).pluck(:email)

      bronze, silver, gold = committer_badges

      granter = GithubBadges::Granter.new(emails)
      granter.add_badge(bronze, as_title: false, threshold: 1)
      granter.add_badge(silver, as_title: true, threshold: 25)
      granter.add_badge(gold, as_title: true, threshold: 1000)
      granter.grant!
    end

    def self.grant_contributor_badges!
      emails = GithubCommit.where(
        merge_commit: false,
        role_id: CommitsPopulator::ROLES[:contributor]
      ).pluck(:email)

      bronze, silver, gold = contributor_badges

      granter = GithubBadges::Granter.new(emails)
      granter.add_badge(bronze, as_title: false, threshold: 1)
      granter.add_badge(silver, as_title: true, threshold: SiteSetting.github_silver_badge_min_commits)
      granter.add_badge(gold, as_title: true, threshold: SiteSetting.github_gold_badge_min_commits)
      granter.grant!
    end

    def self.contributor_badges
      unless bronze = Badge.find_by(name: BADGE_NAME_BRONZE)
        bronze = Badge.create!(name: BADGE_NAME_BRONZE,
                               description: 'contributed an accepted pull request',
                               badge_type_id: 3)
      end

      unless silver = Badge.find_by(name: BADGE_NAME_SILVER)
        silver = Badge.create!(name: BADGE_NAME_SILVER,
                               description: 'contributed 25 accepted pull requests',
                               badge_type_id: 2)
      end

      unless gold = Badge.find_by(name: BADGE_NAME_GOLD)
        gold = Badge.create!(name: BADGE_NAME_GOLD,
                             description: 'contributed 250 accepted pull requests',
                             badge_type_id: 1)
      end
      [bronze, silver, gold]
    end

    def self.committer_badges
      unless bronze = Badge.find_by(name: COMMITER_BADGE_NAME_BRONZE)
        bronze = Badge.create!(name: COMMITER_BADGE_NAME_BRONZE,
                               description: 'created a commit',
                               enabled: false,
                               badge_type_id: 3)
      end

      unless silver = Badge.find_by(name: COMMITER_BADGE_NAME_SILVER)
        silver = Badge.create!(name: COMMITER_BADGE_NAME_SILVER,
                               description: 'created 25 commits',
                               enabled: false,
                               badge_type_id: 2)
      end

      unless gold = Badge.find_by(name: COMMITER_BADGE_NAME_GOLD)
        gold = Badge.create!(name: COMMITER_BADGE_NAME_GOLD,
                             description: 'created 1000 commits',
                             enabled: false,
                             badge_type_id: 1)
      end
      [bronze, silver, gold]
    end
  end
end
