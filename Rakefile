desc "Install the sake-git tasks (use FORCE=yes to overwrite)"
task :install do
  if ENV['FORCE'] == 'yes'
    tasks = `sake -Tv #{Dir.pwd}/git.rake`.to_a.grep(/^sake/).map {|l| l[/^sake (\S+)/, 1]}
    `sake -u #{tasks.join(' ')} 2>/dev/null`
  end
  
  exec("sake -i #{Dir.pwd}/git.rake")
end

task :default => :install