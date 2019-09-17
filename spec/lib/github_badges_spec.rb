# frozen_string_literal: true

require 'rails_helper'

describe DiscourseGithubPlugin::GithubBadges do
  let(:bronze_user) { Fabricate(:user) }
  let(:bronze_user_repo_2) { Fabricate(:user) }
  let(:silver_user) { Fabricate(:user) }
  let(:contributor) { Fabricate(:user) }
  let(:private_email_contributor) { Fabricate(:user) }
  let(:private_email_contributor2) { Fabricate(:user) }
  let(:merge_commit_user) { Fabricate(:user) }

  context 'committer and contributor badges' do
    before do
      roles = DiscourseGithubPlugin::CommitsPopulator::ROLES
      SiteSetting.github_badges_repos = "https://github.com/org/repo1.git|https://github.com/org/repo2.git"
      repo1 = DiscourseGithubPlugin::GithubRepo.repos.find { |repo| repo.name == "org/repo1" }
      repo2 = DiscourseGithubPlugin::GithubRepo.repos.find { |repo| repo.name == "org/repo2" }
      repo1.commits.create!(
        sha: "1",
        email: bronze_user.email,
        committed_at: 1.day.ago,
        role_id: roles[:committer]
      )
      repo1.commits.create!(
        sha: "2",
        email: merge_commit_user.email,
        merge_commit: true,
        committed_at: 1.day.ago,
        role_id: roles[:committer]
      )
      repo1.commits.create!(
        sha: "3",
        email: contributor.email,
        committed_at: 1.day.ago,
        role_id: roles[:contributor]
      )
      25.times do |n|
        repo1.commits.create!(
          sha: "blah#{n}",
          email: silver_user.email,
          committed_at: 1.day.ago,
          role_id: roles[:committer]
        )
      end
      repo2.commits.create!(
        sha: "4",
        email: bronze_user_repo_2.email,
        committed_at: 2.day.ago,
        role_id: roles[:committer]
      )

      GithubUserInfo.create!(
        user_id: private_email_contributor.id,
        screen_name: "bob",
        github_user_id: 100,
      )
      repo1.commits.create!(
        sha: "123",
        email: "100+bob@users.noreply.github.com",
        committed_at: 1.day.ago,
        role_id: roles[:contributor]
      )

      GithubUserInfo.create!(
        user_id: private_email_contributor2.id,
        screen_name: "joe",
        github_user_id: 101,
      )
      repo1.commits.create!(
        sha: "124",
        email: "joe@users.noreply.github.com",
        committed_at: 1.day.ago,
        role_id: roles[:contributor]
      )
    end

    it 'granted correctly' do
      # inital run to seed badges and then enable them
      DiscourseGithubPlugin::GithubBadges.grant!

      contributor_bronze = DiscourseGithubPlugin::GithubBadges::BADGE_NAME_BRONZE
      committer_bronze = DiscourseGithubPlugin::GithubBadges::COMMITER_BADGE_NAME_BRONZE
      committer_silver = DiscourseGithubPlugin::GithubBadges::COMMITER_BADGE_NAME_SILVER

      users = [
        bronze_user,
        bronze_user_repo_2,
        silver_user,
        contributor,
        private_email_contributor,
        private_email_contributor2,
        merge_commit_user,
      ]
      users.each { |u| u.badges.destroy_all }

      [committer_bronze, committer_silver].each do |name|
        Badge.find_by(name: name).update!(enabled: true)
      end

      DiscourseGithubPlugin::GithubBadges.grant!
      users.each(&:reload)

      expect(merge_commit_user.badges).to eq([])
      [bronze_user, bronze_user_repo_2].each_with_index do |u, ind|
        expect(u.badges.pluck(:name)).to eq([committer_bronze])
      end
      expect(contributor.badges.pluck(:name)).to eq([contributor_bronze])
      expect(private_email_contributor.badges.pluck(:name)).to eq([contributor_bronze])
      expect(private_email_contributor2.badges.pluck(:name)).to eq([contributor_bronze])
      expect(silver_user.badges.pluck(:name)).to contain_exactly(committer_bronze, committer_silver)
    end
  end
end
