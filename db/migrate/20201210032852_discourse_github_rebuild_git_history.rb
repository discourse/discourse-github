# frozen_string_literal: true

class DiscourseGithubRebuildGitHistory < ActiveRecord::Migration[6.0]
  def up
    execute "DELETE FROM github_commits"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
