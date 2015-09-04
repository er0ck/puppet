test_name 'SysV and Systemd Service Provider Validation'

confine :except, :platform => 'windows'
confine :except, :platform => /osx/  # covered by launchd_provider.rb
confine :except, :platform => 'solaris'
confine :except, :platform => /ubuntu-[a-u]/ # upstart covered by ticket_14297_handle_upstart.rb

package_name = {'el'     => 'httpd',
                'centos' => 'httpd',
                'fedora' => 'httpd',
                'debian' => 'apache2',
                'sles'   => 'apache2',
                'ubuntu' => 'apache2',
}

agents.each do |agent|
  platform = agent.platform.variant
  majrelease = on(agent, facter('operatingsystemmajrelease')).stdout.chomp.to_i

  if ((platform == 'debian' && majrelease == 8) || (platform == 'ubuntu' && majrelease == 15))
    skip_test 'legit failures on debian8 and ubuntu15; see: PUP-5149'
  end

  init_script_systemd = "/usr/lib/systemd/system/#{package_name[platform]}.service"
  symlink_systemd     = "/etc/systemd/system/multi-user.target.wants/#{package_name[platform]}.service"

  start_runlevels     = ["2", "3", "4", "5"]
  kill_runlevels      = ["0", "1", "6"]
  if platform == 'debian' && majrelease == 6
    start_symlink     = "S20apache2"
    kill_symlink      = "K01apache2"
  elsif platform == 'debian' && majrelease == 7
    start_symlink     = "S17apache2"
    kill_symlink      = "K01apache2"
  elsif platform == 'debian' && majrelease == 8
    start_symlink     = "S02apache2"
    kill_symlink      = "K01apache2"
  elsif platform == 'sles'   && majrelease == 10
    start_symlink     = "S13apache2"
    kill_symlink      = "K09apache2"
    start_runlevels   = ["3", "5"]
    kill_runlevels    = ["3", "5"]
  elsif platform == 'sles'   && majrelease == 11
    start_symlink     = "S11apache2"
    kill_symlink      = "K01apache2"
    start_runlevels   = ["3", "5"]
    kill_runlevels    = ["3", "5"]
  else
    start_symlink     = "S85httpd"
    kill_symlink      = "K15httpd"
  end

  manifest_uninstall_httpd = %Q{
    package { '#{package_name[platform]}':
      ensure => absent,
    }
  }
  manifest_install_httpd = %Q{
    package { '#{package_name[platform]}':
      ensure => present,
    }
  }
  manifest_httpd_enabled = %Q{
    service { '#{package_name[platform]}':
      enable => true,
    }
  }
  manifest_httpd_disabled = %Q{
    service { '#{package_name[platform]}':
      enable => false,
    }
  }

  teardown do
    apply_manifest_on(agent, manifest_uninstall_httpd)
  end

  if platform == 'fedora' && majrelease > 21
    # This is a reminder so we update the provider's defaultfor when new
    # versions of Fedora are released (then update this test)
    fail_test "Provider needs manual update to support Fedora #{majrelease}"
  end

  step "installing httpd/apache"
  apply_manifest_on(agent, manifest_install_httpd, :catch_failures => true)

  step "ensure enabling service creates the start & kill symlinks"
  is_sysV = ((platform == 'centos' || platform == 'el') && majrelease < 7) ||
              platform == 'debian' ||
             (platform == 'sles'                        && majrelease < 12)
  apply_manifest_on(agent, manifest_httpd_disabled, :catch_failures => true)
  apply_manifest_on(agent, manifest_httpd_enabled, :catch_failures => true) do
    if is_sysV
      # debian platforms using sysV put rc runlevels directly in /etc/
      on agent, "ln -s /etc/ /etc/rc.d", :accept_all_exit_codes => true
      rc_symlinks = on(agent, "find /etc/ -name *#{package_name[platform]}", :accept_all_exit_codes => true).stdout
      start_runlevels.each do |runlevel|
        assert_match("#{runlevel}.d/#{start_symlink}", rc_symlinks, "did not find #{start_symlink} in runlevel #{runlevel}")
        assert_match(/\/etc(\/rc\.d)?\/init\.d\/#{package_name[platform]}/, rc_symlinks, "did not find #{package_name[platform]} init script")
      end
      kill_runlevels.each do |runlevel|
        assert_match("#{runlevel}.d/#{kill_symlink}", rc_symlinks, "did not find #{kill_symlink} in runlevel #{runlevel}")
      end
    else
      rc_symlinks = on(agent, "ls #{symlink_systemd} #{init_script_systemd}", :accept_all_exit_codes => true).stdout
      assert_match("#{symlink_systemd}",     rc_symlinks, "did not find #{symlink_systemd}")
      assert_match("#{init_script_systemd}", rc_symlinks, "did not find #{init_script_systemd}")
    end
  end

  step "ensure disabling service removes start symlinks"
  apply_manifest_on(agent, manifest_httpd_disabled, :catch_failures => true) do
    if is_sysV
      rc_symlinks = on(agent, "find /etc/ -name *#{package_name[platform]}", :accept_all_exit_codes => true).stdout
      # sles removes rc.d symlinks
      if platform != 'sles'
        (start_runlevels + kill_runlevels).each do |runlevel|
          assert_match("#{runlevel}.d/#{kill_symlink}", rc_symlinks, "did not find #{kill_symlink} in runlevel #{runlevel}")
        end
      end
    else
      rc_symlinks = on(agent, "ls #{symlink_systemd}", :accept_all_exit_codes => true).stdout
      refute_match("#{symlink_systemd}",     rc_symlinks, "should not have found #{symlink_systemd}")
    end
  end
end
