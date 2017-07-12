require 'rails_helper'

describe GithubLinkback do

  context "#should_enqueue?" do
    let(:post_without_link) { Fabricate.build(:post) }

    let(:post_with_link) do
      Fabricate.build(:post, raw: 'https://github.com/discourse/discourse/commit/5be9bee2307dd517c26e6ef269471aceba5d5acf')
    end

    it "returns false when the feature is disabled" do
      SiteSetting.github_linkback_enabled = false
      expect(GithubLinkback.new(post_with_link).should_enqueue?).to eq(false)
    end

    it "returns false without a post" do
      SiteSetting.github_linkback_enabled = true
      expect(GithubLinkback.new(nil).should_enqueue?).to eq(false)
    end

    it "returns false when the post doesn't have the word github in it" do
      SiteSetting.github_linkback_enabled = true
      expect(GithubLinkback.new(post_without_link).should_enqueue?).to eq(false)
    end

    it "returns true when the feature is enabled" do
      SiteSetting.github_linkback_enabled = true
      expect(GithubLinkback.new(post_with_link).should_enqueue?).to eq(true)
    end
  end

  context "#github_urls" do
    let(:github_link) { "https://github.com/discourse/discourse/commit/76981605fa10975e2e7af457e2f6a31909e0c811" }

    let(:post) do
      Fabricate(
        :post,
        raw: <<~RAW
          cool post

          #{github_link}

          https://eviltrout.com/not-a-gh-link

          https://github.com/eviltrout/tis-100/commit/e22b23f354e3a1c31bc7ad37a6a309fd6daf18f4
        RAW
      )
    end

    it "returns an empty array with no projects" do
      SiteSetting.github_linkback_projects = ""
      links = GithubLinkback.new(post).github_links
      expect(links).to eq([])
    end

    it "should return the urls for the selected projects" do
      SiteSetting.github_linkback_projects = "discourse/discourse|eviltrout/ember-performance"
      links = GithubLinkback.new(post).github_links
      expect(links.size).to eq(1)
      expect(links).to include(github_link)
    end
  end

end
