require 'rails_helper'
require 'jobs/regular/pull_hotlinked_images'

describe Jobs::ReplaceGithubNonPermalinks do
  let(:github_url) { "https://github.com/test/onebox/blob/master/lib/onebox/engine/github_blob_onebox.rb" }
  let(:github_permanent_url) { "https://github.com/test/onebox/blob/815ea9c0a8ffebe7bd7fcd34c10ff28c7a6b6974/lib/onebox/engine/github_blob_onebox.rb" }
  let(:github_url2) { "https://github.com/test/discourse/blob/master/app/models/tag.rb#L1-L3" }
  let(:github_permanent_url2) { "https://github.com/test/discourse/blob/7e4edcfae8a3c0e664b836ee7c5f28b47853a2f8/app/models/tag.rb#L1-L3" }
  let(:broken_github_url) { "https://github.com/test/oneblob/blob/master/lib/onebox/engine/nonexistent.rb" }
  let(:github_response_body) { { sha: '815ea9c0a8ffebe7bd7fcd34c10ff28c7a6b6974', commit: {} } }
  let(:github_response_body2) { { sha: '7e4edcfae8a3c0e664b836ee7c5f28b47853a2f8', commit: {} } }

  before do
    stub_request(:get, "https://api.github.com/repos/test/onebox/commits/master")
      .to_return(status: 200, body: github_response_body.to_json, headers: {})
    stub_request(:get, "https://api.github.com/repos/test/onebox/commits/815ea9c0a8ffebe7bd7fcd34c10ff28c7a6b6974")
      .to_return(status: 200, body: github_response_body.to_json, headers: {})
    stub_request(:get, "https://api.github.com/repos/test/oneblob/commits/master").to_return(status: 404)
    stub_request(:get, "https://api.github.com/repos/test/discourse/commits/master")
      .to_return(status: 200, body: github_response_body2.to_json, headers: {})
  end

  describe '#execute' do
    before do
      SiteSetting.queue_jobs = false
      SiteSetting.onebox_domains_blacklist = "github.com"
      SiteSetting.github_permalinks_enabled = true
    end

    it 'replaces link with permanent link' do
      post = Fabricate(:post, raw: "#{github_url}")
      Jobs::ReplaceGithubNonPermalinks.new.execute(post_id: post.id)
      post.reload

      expect(post.raw).to eq(github_permanent_url)
    end

    it "doesn't replace the link if it's already permanent" do
      post = Fabricate(:post, raw: github_permanent_url)
      Jobs::ReplaceGithubNonPermalinks.new.execute(post_id: post.id)
      post.reload

      expect(post.raw).to eq(github_permanent_url)
    end

    it "doesn't change the post if link is broken" do
      post = Fabricate(:post, raw: broken_github_url)
      Jobs::ReplaceGithubNonPermalinks.new.execute(post_id: post.id)
      post.reload

      expect(post.raw).to eq(broken_github_url)
    end

    it "works with multiple github urls in the post" do
      post = Fabricate(:post, raw: "#{github_url} #{github_url2} htts://github.com")
      Jobs::ReplaceGithubNonPermalinks.new.execute(post_id: post.id)
      post.reload

      updated_post = "#{github_permanent_url} #{github_permanent_url2} htts://github.com"
      expect(post.raw).to eq(updated_post)
    end
  end
end
