desc "Install the sake-git tasks (use FORCE=yes to overwrite)"
task :install do
  if ENV['FORCE'] == 'yes'
    tasks = `rake -f #{Dir.pwd}/git.rake -T`.to_a.grep(/^rake/).map {|l| l[/^rake (\S+)/, 1]}
    `sake -u #{tasks.join(' ')} 2>/dev/null`
  end
  
  exec("sake -i #{Dir.pwd}/git.rake")
end

task :default => :install