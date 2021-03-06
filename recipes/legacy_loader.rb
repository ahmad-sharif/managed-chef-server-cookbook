#
# Cookbook:: managed-chef-server
# Recipe:: legacy_loader
#

# need the ChefDK for the 'berks' command
include_recipe 'chefdk::default'
node.override['chefdk']['channel'] = :stable

# load directories for cookbooks, environments, and roles into the Chef server
configrb = node['mcs']['managed_user']['dir'] + '/config.rb'

# cookbooks
cbdir = node['mcs']['cookbooks']['dir']
# temp directory
cbtempdir = Chef::Config[:file_cache_path] + '/legacycookbooks'
directory cbtempdir

# untar into temp directory
Dir.foreach(cbdir) do |tarfile|
  next unless tarfile.end_with?('.tgz', '.tar.gz')
  # untar each cookbook
  execute "tar -xzf #{tarfile}" do
    cwd cbdir
    command "tar -C #{cbtempdir} -xzf #{tarfile}"
  end
end

# upload all the legacy cookbooks
ruby_block 'knife cookbook upload legacy' do
  ignore_failure true
  block do
    # from temp directory, either load the Berksfile or read the cookbook/metadata.json
    cookbooks = ''
    puts
    Dir.foreach(cbtempdir) do |cookbook|
      next if ['.', '..'].member?(cookbook)
      dir = "#{cbtempdir}/#{cookbook}"
      next unless File.directory?(dir)
      # is there a Berksfile? let's load that instead
      berksfile = dir + '/Berksfile'
      if File.exist?(berksfile)
        configjson = node['mcs']['managed_user']['dir'] + '/config.json'
        puts "berks install -b #{berksfile} -c #{configjson}"
        shell_out!("berks install -b #{berksfile} -c #{configjson}")
        puts "berks upload -b #{berksfile} -c #{configjson}"
        shell_out!("berks upload -b #{berksfile} -c #{configjson}")
      else
        json = JSON.parse(File.read(dir + '/metadata.json'))
        cookbooks += json['name'] + ' '
      end
    end
    unless cookbooks.empty?
      puts "knife cookbook upload #{cookbooks} -c #{configrb} -o #{cbtempdir}"
      shell_out!("knife cookbook upload #{cookbooks} -c #{configrb} -o #{cbtempdir}")
    end
  end
end

# clean up working directory
directory "delete #{cbtempdir}" do
  action :delete
end

# environments
envdir = node['mcs']['environments']['dir']
Dir.foreach(envdir) do |env|
  next unless env.end_with?('.rb', '.json')
  if env.end_with?('.json') # if it's .json, check the type
    json = JSON.parse(File.read(envdir + '/' + env))
    type = json['chef_type']
    next unless type.eql?('environment')
  end
  # we could make this idempotent by comparing the value on the server
  execute "knife environment from file #{env}" do
    command "knife environment from file #{env} -c #{configrb}"
    cwd envdir
  end
end

# roles
roledir = node['mcs']['roles']['dir']
Dir.foreach(roledir) do |role|
  next unless role.end_with?('.rb', '.json')
  if role.end_with?('.json') # if it's .json, check the type
    json = JSON.parse(File.read(roledir + '/' + role))
    type = json['chef_type']
    next unless type.eql?('role')
  end
  # we could make this idempotent by comparing the value on the server
  execute "knife role from file #{role}" do
    command "knife role from file #{role} -c #{configrb}"
    cwd roledir
  end
end

# data bags to be added eventually
