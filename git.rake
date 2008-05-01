desc "This is just here for the other tasks and isn't intended for your use"
task 'git:helpers' do
  class GitError < RuntimeError; end
  class GitRebaseError < GitError; end
  
  def git_branch
    `git-branch`.grep(/^\*/).first.strip[(2..-1)]
  end
  def git_branches
    `git-branch`.to_a.map { |b| b[(2..-1)].chomp }
  end
  def git?
    `git-status`
    (not ($?.exitstatus == 128))
  end
  def git_stash
    `git-diff-files --quiet`
    if ($?.exitstatus == 1) then
      stash = true
      clear = (`git-stash list`.scan("\n").size == 0)
      puts("* Saving changes...")
      `git-stash save`
    else
      stash = false
    end
    begin
      yield rescue puts("* Encountered an error, backing out...")
      ensure
        if stash then
          puts("* Applying changes...")
          sh("git-stash apply")
          `git-stash clear` if clear
        end
    end
  end
  
  def git_checkout(what = nil)
    branch = git_branch
    sh("git-checkout #{what}") if branch != what
    if block_given?
      yield
      sh("git-checkout #{branch}") if branch != what
    end
  end
  
  def git_fetch
    sh("git#{"-svn" if git_svn?} fetch")
  end
  
  def assert_command_succeeded(*args)
    raise *args if $?.exitstatus != 0
  end
  
  def assert_rebase_succeeded(what = nil)
    assert_command_succeeded GitRebaseError, "conflict while rebasing branch #{what}"
  end
  
  def git_rebase(what = nil)
    if git_svn? then
      git_checkout what do
        sh("git-svn rebase --local")
        assert_rebase_succeeded what
      end
    else
      sh("git-rebase origin/master #{what}")
      assert_rebase_succeeded what
    end
  end
  def git_push
    git_svn? ? (sh("git-svn dcommit")) : (sh("git-push"))
  end
  def git_svn?
    not File.readlines(".git/config").grep(/^\[svn-remote "svn"\]\s*$/).empty?
  end
  def argv
    ARGV.inject([]) do |argv, arg|
      if (argv.last and argv.last =~ /=$/) then
        (argv.last << arg)
      else
        (argv << arg.dup)
      end
      argv
    end
  end
  def correct_env_from_argv
    argv.grep(/^[A-Z]+=/).each { |kv| ENV.send(:[]=, *kv.split("=", 2)) }
  end
  def env(name)
    case val = ENV[name]
    when "", nil then
      nil
    else
      val
    end
  end
  correct_env_from_argv
end

desc 'Pull new commits from the repository'
task 'git:update' => [ 'git:helpers' ] do
  git_stash do
    branch = git_branch
    if (branch == "master") then
      switch = false
    else
      switch = true
      `git-checkout master`
      puts("* Switching back to master...")
    end
    puts("* Pulling in new commits...")
    git_fetch
    git_rebase
    if switch then
      puts("* Porting changes into #{branch}...")
      `git-checkout #{branch}`
      sh("git-rebase master")
    end
  end
end

desc 'Push local commits into the remote repository'
task 'git:push' => [ 'git:update' ] do
  git_stash do
    puts("* Pushing changes...")
    git_push
    branch = git_branch
    unless (branch == "master") then
      `git-checkout master`
      puts("* Porting changes into master")
      git_rebase
      `git-checkout #{branch}`
    end
  end
end

desc 'Delete the current branch and switch back to master'
task 'git:close' => [ 'git:helpers' ] do
  branch = (env("NAME") or git_branch)
  current = git_branch
  if (branch == "master") then
    $stderr.puts("* Cannot delete master branch")
    exit(1)
  end
  if (current == branch) then
    puts("* Switching to master")
    `git-checkout master 2>/dev/null`
  end
  puts("* Deleting branch #{branch}")
  `git-branch -d #{branch} 2>/dev/null`
  if ($?.exitstatus == 1) then
    $stderr.puts("* Branch #{branch} isn't a strict subset of master, quitting")
    `git-checkout #{current} 2>/dev/null`
    exit(1)
  end
  `git-checkout #{current} 2>/dev/null` unless (current == branch)
  exit(0)
end

desc 'Create a new branch off master'
task 'git:open' => [ 'git:helpers' ] do
  newbranch = (env("NAME") or begin
    (require("readline")
    print("* Name your branch: ")
    Readline.readline.chomp)
  end)
  branch = git_branch
  if git_branches.include?(newbranch)
    if newbranch == branch
      puts(%{* Already on branch "#{newbranch}"})
    else
      puts(%{* Switching to existing branch "#{newbranch}"})
      git_checkout newbranch
    end
    exit(0)
  end
  unless (branch == "master") then
    puts("* Switching to master")
    git_checkout 'master'
  end
  `git-checkout -b #{newbranch}`
  unless $?.exitstatus.zero? then
    puts("* Couldn't create branch #{newbranch}, switching back to #{branch}")
    git_checkout branch
    exit(1)
  end
  exit(0)
end

desc 'Merge the current branch into the master branch.'
task 'git:fold' => [ 'git:helpers' ] do
  branch = git_branch
  if (branch == "master") then
    $stderr.puts("* Cannot fold master branch")
    exit(1)
  end
  puts("* Switching to master")
  `git-checkout master 2>/dev/null`
  puts("* Merging #{branch}")
  system("git-merge #{@merge_flags} #{branch}")
  if ($?.exitstatus == 1) then
    $stderr.puts("* Merge had errors -- see to your friend")
    exit(1)
  end
  puts("* Switching to #{branch}")
  `git-checkout #{branch} 2>/dev/null`
end

desc 'Squash the current branch into the master branch.'
task 'git:squash' do
  @merge_flags = "--squash"
  Rake::Task["git:fold"].invoke
end

desc 'Update all branches'
task 'git:update:all' => [ 'git:helpers' ] do
  git_stash do
    branch = git_branch
    switch = true
    git_branches.each do |b|
      puts("* Updating branch #{b}")
      begin
        git_rebase(b)
      rescue GitRebaseError => e
        puts("* Couldn't rebase #{b}, aborting so you can clean it up")
        switch = false
        break
      end
    end
    `git-checkout #{branch} 2>/dev/null` if switch
  end
end

desc 'Converts an existing Subversion Repo into a Git Repository'
task 'git:ify' do
  # Make sure we're in an svn repo
  unless File.directory?("./.svn")
    $stderr.puts "This task can only be executed in an existing working copy! (No .svn-Folder found)"
    exit(1)
  end

  # get svn info location
  svnurl = %x(svn info).grep(/^URL:/).first.gsub('URL: ','').chomp

  # project = basename
  project = "../#{File.basename(Dir.pwd)}.git"

  puts cmd = "git svn clone #{svnurl} #{project}"

  `#{cmd}`
end
