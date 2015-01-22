test_name "Setup environment"

step "Ensure Git and Ruby"

require 'puppet/acceptance/install_utils'
extend Puppet::Acceptance::InstallUtils
require 'puppet/acceptance/git_utils'
extend Puppet::Acceptance::GitUtils
require 'beaker/dsl/install_utils'
extend Beaker::DSL::InstallUtils

PACKAGES = {
  :redhat => [
    'git',
    'ruby',
    # ruby json installed later via gems
  ],
  :debian => [
    ['git', 'git-core'],
    'ruby',
  ],
  :debian_ruby18 => [
    'libjson-ruby',
  ],
  :solaris_11 => [
    ['git', 'developer/versioning/git'],
  ],
  :solaris_10 => [
    'coreutils',
    'curl', # update curl to fix "CURLOPT_SSL_VERIFYHOST no longer supports 1 as value!" issue
    'git',
    'ruby19',
    'ruby19_dev',
    'gcc4core',
  ],
  :sles => [
    'gcc',
    'git',
    'ruby',
    'rubygems',
  ],
  :windows => [
    'git',
    # there isn't a need for json on windows because it is bundled in ruby 1.9
  ],
}

hosts.each do |host|
  case host['platform']
  when  /solaris-10/
    on host, 'mkdir -p /var/lib'
    on host, 'ln -sf /opt/csw/bin/pkgutil /usr/bin/pkgutil'
    on host, 'ln -sf /opt/csw/bin/gem19 /usr/bin/gem'
    on host, 'ln -sf /opt/csw/bin/git /usr/bin/git'
    on host, 'ln -sf /opt/csw/bin/ruby19 /usr/bin/ruby'
    on host, 'ln -sf /opt/csw/bin/gstat /usr/bin/stat'
    on host, 'ln -sf /opt/csw/bin/greadlink /usr/bin/readlink'
  when  /osx/
    on host, 'ln -sf /System/Library/Frameworks/Ruby.framework/Versions/2.0/usr/bin/puppet /usr/bin/puppet'
    on host, 'ln -sf /System/Library/Frameworks/Ruby.framework/Versions/2.0/usr/bin/facter /usr/bin/facter'
    on host, 'ln -sf /System/Library/Frameworks/Ruby.framework/Versions/2.0/usr/bin/hiera /usr/bin/hiera'
  end
end

install_packages_on(hosts, PACKAGES, :check_if_exists => true)

hosts.each do |host|
  case host['platform']
  when /(el-|sles)/
    step "#{host} Install json from rubygems"
    on host, 'gem install json'
  when /windows/
    arch = host[:ruby_arch] || 'x86'
    step "#{host} Selected architecture #{arch}"

    revision = if arch == 'x64'
                 '2.0.0-x64'
               else
                 '1.9.3-x86'
               end

    step "#{host} Install ruby from git using revision #{revision}"
    # TODO remove this step once we are installing puppet from msi packages
    install_from_git(host, "/opt/puppet-git-repos",
                     :name => 'puppet-win32-ruby',
                     :path => build_giturl('puppet-win32-ruby'),
                     :rev  => revision)
    on host, 'cd /opt/puppet-git-repos/puppet-win32-ruby; cp -r ruby/* /'
    on host, 'cd /lib; icacls ruby /grant "Everyone:(OI)(CI)(RX)"'
    on host, 'cd /lib; icacls ruby /reset /T'
    on host, 'cd /; icacls bin /grant "Everyone:(OI)(CI)(RX)"'
    on host, 'cd /; icacls bin /reset /T'
    on host, 'ruby --version'
    on host, 'cmd /c gem list'
  when /solaris-11/
    step "#{host} jump through hoops to install ruby19; switch back to runtime/ruby-19 after template upgrade to sol11.2"
    create_remote_file host, "/root/shutupsolaris", <<END
mail=
# Overwrite already installed instances
instance=overwrite
# Do not bother checking for partially installed packages
partial=nocheck
# Do not bother checking the runlevel
runlevel=nocheck
# Do not bother checking package dependencies (We take care of this)
idepend=nocheck
rdepend=nocheck
# DO check for available free space and abort if there isn't enough
space=quit
# Do not check for setuid files.
setuid=nocheck
# Do not check if files conflict with other packages
conflict=nocheck
# We have no action scripts.  Do not check for them.
action=nocheck
# Install to the default base directory.
basedir=default
END
    on host, 'pkgadd -a /root/shutupsolaris -d http://get.opencsw.org/now all'
    on host, '/opt/csw/bin/pkgutil -U all'
    on host, '/opt/csw/bin/pkgutil -i -y ruby19_dev'
    on host, '/opt/csw/bin/pkgutil -i -y ruby19'
    on host, 'ln -sf /opt/csw/bin/gem19 /usr/bin/gem'
    on host, 'ln -sf /opt/csw/bin/ruby19 /usr/bin/ruby'
  end
end

install_packages_on(hosts, PACKAGES, :check_if_exists => true)

# Only configure gem mirror after Ruby has been installed, but before any gems are installed.
configure_gem_mirror(hosts)

hosts.each do |host|
  case host['platform']
  when /solaris/
    step "#{host} Install json from rubygems"
    on host, 'gem install json_pure'
  end
end
