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
    return if SiteSetting.github_badges_repos.blank?

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
    SiteSetting.github_badges_repos.split("|").each do |repo|
      dir = path_to_repo(repo)
      if !Rails.env.test?
        if Dir.exists?(dir)
          Rails.logger.info `cd #{dir} && git pull`
        else
          if valid_repo?(repo)
            Rails.logger.info `git clone #{repo} #{dir}`
          else
            Rails.logger.warn("Invalid repo URL for the github badges plugin: #{repo}")
          end
        end
      end

      exec("git log --merges --pretty=format:%p --grep='Merge pull request'", chdir: dir).each_line do |m|
        emails << (exec("git log -1 --format=%ce #{m.split(' ')[1].strip}", chdir: dir).strip)
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
    SiteSetting.github_badges_repos.split("|").each do |repo|
      dir = path_to_repo(repo)
      emails.concat(exec("git log --no-merges --format=%ae", chdir: dir).split("\n"))
      emails.concat(exec("git log --no-merges --format=%b | grep -Poi 'co-authored-by:.*<\\K(.*)(?=>)' || true", chdir: dir).split("\n"))
    end

    granter = GithubBadges::Granter.new(emails)
    granter.add_badge(bronze, as_title: false) { |commits| commits >= 1 }
    granter.add_badge(silver, as_title: true) { |commits| commits >= 25 }
    granter.add_badge(gold, as_title: true) { |commits| commits >= 1000 }
    granter.grant!
  end

  def self.path_to_repo(repo)
    File.join(self.TMP_DIR, repo.gsub(/[^A-Za-z0-9-_]/, "_"))
  end

  def self.valid_repo?(repo)
    uri = URI.parse(repo)
    URI::HTTP === uri || URI::HTTPS === uri
  rescue URI::Error
    false
  end

  def self.exec(command, chdir:)
    Discourse::Utils.execute_command(command, chdir: chdir)
  end
end
