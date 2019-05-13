# frozen_string_literal: true

require 'rails_helper'

describe GithubPermalinks do
  let(:cpp) { CookedPostProcessor.new(post) }

  context "when it doesn't contain github link to the file" do
    let(:post) { Fabricate(:post, raw: "there is no github link") }
      it "it does not run the job" do
        Jobs.expects(:cancel_scheduled_job).never
        cpp.replace_github_non_permalinks
      end
  end

  context "when it contains github link" do
    let(:post) { Fabricate(:post, raw: "https://github.com/discourse/onebox/blob/master/lib/onebox/engine/gfycat_onebox.rb") }
    it "ensures only one job is scheduled right after the editing_grace_period" do
      Jobs.expects(:cancel_scheduled_job).with(:replace_github_non_permalinks, post_id: post.id).once
      delay = SiteSetting.editing_grace_period + 1
      Jobs.expects(:enqueue_in).with(delay.seconds, :replace_github_non_permalinks, post_id: post.id, bypass_bump: false).once
      cpp.replace_github_non_permalinks
    end
  end
end
