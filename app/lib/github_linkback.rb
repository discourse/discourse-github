require_dependency 'pretty_text'
require 'digest/sha1'

class GithubLinkback

  class Link
    attr_reader :url, :project, :sha

    def initialize(url, project, sha)
      @url = url
      @project = project
      @sha = sha
    end
  end

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

    result = []
    return result if projects.blank?

    PrettyText.extract_links(@post.cooked).map(&:url).uniq.each do |l|
      if l =~ /https?:\/\/github\.com\/([^\/]+)\/([^\/]+)\/commit\/([0-9a-f]+)/

        next if @post.custom_fields[GithubLinkback.field_for(l)].present?

        project = "#{Regexp.last_match[1]}/#{Regexp.last_match[2]}"

        if projects.include?(project)
          result << Link.new(
            Regexp.last_match[0],
            project,
            Regexp.last_match[3]
          )
        end
      end
    end
    result
  end

  def create
    return [] unless SiteSetting.github_linkback_access_token.present?

    links = github_links
    links.each do |link|
      github_url = "https://api.github.com/repos/#{link.project}/commits/#{link.sha}/comments"

      comment = I18n.t('github_linkback.commit_template',
        title: SiteSetting.title,
        post_url: "#{Discourse.base_url}#{@post.url}"
      )

      Excon.post(
        github_url,
        body: { body: comment }.to_json,
        headers: {
          "Content-Type" => "application/json",
          "Authorization" => "token #{SiteSetting.github_linkback_access_token}",
          "User-Agent" => "Discourse-Github-Linkback"
        }
      )

      # Don't post the same link twice
      @post.custom_fields[GithubLinkback.field_for(link.url)] = 'true'
      @post.save_custom_fields
    end

    links
  end


  def self.field_for(url)
    "github-linkback:Digest::SHA1.hexdigest(url)[0..15]"
  end
end
