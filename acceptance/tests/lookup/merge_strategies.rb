test_name 'C99903: merge strategies' do
  require 'puppet/acceptance/environment_utils.rb'
  extend Puppet::Acceptance::EnvironmentUtils

  app_type        = File.basename(__FILE__, '.*')
  tmp_environment = mk_tmp_environment_with_teardown(master, app_type)
  fq_tmp_environmentpath  = "#{environmentpath}/#{tmp_environment}"
  tmp_environment2 = mk_tmp_environment_with_teardown(master, app_type)
  fq_tmp_environmentpath2  = "#{environmentpath}/#{tmp_environment2}"

  confdir = master.puppet('master')['confdir']
  codedir = master.puppet('master')['codedir']

  teardown do
    step "remove global hiera.yaml" do
      on(master, "rm #{confdir}/hiera.yaml")
    end
  end

  step "create global hiera.yaml and environment data" do
    create_remote_file(master, "#{confdir}/hiera.yaml", <<-HIERA)
---
:backends:
  - yaml
:yaml:
  :datadir: "/etc/puppetlabs/code/environments/%{::environment}/hieradata"
:hierarchy:
  - "host"
  - "roles"
  - "profiles"
  - "%{::operatingsystem}"
  - "%{::osfamily}"
  - "%{::kernel}"
  - "common"
:logger: console
:merge_behavior: deeper
HIERA

    on(master, "mkdir -p #{fq_tmp_environmentpath}/hieradata/")
    create_remote_file(master, "#{fq_tmp_environmentpath}/hieradata/host.yaml", <<-YAML)
---
profiles:
  webserver:
    apache:
      httpd:
        modules:
          - mpm_prefork
          - php
          - ssl
    YAML

    create_remote_file(master, "#{fq_tmp_environmentpath}/hieradata/profiles.yaml", <<-YAML)
profiles:
  webserver:
    apache:
      httpd:
        modules:
          - auth_kerb
          - authnz_ldap
          - cgid
          - php
          - status
YAML

    create_sitepp(master, tmp_environment, <<-SITE)
notify { "hiera_hash: ${hiera_hash ('profiles')['webserver']['apache']['httpd']['modules']}": }
notify { "lookup1: ${lookup ('profiles')['webserver']['apache']['httpd']['modules']}": }
notify { "lookup1b: ${lookup ({'name' => 'profiles', 'merge' => 'deep'})['webserver']['apache']['httpd']['modules']}": }
    SITE

    on(master, "chmod -R 775 #{fq_tmp_environmentpath}")
    on(master, "chmod -R 775 #{confdir}")
  end

  step "create another environment, hiera5 config and environment data: #{tmp_environment2}" do
    create_remote_file(master, "#{fq_tmp_environmentpath2}/hiera.yaml", <<-HIERA)
---
version: 5
hierarchy:
  - name: "%{environment}/host"
    data_hash: yaml_data
    path: "hieradata/host.yaml"
  - name: "%{environment}/profiles"
    data_hash: yaml_data
    path: "hieradata/profiles.yaml"
HIERA

    on(master, "mkdir -p #{fq_tmp_environmentpath2}/hieradata/")
    create_remote_file(master, "#{fq_tmp_environmentpath2}/hieradata/host.yaml", <<-YAML)
---
profiles:
  webserver:
    apache:
      httpd:
        modules:
          - mpm_prefork
          - php
          - ssl
arrayed_hash:
  - array1:
    key1: val1
    key2: val2
lookup_options:
  'profiles':
    merge:
      strategy: deep
YAML

    create_remote_file(master, "#{fq_tmp_environmentpath2}/hieradata/profiles.yaml", <<-YAML)
profiles:
  webserver:
    apache:
      httpd:
        modules:
          - auth_kerb
          - authnz_ldap
          - cgid
          - php
          - status
arrayed_hash:
  - array1:
    key1: valB
    key3: val3
lookup_options:
  'profiles':
    merge:
      strategy: deep
YAML

    create_sitepp(master, tmp_environment2, <<-SITE)
notify { "hiera_hash: ${hiera_hash ('profiles')['webserver']['apache']['httpd']['modules']}": }
notify { "lookup2: ${lookup ('profiles')['webserver']['apache']['httpd']['modules']}": }
notify { "lookup2b: ${lookup ({'name' => 'profiles', 'merge' => 'first'})['webserver']['apache']['httpd']['modules']}": }
# this doesn't look quite right, but is an artifact of deep merge combined with merge_hash_arrays and hieradata can not have arrays at top level.
notify { "lookup_arrayed_hash: ${lookup ({'name' => 'arrayed_hash', 'merge' => {'strategy' => 'deep', 'merge_hash_arrays' => true}})}": }
    SITE

    on(master, "chmod -R 775 #{fq_tmp_environmentpath2}")
  end

  with_puppet_running_on(master,{}) do
    agents.each do |agent|
      step "agent lookups #{agent.hostname}, hiera3" do
        on(agent, puppet('agent', "-t --server #{master.hostname} --environment #{tmp_environment}"),
           :accept_all_exit_codes => true) do |result|
          assert(result.exit_code == 2, "agent lookup didn't exit properly: (#{result.exit_code})")
          # hiera_hash will honor old global merge strategies, which were a bad idea
          assert_match(/hiera_hash: \[auth_kerb, authnz_ldap, cgid, php, status, mpm_prefork, ssl\]/, result.stdout,
                       "1: agent hiera_hash didn't find correct key")
          # so, lookup doesn't honor them except on a by-key or by-lookup basis
          assert_match(/lookup1: \[mpm_prefork, php, ssl\]/, result.stdout,
                       "1: agent lookup didn't find correct key")
          assert_match(/lookup1b: \[auth_kerb, authnz_ldap, cgid, php, status, mpm_prefork, ssl\]/, result.stdout,
                       "1b: agent lookup didn't find correct key")
        end
      end
      step "agent lookups #{agent.hostname}, hiera5" do
        on(agent, puppet('agent', "-t --server #{master.hostname} --environment #{tmp_environment2}"),
           :accept_all_exit_codes => true) do |result|
          assert(result.exit_code == 2, "agent lookup didn't exit properly: (#{result.exit_code})")
          assert_match(/hiera_hash: \[auth_kerb, authnz_ldap, cgid, php, status, mpm_prefork, ssl\]/, result.stdout,
                       "2: agent hiera_hash didn't find correct key")
          assert_match(/lookup2: \[auth_kerb, authnz_ldap, cgid, php, status, mpm_prefork, ssl\]/, result.stdout,
                       "2: agent lookup didn't find correct key")
          assert_match(/lookup2b: \[mpm_prefork, php, ssl\]/, result.stdout,
                       "2b: agent lookup didn't find correct key")
        end
      end
    end
  end

end
