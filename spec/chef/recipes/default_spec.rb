require 'chef_helper'

describe 'gitlab::default' do
  let(:chef_run) { ChefSpec::SoloRunner.converge('gitlab::default') }

  before do
    allow(Gitlab).to receive(:[]).and_call_original
  end

  it 'creates the user config directory' do
    expect(chef_run).to create_directory('/etc/gitlab').with(
      user: 'root',
      group: 'root',
      mode: '0775'
    )
  end

  it 'creates the var opt data config directory' do
    expect(chef_run).to create_directory('Create /var/opt/gitlab').with(
      path: '/var/opt/gitlab',
      user: 'root',
      group: 'root',
      mode: '0755'
    )
  end

  it 'creates the system gitconfig directory and file' do
    stub_gitlab_rb(omnibus_gitconfig: { system: { receive: ["fsckObjects = true"], pack: ["threads = 2"] } })

    expect(chef_run).to create_directory('/opt/gitlab/embedded/etc').with(
      user: 'root',
      group: 'root',
      mode: '0755'
    )

    expect(chef_run).to create_template('/opt/gitlab/embedded/etc/gitconfig').with(
      source: 'gitconfig-system.erb',
      variables: { gitconfig:  { "receive" => ["fsckObjects = true"], "pack" => ["threads = 2"] } },
      mode: 0755
    )
  end

  context 'when manage_etc directory management is disabled' do
    before { stub_gitlab_rb(manage_storage_directories: { enable: true, manage_etc: false } ) }

    it 'does not create the user config directory' do
      expect(chef_run).to_not create_directory('/etc/gitlab')
    end
  end
end