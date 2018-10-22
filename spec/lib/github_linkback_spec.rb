require 'rails_helper'

describe GithubLinkback do
  let(:github_commit_link) { "https://github.com/discourse/discourse/commit/76981605fa10975e2e7af457e2f6a31909e0c811" }
  let(:github_pr_link) { "https://github.com/discourse/discourse/pull/701" }
  let(:github_pr_link_wildcard) { "https://github.com/discourse/discourse-github-linkback/pull/3" }

  let(:post) do
    Fabricate(
      :post,
      raw: <<~RAW
        cool post

        #{github_commit_link}

        https://eviltrout.com/not-a-gh-link

        #{github_commit_link}

        https://github.com/eviltrout/tis-100/commit/e22b23f354e3a1c31bc7ad37a6a309fd6daf18f4

        #{github_pr_link}

        i have no idea what i'm linking back to

        #{github_pr_link_wildcard}

        end_of_transmission

      RAW
    )
  end

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

    context "private_message" do
      it "doesn't enqueue private messages" do
        SiteSetting.github_linkback_enabled = true
        private_topic = Fabricate(:private_message_topic)
        private_post = Fabricate(
          :post,
          topic: private_topic,
          raw: "this post http://github.com should not enqueue"
        )
        expect(GithubLinkback.new(private_post).should_enqueue?).to eq(false)
      end
    end

    context "unlisted topics" do
      it "doesn't enqueue unlisted topics" do
        SiteSetting.github_linkback_enabled = true
        unlisted_topic = Fabricate(:topic, visible: false)
        unlisted_post = Fabricate(
          :post,
          topic: unlisted_topic,
          raw: "this post http://github.com should not enqueue"
        )
        expect(GithubLinkback.new(unlisted_post).should_enqueue?).to eq(false)
      end
    end
  end

  context "#github_urls" do
    it "returns an empty array with no projects" do
      SiteSetting.github_linkback_projects = ""
      links = GithubLinkback.new(post).github_links
      expect(links).to eq([])
    end

    it "doesn't return links that have already been posted" do
      SiteSetting.github_linkback_projects = "discourse/discourse|eviltrout/ember-performance|discourse/*"

      post.custom_fields[GithubLinkback.field_for(github_commit_link)] = "true"
      post.custom_fields[GithubLinkback.field_for(github_pr_link)] = "true"
      post.custom_fields[GithubLinkback.field_for(github_pr_link_wildcard)] = "true"
      post.save_custom_fields

      links = GithubLinkback.new(post).github_links
      expect(links.size).to eq(0)
    end

    it "should return the urls for the selected projects" do
      SiteSetting.github_linkback_projects = "discourse/discourse|eviltrout/ember-performance|discourse/*"
      links = GithubLinkback.new(post).github_links
      expect(links.size).to eq(3)

      expect(links[0].url).to eq(github_commit_link)
      expect(links[0].project).to eq("discourse/discourse")
      expect(links[0].sha).to eq("76981605fa10975e2e7af457e2f6a31909e0c811")
      expect(links[0].type).to eq(:commit)

      expect(links[1].url).to eq(github_pr_link)
      expect(links[1].project).to eq("discourse/discourse")
      expect(links[1].pr_number).to eq(701)
      expect(links[1].type).to eq(:pr)

      expect(links[2].url).to eq(github_pr_link_wildcard)
      expect(links[2].project).to eq("discourse/discourse-github-linkback")
      expect(links[2].pr_number).to eq(3)
      expect(links[2].type).to eq(:pr)
    end
  end

  context "#create" do
    before do
      SiteSetting.github_linkback_projects = "discourse/discourse|discourse/*"
    end

    it "returns an empty array without an access token" do
      expect(GithubLinkback.new(post).create).to be_blank
    end

    context "with an access token" do
      let(:headers) {
        { 'Authorization' => 'token abcdef',
          'Content-Type' => 'application/json',
          'Host' => 'api.github.com',
          'User-Agent' => 'Discourse-Github-Linkback' }
      }

      before do
        SiteSetting.github_linkback_access_token = "abcdef"

        stub_request(:post, "https://api.github.com/repos/discourse/discourse/commits/76981605fa10975e2e7af457e2f6a31909e0c811/comments").
          with(headers: headers).
          to_return(status: 200, body: "", headers: {})

        stub_request(:post, "https://api.github.com/repos/discourse/discourse/issues/701/comments").
          with(headers: headers).
          to_return(status: 200, body: "", headers: {})

        stub_request(:post, "https://api.github.com/repos/discourse/discourse-github-linkback/issues/3/comments").
          with(headers: headers).
          to_return(status: 200, body: "", headers: {})

      end

      it "returns the URL it linked to and custom fields" do
        links = GithubLinkback.new(post).create
        expect(links.size).to eq(3)

        expect(links[0].url).to eq(github_commit_link)
        field = GithubLinkback.field_for(github_commit_link)
        expect(post.custom_fields[field]).to be_present

        expect(links[1].url).to eq(github_pr_link)
        field = GithubLinkback.field_for(github_pr_link)
        expect(post.custom_fields[field]).to be_present

        expect(links[2].url).to eq(github_pr_link_wildcard)
        field = GithubLinkback.field_for(github_pr_link_wildcard)
        expect(post.custom_fields[field]).to be_present
      end
    end
  end

end
