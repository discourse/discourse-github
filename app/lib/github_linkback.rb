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
    projects = (SiteSetting.github_linkback_projects || "").split('|')
    return [] if projects.blank?

    PrettyText.extract_links(@post.cooked).map(&:url).find_all do |l|
      if l =~ /https?:\/\/github\.com\/([^\/]+)\/([^\/]+)\/commit\/([0-9a-f]+)/
        projects.include?("#{Regexp.last_match[1]}/#{Regexp.last_match[2]}")
      else
        false
      end
    end
  end

  def create
  end

end
