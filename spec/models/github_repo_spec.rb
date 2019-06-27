# frozen_string_literal: true

require 'rails_helper'

describe DiscourseGithubPlugin::GithubRepo do

  it "strips .git from url" do
    SiteSetting.set("github_badges_repos", "https://github.com/discourse/discourse.git")
    repo = DiscourseGithubPlugin::GithubRepo.repos.first
    expect(repo.name).to eq ("discourse/discourse")
  end

  it "strips trailing slash from url" do
    SiteSetting.set("github_badges_repos", "https://github.com/discourse/discourse/")
    repo = DiscourseGithubPlugin::GithubRepo.repos.first
    expect(repo.name).to eq ("discourse/discourse")
  end
end

