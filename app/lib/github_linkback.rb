require_dependency 'pretty_text'
require 'digest/sha1'

class GithubLinkback

  class Link
    attr_reader :url, :project, :type
    attr_accessor :sha, :pr_number

    def initialize(url, project, type)
      @url = url
      @project = project
      @type = type
    end
  end

  def initialize(post)
    @post = post
  end

  def should_enqueue?
    !!(SiteSetting.github_linkback_enabled? &&
      @post.present? &&
      @post.raw =~ /github/ &&
      Guardian.new.can_see?(@post) &&
      @post.topic.visible?)
  end

  def enqueue
    Jobs.enqueue(:create_github_linkback, post_id: @post.id) if should_enqueue?
  end

  def github_links
    projects = SiteSetting.github_linkback_projects.split('|')

    return [] if projects.blank?

    result = {}
    PrettyText.extract_links(@post.cooked).map(&:url).each do |l|
      l = l.split('#')[0]
      next if @post.custom_fields[GithubLinkback.field_for(l)].present?

      if l =~ /https?:\/\/github\.com\/([^\/]+)\/([^\/]+)\/commit\/([0-9a-f]+)/
        project = "#{Regexp.last_match[1]}/#{Regexp.last_match[2]}"
        if is_allowed_project_link?(projects, project)
          link = Link.new(Regexp.last_match[0], project, :commit)
          link.sha = Regexp.last_match[3]
          result[link.url] = link
        end
      elsif l =~ /https?:\/\/github.com\/([^\/]+)\/([^\/]+)\/pull\/(\d+)/
        project = "#{Regexp.last_match[1]}/#{Regexp.last_match[2]}"
        if is_allowed_project_link?(projects, project)
          link = Link.new(Regexp.last_match[0], project, :pr)
          link.pr_number = Regexp.last_match[3].to_i
          result[link.url] = link
        end
      end
    end
    result.values
  end

  def is_allowed_project_link?(projects, project)
    return true if projects.include?(project)

    check_user = project.split("/")[0]
    projects.any? do |allowed_project|
      allowed_user, allowed_all_projects = allowed_project.split("/")
      (allowed_user == check_user) && (allowed_all_projects == "*")
    end
  end

  def create
    return [] unless SiteSetting.github_linkback_access_token.present?

    links = []

    DistributedMutex.synchronize("github_linkback_#{@post.id}") do
      links = github_links
      links.each do |link|
        case link.type
        when :commit
          post_commit(link)
        when :pr
          post_pr(link)
        else
          next
        end

        # Don't post the same link twice
        @post.custom_fields[GithubLinkback.field_for(link.url)] = 'true'
      end
      @post.save_custom_fields
    end

    links
  end

  def self.field_for(url)
    "github-linkback:#{Digest::SHA1.hexdigest(url)[0..15]}"
  end

  private

  def post_pr(link)
    github_url = "https://api.github.com/repos/#{link.project}/issues/#{link.pr_number}/comments"
    comment = I18n.t(
      'github_linkback.pr_template',
      title: SiteSetting.title,
      post_url: "#{Discourse.base_url}#{@post.url}"
    )

    Excon.post(
      github_url,
      body: { body: comment }.to_json,
      headers: headers
    )
  end

  def post_commit(link)
    github_url = "https://api.github.com/repos/#{link.project}/commits/#{link.sha}/comments"

    comment = I18n.t(
      'github_linkback.commit_template',
      title: SiteSetting.title,
      post_url: "#{Discourse.base_url}#{@post.url}"
    )

    Excon.post(
      github_url,
      body: { body: comment }.to_json,
      headers: headers
    )
  end

  def headers
    {
      "Content-Type" => "application/json",
      "Authorization" => "token #{SiteSetting.github_linkback_access_token}",
      "User-Agent" => "Discourse-Github-Linkback"
    }
  end

end
