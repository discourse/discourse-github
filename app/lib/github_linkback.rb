module GithubLinkback

  def self.should_enqueue?(post)
    !!(SiteSetting.github_linkback_enabled? &&
      post.present? &&
      post.raw =~ /github/)
  end

end
