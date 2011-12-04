require 'find'

def scm
  scm = ENV['SCM'] || 'git'
  if !(scm == 'svn' || scm == 'git' || scm == 'git_with_svn')
    puts "#{scm} is not supported. Please use svn or git."
    exit
  end
  scm
end

# Extract project name.
def project_name
  File.expand_path(Rails.root).split("/").last
end

# Print message with separator.
def p80(message)
  puts "-"*80
  puts message if message
  yield if block_given?
end

# Remove old backups
def remove_old_backups(backup_dir)
  backups_to_keep = ENV['NUMBER_OF_BACKUPS_TO_KEEP'] || 30
  backups = []
  Find.find(backup_dir) { |file_name| backups << file_name if !File.directory?(file_name) && file_name =~ /.*\.tar.gz$/ }
  backups.sort!
  (backups - backups.last(backups_to_keep - 1)).each do |file_name|
    puts "Removing #{file_name}..."
    FileUtils.rm(file_name)
  end
end

namespace :backup do
  desc 'Creates a backup of the project in the local disk.'
  task :local do
    backup_dir = '../backups/backup-' + project_name
    sh "mkdir -p #{backup_dir}" if !FileTest.exists?(backup_dir)
    remove_old_backups(backup_dir)
    sh "tar cfz #{backup_dir}/#{project_name}-#{Time.now.strftime('%Y%m%d-%H%M%S')}.tar.gz ../#{project_name}"
  end
end

namespace :scm do
  namespace :status do
    desc 'Check if project can be committed to the repository.'
    task :check do
      Rake::Task["#{scm}:status:check"].invoke 
    end
  end

  desc 'Update files from repository.'
  task :update do
    Rake::Task["svn:update"].invoke if scm == 'svn' 
    Rake::Task["git:pull"].invoke if scm == 'git'
    Rake::Task["git_with_svn:rebase"].invoke if scm == 'git_with_svn' 
  end
  
  desc 'Commit project.'
  task :commit do
    Rake::Task["svn:commit"].invoke if scm == 'svn' 
    if scm == 'git' 
      Rake::Task["git:push"].invoke 
    end
    Rake::Task["git_with_svn:dcommit"].invoke if scm == 'git_with_svn'
  end
end


namespace :svn do
  namespace :status do
    desc 'Check if project can be committed to the repository.'
    task :check do
      files_out_of_sync = `svn status | grep -e '[?|!]'`
      if files_out_of_sync.size > 0
        puts "Files out of sync:"
        files_out_of_sync.each { |filename| puts filename }
        puts 
        exit
      end
    end
  end

  desc 'Update files from repository.'
  task :update do
    sh "svn update"
  end
  
  desc 'Commit project.'
  task :commit do
    message = ''
    message = "-m ''" if ENV['SKIP_COMMIT_MESSAGES']
    sh "svn commit #{message}"
  end
end

namespace :git do
  
  def has_files_to_commit?
    return false if (`git status`).include?('nothing to commit')
    true  
  end
  
  namespace :status do
    desc 'Check if project can be committed to the repository.'
    task :check do
      result = `git status`
      if result.include?('Untracked files:') || result.include?('unmerged:')
        puts "Files out of sync:"
        puts result
        exit
      end
    end
  end

  desc 'Update files from repository.'
  task :pull do
    sh "git pull --rebase"
  end
  
  desc 'Commit project.'
  task :commit do
    message = ''
    message = "-m 'Committed by integration plugin.'" if ENV['SKIP_COMMIT_MESSAGES']
    sh "git commit -a -v #{message}"
  end
  
  desc 'Push project.'
  task :push do
    Rake::Task['git:commit'].invoke if has_files_to_commit? 
    sh "git push"
  end
end

namespace :git_with_svn do
  namespace :status do
    task :check do
      Rake::Task["git:status:check"].invoke
    end
  end
  
  desc 'Rebase the git project from svn repository'
  task :rebase do
    sh "git svn rebase"
  end
  
  desc 'Send all changes to svn repository'
  task :dcommit do
    sh "git svn dcommit"
  end
end

namespace :integration do
  task :start => ["scm:status:check", "log:clear", "tmp:clear", "backup:local", "scm:update"]
  task :finish => ["scm:commit"]

  desc 'Check code coverage'
  task :coverage_verify do
    sh "ruby #{File.expand_path(File.dirname(__FILE__) + '/../../test/coverage_test.rb')}" 
  end
end

desc 'Integrate new code to repository'
task :integrate do
  if !defined?(INTEGRATION_TASKS)
    p80 %{
You should define INTEGRATION_TASKS constant. We recommend that you define it on lib/tasks/integration.rake file. The file doesn't exists. You should create it in your project.

You'll probably want to add coverage/ to your .gitignore file.

A sample content look like this:

INTEGRATION_TASKS = %w( 
  integration:start
  db:migrate
  spec
  integration:coverage_verify
  jasmine:ci
  integration:finish
)

Look at other samples at: http://github.com/mergulhao/integration/tree/master/samples
}
    exit
  end
  
  INTEGRATION_TASKS.each do |subtask|
    p80("Executing #{subtask}...") do 
      RAILS_ENV = ENV['RAILS_ENV'] || 'development'
      Rake::Task[subtask].invoke 
    end
  end
end
