test_name 'C99980: eyaml backend and extension config' do
  require 'puppet/acceptance/environment_utils.rb'
  extend Puppet::Acceptance::EnvironmentUtils
  require 'puppet/acceptance/common_utils'
  extend Puppet::Acceptance::CommandUtils

  app_type        = File.basename(__FILE__, '.*')
  tmp_environment = mk_tmp_environment_with_teardown(master, app_type + '1')
  fq_tmp_environmentpath  = "#{environmentpath}/#{tmp_environment}"
  tmp_environment2 = mk_tmp_environment_with_teardown(master, app_type + '2')
  fq_tmp_environmentpath2  = "#{environmentpath}/#{tmp_environment2}"

  private_key_pem_path = "/tmp/keys/private_key.pkcs7.pem"
  public_key_pem_path = "/tmp/keys/public_key.pkcs7.pem"

  teardown do
    step 'delete eyaml encryption keys' do
      on(master, "rm -f #{private_key_pem_path} #{public_key_pem_path}")
    end
    #step 'uninstall eyaml gem' do
      #on(master, "#{gem_command(master)} uninstall hiera-eyaml")
      #on(master, "#{master['privatebindir']}/../../bin/puppetserver gem uninstall hiera-eyaml")
    #end
  end

  test_hiera_encrypted = ''
  test_lookup_encrypted = ''
  a_encrypted = ''
  step 'install hiera-eyaml gem' do
    on(master, "#{gem_command(master)} install hiera-eyaml")
    on(master, "#{master['privatebindir']}/../../bin/puppetserver gem install hiera-eyaml")
    step 'generate keys' do
      on(master, 'mkdir -p /tmp/keys')
      on(master, "#{master['privatebindir']}/eyaml createkeys --pkcs7-private-key=#{private_key_pem_path} --pkcs7-public-key=#{public_key_pem_path}")
      on(master, 'chown -R puppet:puppet /tmp/keys')
    end
    step 'encrypt our data' do
      encrypt_keys = "--pkcs7-private-key=#{private_key_pem_path} --pkcs7-public-key=#{public_key_pem_path}"
      quoted_a = '"a"'
      test_hiera_encrypted = on(master, "#{master['privatebindir']}/eyaml encrypt -s 'test value with hiera interpolation %{hiera(#{quoted_a})}' #{encrypt_keys}").stdout.match(/ENC\[.*\]/)
      test_lookup_encrypted = on(master, "#{master['privatebindir']}/eyaml encrypt -s 'test value with hiera interpolation %{lookup(#{quoted_a})}' #{encrypt_keys}").stdout.match(/ENC\[.*\]/)
      a_encrypted = on(master, "#{master['privatebindir']}/eyaml encrypt -s 'a_value' #{encrypt_keys}").stdout.match(/ENC\[.*\]/)
    end
  end

  step 'create environment hiera3 config with eyaml backend, extension: "yaml"' do
    create_remote_file(master, "#{fq_tmp_environmentpath}/hiera.yaml", <<-HIERA)
---
:backends:
  - yaml
:hierarchy:
  - "ssenvironment/%{::osfamily}/%{::ssenvironment}"
  - "common"
:yaml:
  :datadir:
HIERA
    on(master, "chown puppet:puppet #{fq_tmp_environmentpath}/hiera.yaml")
  end

  common_yaml = <<-YAML
---
enclair: "i see you"
test_hiera: '#{test_hiera_encrypted}'
test_lookup: '#{test_lookup_encrypted}'
a: '#{a_encrypted}'
YAML

  step 'create environment hieradata with interpolated hiera() and lookup() calls' do
    on(master, "mkdir -p #{fq_tmp_environmentpath}/hieradata/")
    create_remote_file(master, "#{fq_tmp_environmentpath}/hieradata/common.yaml", common_yaml)
  end

  def site_pp(env_num = 1)
    return <<-SITE
notify { "lookup_clair#{env_num}: ${lookup('enclair')}": }
notify { "a#{env_num}: ${lookup('a')}": }
notify { "lookup#{env_num}: ${lookup('test_lookup')}": }
notify { "hiera#{env_num}: ${hiera('test_hiera')}": }
notify { "lookup_hiera#{env_num}: ${lookup('test_hiera')}": }
notify { "hiera_lookup#{env_num}: ${hiera('test_lookup')}": }
notify { "lookup_y#{env_num}: ${lookup('test_lookup_y')}": }
    SITE
  end

  step 'create site.pp with hiera and lookup calls in notify resources' do
    create_sitepp(master, tmp_environment, site_pp(1))
  end

  on(master, "chmod -R 775 #{fq_tmp_environmentpath}")

  step 'create environment hiera5 config with eyaml backend' do
    # extensions are required in paths in hiera5
    create_remote_file(master, "#{fq_tmp_environmentpath2}/hiera.yaml", <<-HIERA)
---
version: 5
hierarchy:
  - name: "common"
    lookup_key: eyaml_lookup_key
    datadir: hieradata
    path: "common.yaml"
    options:
      pkcs7_private_key: "#{private_key_pem_path}"
      pkcs7_public_key: "#{public_key_pem_path}"
  - name: "other"
    data_hash: yaml_data
    datadir: hieradata
    path: "other.yaml"
HIERA

  step 'create environment2 hieradata with interpolated hiera() and lookup() calls' do
    on(master, "mkdir -p #{fq_tmp_environmentpath2}/hieradata/")
    create_remote_file(master, "#{fq_tmp_environmentpath2}/hieradata/common.yaml", common_yaml)
  end

  step 'create environment2 yaml hieradata with interpolated hiera() and lookup() calls' do
    create_remote_file(master, "#{fq_tmp_environmentpath2}/hieradata/other.yaml", <<-OTHER)
---
test_hiera_y: 'test %{hiera(a_y)}'
test_lookup_y: 'test %{lookup("a_y")}'
a_y: 'a yaml value'
    OTHER
  end

  step 'create site.pp 2 with hiera and lookup calls in notify resources' do
    create_sitepp(master, tmp_environment2, site_pp(2))
  end

  on(master, "chmod -R 775 #{fq_tmp_environmentpath2}")
  end

  with_puppet_running_on(master,{}) do
    agents.each do |agent|
      #step "agent lookups #{agent.hostname}, hiera3" do
        #on(agent, puppet('agent', "-t --server #{master.hostname} --environment #{tmp_environment}"),
           #:accept_all_exit_codes => true) do |result|
          #assert(result.exit_code == 2, "agent lookup didn't exit properly: (#{result.exit_code})")
          #assert_match(/lookup1: interpolation a_value/, result.stdout,
                       #"lookup lookup 1 interpolation in hiera3 eyaml didn't work")
          #assert_match(/hiera1: interpolation a_value/, result.stdout,
                       #"hiera hiera 1 interpolation in hiera3 eyaml didn't work")
          #assert_match(/lookup_hiera1: interpolation a_value/, result.stdout,
                       #"lookup hiera 1 interpolation in hiera3 eyaml didn't work")
          #assert_match(/hiera_lookup1: interpolation a_value/, result.stdout,
                       #"hiera lookup 1 interpolation in hiera3 eyaml didn't work")
        #end
      #end
      step "agent lookups #{agent.hostname}, hiera5" do
        on(agent, puppet('agent', "-t --server #{master.hostname} --environment #{tmp_environment2}"),
           :accept_all_exit_codes => true) do |result|
          assert(result.exit_code == 2, "agent lookup didn't exit properly: (#{result.exit_code})")
          assert_match(/lookup2: interpolation a_value/, result.stdout,
                       "lookup lookup 2 interpolation in hiera5 eyaml didn't work")
          assert_match(/hiera2: interpolation a_value/, result.stdout,
                       "hiera hiera 2 interpolation in hiera5 eyaml didn't work")
          assert_match(/lookup_hiera2: interpolation a_value/, result.stdout,
                       "lookup hiera 2 interpolation in hiera5 eyaml didn't work")
          assert_match(/hiera_lookup2: interpolation a_value/, result.stdout,
                       "hiera lookup 2 interpolation in hiera5 eyaml didn't work")
        end
      end
    end
  end

end
