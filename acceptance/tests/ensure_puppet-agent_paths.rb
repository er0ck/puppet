# ensure installs and code honor new puppet-agent path spec:
# https://github.com/puppetlabs/puppet-specifications/blob/master/file_paths.md
test_name 'PUP-4033: Ensure aio path spec is honored'

step 'test configprint outputs'

# :codedir isn't configurable, so isn't in configprint/genconfig
# :environmentpath is empty by default??
config_options = [ {:name => :codedir, :posix_expected => '/etc/puppetlabs/code', :win_expected => 'unknown', :in_configprint => true},
                   {:name => :environmentpath, :posix_expected => '/etc/puppetlabs/code/environments', :win_expected => 'unknown', :in_configprint => true},
                   {:name => :hiera_config, :posix_expected => '/etc/puppetlabs/code/hiera_config', :win_expected => 'unknown', :in_configprint => true},
]
agents.each do |agent|
  config_options.each do |config_option|
    if config_option[:in_configprint]
      on(agent, puppet_agent('--configprint ' "#{config_option[:name]}"))
    end
  end
end
#:hiera_config
# hiera_data: see parser_functions/hiera/lookup_data.rb, and hiera/acceptance
#:confdir
#:rest_authconfig
#:autosign
#:binder_config
#end

#step 'test puppet genconfig entries'
#end

#step 'test puppet config paths exist'
#end

#step 'test puppet binaries exist'
#end
