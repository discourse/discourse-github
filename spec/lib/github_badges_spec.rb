# frozen_string_literal: true

require 'rails_helper'

describe GithubBadges do
  original_dir = GithubBadges.TMP_DIR

  let(:bronze_user) { Fabricate(:user) }
  let(:bronze_user_repo_2) { Fabricate(:user) }
  let(:silver_user) { Fabricate(:user) }
  let(:co_author) { Fabricate(:user) }
  let(:contributer) { Fabricate(:user) }

  def exec(command)
    GithubBadges.exec(command, chdir: @dir)
  end

  context 'granting badges' do
    before do
      GithubBadges.TMP_DIR = File.join(Dir.tmpdir, SecureRandom.hex)
      SiteSetting.github_badges_repos = "https://github.com/org/repo1.git|https://github.com/org/repo2.git"
      repos = SiteSetting.github_badges_repos.split("|")

      @dir = GithubBadges.path_to_repo(repos[0])
      FileUtils.mkdir_p(@dir)
      exec("git init .")
      exec("git config user.email '#{bronze_user.email}'")
      exec("git config user.name '#{bronze_user.username}'")
      exec("echo $RANDOM > file && git add file")
      exec("git commit -am 'Commit\n\nCo-authored-by: #{co_author.username} <#{co_author.email}>'")
      exec("git config user.email '#{silver_user.email}'")
      exec("git config user.name '#{silver_user.username}'")
      25.times do |n|
        n += 2
        exec("echo $RANDOM > file#{n} && git add file#{n}")
        exec("git commit -am 'Commit #{n}'")
      end
      exec("git config user.email '#{contributer.email}'")
      exec("git config user.name '#{contributer.username}'")
      exec("git checkout -q -b pr")
      exec("echo $RANDOM > pr && git add pr")
      exec("git commit -am 'PR'")
      exec("git config user.email '#{bronze_user.email}'")
      exec("git config user.name '#{bronze_user.username}'")
      exec("git checkout -q master")
      exec("git merge pr --no-ff -m 'Merge pull request'")

      @dir = GithubBadges.path_to_repo(repos[1])
      FileUtils.mkdir_p(@dir)
      exec("git init .")
      exec("git config user.email '#{bronze_user_repo_2.email}'")
      exec("git config user.name '#{bronze_user_repo_2.username}'")
      exec("echo $RANDOM > file && git add file")
      exec("git commit -am 'Commit'")
    end

    after do
      FileUtils.rm_rf(GithubBadges.TMP_DIR)
      GithubBadges.TMP_DIR = original_dir
    end

    it 'works correctly' do
      # inital run to seed badges and then enable them
      GithubBadges.badge_grant!
      users = [bronze_user, bronze_user_repo_2, silver_user, co_author, contributer]
      users.each { |u| u.badges.destroy_all }

      [
        GithubBadges::COMMITER_BADGE_NAME_BRONZE,
        GithubBadges::COMMITER_BADGE_NAME_SILVER
      ].each do |name|
        Badge.find_by(name: name).update!(enabled: true)
      end

      GithubBadges.badge_grant!
      users.each(&:reload)

      [bronze_user, bronze_user_repo_2, co_author].each_with_index do |u, ind|
        expect(u.badges.pluck(:name)).to eq([GithubBadges::COMMITER_BADGE_NAME_BRONZE])
      end
      expect(contributer.badges.pluck(:name)).to contain_exactly(GithubBadges::BADGE_NAME_BRONZE, GithubBadges::COMMITER_BADGE_NAME_BRONZE)
      expect(silver_user.badges.pluck(:name)).to contain_exactly(GithubBadges::COMMITER_BADGE_NAME_BRONZE, GithubBadges::COMMITER_BADGE_NAME_SILVER)
    end
  end

  context 'path_to_repo' do
    it 'removes characters that are not suitable for filenames' do
      expect(GithubBadges.path_to_repo("https://dsf.com/org/repo.git"))
        .to eq(File.join(GithubBadges.TMP_DIR, "https___dsf_com_org_repo_git"))
      expect(GithubBadges.valid_repo?("rm -rf /")).to eq(false)
      expect(GithubBadges.valid_repo?("https://github.com/org/repo.git")).to eq(true)
    end
  end

  context 'valid_repo?' do
    it 'detects invalid URLs' do
      expect(GithubBadges.valid_repo?("rm -rf /")).to eq(false)
      expect(GithubBadges.valid_repo?("https://github.com/org/repo.git")).to eq(true)
    end
  end
end
