module ::GithubBadges

  BADGE_NAME_BRONZE ||= 'Contributor'.freeze
  BADGE_NAME_SILVER ||= 'Great contributor'.freeze
  BADGE_NAME_GOLD   ||= 'Amazing contributor'.freeze

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
    path = '/tmp/github_badges'

    if Dir.exists?(path)
      Rails.logger.info `cd #{path} && git pull`
    else
      Rails.logger.info `cd /tmp && git clone #{SiteSetting.github_badges_repo} github_badges`
    end

    `cd #{path} && git log --merges --pretty=format:%p --grep='Merge pull request'`.each_line do |m|
      emails << (`cd #{path} && git log -1 --format=%ce #{m.split(' ')[1].strip}`.strip)
    end

    email_commits = emails.group_by { |e| e }.map { |k, l| [k, l.count] }.to_h

    Rails.logger.info "#{email_commits.length} commits found!"

    User.with_email(email_commits.keys).each do |user|
      commits = email_commits[user.email]

      BadgeGranter.grant(bronze, user)

      if commits >= 25
        BadgeGranter.grant(silver, user)
        if user.title.blank?
          user.update_attributes!(title: silver.name)
        end
      end

      if commits >= 250
        BadgeGranter.grant(gold, user)
        if user.title.blank?
          user.update_attributes!(title: gold.name)
        end
      end
    end
  end
end
