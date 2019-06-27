# frozen_string_literal: true

module DiscourseGithubPlugin
  class GithubRepo < ActiveRecord::Base
    has_many :commits, foreign_key: :repo_id, class_name: :GithubCommit, dependent: :destroy

    def self.repos
      repos = []
      SiteSetting.github_badges_repos.split("|").each do |link|
        name = link.match(/https?:\/\/github.com\/(.+)/).captures.first
        name.gsub!(/\.git$/, "")
        name.gsub!(/\/$/, "") # Remove trailing '/'
        repos << find_or_create_by!(name: name)
      end
      repos
    end
  end
end

# == Schema Information
#
# Table name: github_repos
#
#  id         :bigint           not null, primary key
#  name       :string(255)      not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_github_repos_on_name  (name) UNIQUE
#
