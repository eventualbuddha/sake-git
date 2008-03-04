desc "This is just here for the other tasks and isn't intended for your use"
task 'git:helpers' do
  def git_branch
    `git-branch | grep \"*\"`.strip[(2..-1)]
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
  def git_fetch
    sh("git#{"-svn" if git_svn?} fetch")
  end
  def git_rebase(what = nil)
    if git_svn? then
      sh("git-rebase git-svn #{what}")
    else
      sh("git-rebase origin/master #{what}")
    end
  end
  def git_push
    git_svn? ? (sh("git-svn dcommit")) : (sh("git-push"))
  end
  def git_svn?
    `git-branch -a` =~ /^\s*git-svn/
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

desc 'Push local commits into the Wesabe repository'
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
  unless (branch == "master") then
    puts("* Switching to master")
    `git-checkout master`
  end
  `git-checkout -b #{newbranch}`
  unless $?.exitstatus.zero? then
    puts("* Couldn't create branch #{newbranch}, switching back to #{branch}")
    `git-checkout #{branch}`
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
      git_rebase(b)
      unless $?.exitstatus.zero? then
        puts("* Couldn't rebase #{b}, aborting so you can clean it up")
        switch = false
        break
      end
    end
    `git-checkout #{branch} 2>/dev/null` if switch
  end
end
