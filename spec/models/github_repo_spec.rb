# frozen_string_literal: true

require 'rails_helper'

describe DiscourseGithubPlugin::GithubRepo do

  it "strips .git from url" do
    SiteSetting.github_badges_repos = "https://github.com/discourse/discourse.git"
    repo = DiscourseGithubPlugin::GithubRepo.repos.first
    expect(repo.name).to eq ("discourse/discourse")
  end

  it "strips trailing slash from url" do
    SiteSetting.github_badges_repos = "https://github.com/discourse/discourse/"
    repo = DiscourseGithubPlugin::GithubRepo.repos.first
    expect(repo.name).to eq ("discourse/discourse")
  end

  it "doesn't raise an error when the site setting doesn't contain a github URL" do
    SiteSetting.github_badges_repos = "https://eviltrout.com/discourse/discourse/"
    expect(DiscourseGithubPlugin::GithubRepo.repos).to be_blank
  end
end
