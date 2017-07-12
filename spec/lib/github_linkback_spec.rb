require 'rails_helper'

describe GithubLinkback do
  context ".should_enqueue?" do

    let(:post_without_link) { Fabricate.build(:post) }

    let(:post_with_link) do
      Fabricate.build(:post, raw: 'https://github.com/discourse/discourse/commit/5be9bee2307dd517c26e6ef269471aceba5d5acf')
    end

    it "returns false when the feature is disabled" do
      SiteSetting.github_linkback_enabled = false
      expect(GithubLinkback.should_enqueue?(post_with_link)).to eq(false)
    end

    it "returns false without a post" do
      SiteSetting.github_linkback_enabled = true
      expect(GithubLinkback.should_enqueue?(nil)).to eq(false)
    end

    it "returns false when the post doesn't have the word github in it" do
      SiteSetting.github_linkback_enabled = true
      expect(GithubLinkback.should_enqueue?(post_without_link)).to eq(false)
    end

    it "returns true when the feature is enabled" do
      SiteSetting.github_linkback_enabled = true
      expect(GithubLinkback.should_enqueue?(post_with_link)).to eq(true)
    end

  end

end
