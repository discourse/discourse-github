require_dependency 'pretty_text'

class GithubLinkback

  def initialize(post)
    @post = post
  end

  def should_enqueue?
    !!(SiteSetting.github_linkback_enabled? &&
      @post.present? &&
      @post.raw =~ /github/)
  end

  def enqueue
    Jobs.enqueue(:create_github_linkback, post_id: @post.id) if should_enqueue?
  end

  def github_links
    PrettyText.extract_links(@post.cooked).map(&:url).find_all do |l|
      l =~ /github\.com/
    end
  end

  def create
  end

end
