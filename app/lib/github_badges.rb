# frozen_string_literal: true

module ::GithubBadges

  def self.TMP_DIR
    @@tmp_dir ||= "/tmp/github_badges"
  end

  # used in tests
  def self.TMP_DIR=(path)
    @@tmp_dir = path
  end

  class Granter
    def initialize(emails)
      @emails = emails
      @badges = []
    end

    def add_badge(badge, as_title:, &blk)
      @badges << [badge, as_title, blk]
    end

    def grant!
      email_commits = @emails.group_by { |e| e }.map { |k, l| [k, l.count] }.to_h
      User.with_email(email_commits.keys).each do |user|
        commits_count = email_commits[user.email]
        @badges.each do |badge, as_title, threshold|
          if threshold.call(commits_count) && badge.enabled? && SiteSetting.enable_badges
            BadgeGranter.grant(badge, user)
            if user.title.blank? && as_title
              user.update_attributes!(title: badge.name)
            end
          end
        end
      end
    end
  end

  BADGE_NAME_BRONZE ||= 'Contributor'.freeze
  BADGE_NAME_SILVER ||= 'Great contributor'.freeze
  BADGE_NAME_GOLD   ||= 'Amazing contributor'.freeze

  COMMITER_BADGE_NAME_BRONZE ||= 'Committer'.freeze
  COMMITER_BADGE_NAME_SILVER ||= 'Frequent committer'.freeze
  COMMITER_BADGE_NAME_GOLD   ||= 'Amazing committer'.freeze

  def self.badge_grant!
    return if SiteSetting.github_badges_repo.blank?

    # ensure badges exist
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

    emails = []
    if !Rails.env.test?
      if Dir.exists?(self.TMP_DIR)
        Rails.logger.info `cd #{self.TMP_DIR} && git pull`
      else
        Rails.logger.info `git clone #{SiteSetting.github_badges_repo} #{self.TMP_DIR}`
      end
    end

    Dir.chdir(self.TMP_DIR) do
      `git log --merges --pretty=format:%p --grep='Merge pull request'`.each_line do |m|
        emails << (`git log -1 --format=%ce #{m.split(' ')[1].strip}`.strip)
      end
    end

    granter = GithubBadges::Granter.new(emails)
    granter.add_badge(bronze, as_title: false) { |commits| commits >= 1 }
    granter.add_badge(silver, as_title: true) { |commits| commits >= SiteSetting.github_silver_badge_min_commits }
    granter.add_badge(gold, as_title: true) { |commits| commits >= SiteSetting.github_gold_badge_min_commits }
    granter.grant!

    committer_badge_grant!
  end

  def self.committer_badge_grant!
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

    emails = []
    Dir.chdir(self.TMP_DIR) do
      `git log --no-merges --pretty=format:%H`.each_line do |h|
        emails << (`git log -1 --format=%ae #{h}`.strip)
        message = `git log -1 --format=%b #{h}`.strip
        message.scan(/co-authored-by:.+<(.+@.+)>/i).flatten.each { |e| emails << e }
      end
    end

    granter = GithubBadges::Granter.new(emails)
    granter.add_badge(bronze, as_title: false) { |commits| commits >= 1 }
    granter.add_badge(silver, as_title: true) { |commits| commits >= 25 }
    granter.add_badge(gold, as_title: true) { |commits| commits >= 1000 }
    granter.grant!
  end
end
