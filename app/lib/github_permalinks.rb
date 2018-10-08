module ::GithubPermalinks
  def self.replace_github_non_permalinks(post)
    # replaces github non-permalinks with permalinks containing a specific commit id
    regex = /https?:\/\/github\.com\/[^\/]+\/[^\/\s]+\/blob\/[^\s]+/i
    # don't replace urls in posts that are more than 1h old
    return unless ((Time.zone.now - post.created_at) / 60).round <= 60
    # only run the job when post is changed by a user and it contains a github url
    return if (post.last_editor_id && post.last_editor_id <= 0) || !post.raw.match(regex)
    # make sure no other job is scheduled
    Jobs.cancel_scheduled_job(:replace_github_non_permalinks, post_id: post.id)
    # schedule the job
    delay = SiteSetting.editing_grace_period + 1
    Jobs.enqueue_in(delay.seconds.to_i, :replace_github_non_permalinks, post_id: post.id, bypass_bump: false)
  end
end
