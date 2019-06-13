# frozen_string_literal: true

require 'rails_helper'

describe GithubBadges do
  original_dir = GithubBadges.TMP_DIR
  GithubBadges.TMP_DIR = File.join(Dir.tmpdir, SecureRandom.hex)

  let(:bronze_user) { Fabricate(:user) }
  let(:silver_user) { Fabricate(:user) }

  before do
    SiteSetting.github_badges_repo = "https://github.com/org/repo.git"

    FileUtils.mkdir_p(GithubBadges.TMP_DIR)
    Dir.chdir(GithubBadges.TMP_DIR) do
      `git init .`
      `git config user.email '#{bronze_user.email}'`
      `git config user.name '#{bronze_user.username}'`
      `echo $RANDOM > file && git add file`
      `git commit -am "Commit"`
      `git config user.email '#{silver_user.email}'`
      `git config user.name '#{silver_user.username}'`
      25.times do |n|
        n += 2
        `echo $RANDOM > file#{n} && git add file#{n}`
        `git commit -am "Commit #{n}"`
      end
    end
  end

  after do
    FileUtils.rm_rf(GithubBadges.TMP_DIR)
    GithubBadges.TMP_DIR = original_dir
  end

  it 'grants badges correctly' do
    # inital run to seed badges and then enable them
    GithubBadges.badge_grant!
    bronze_user.badges.destroy_all
    silver_user.badges.destroy_all

    [
      GithubBadges::COMMITER_BADGE_NAME_BRONZE,
      GithubBadges::COMMITER_BADGE_NAME_SILVER
    ].each do |name|
      Badge.find_by(name: name).update!(enabled: true)
    end

    GithubBadges.badge_grant!
    bronze_user.reload
    silver_user.reload
    expect(bronze_user.badges.pluck(:name)).to eq([GithubBadges::COMMITER_BADGE_NAME_BRONZE])
    expect(silver_user.badges.pluck(:name)).to contain_exactly(GithubBadges::COMMITER_BADGE_NAME_BRONZE, GithubBadges::COMMITER_BADGE_NAME_SILVER)
  end
end
