#
# Copyright:: Copyright (c) 2012 Opscode, Inc.
# Copyright:: Copyright (c) 2017 GitLab Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
account_helper = AccountHelper.new(node)
omnibus_helper = OmnibusHelper.new(node)

postgresql_dir = node['gitlab']['geo-postgresql']['dir']
postgresql_data_dir = node['gitlab']['geo-postgresql']['data_dir']
postgresql_data_dir_symlink = File.join(postgresql_dir, 'data')
postgresql_log_dir = node['gitlab']['geo-postgresql']['log_directory']
postgresql_socket_dir = node['gitlab']['geo-postgresql']['unix_socket_directory']
postgresql_user = account_helper.postgresql_user

pg_helper = GeoPgHelper.new(node)

directory postgresql_dir do
  owner postgresql_user
  mode '0755'
  recursive true
end

[
  postgresql_data_dir,
  postgresql_log_dir
].each do |dir|
  directory dir do
    owner postgresql_user
    mode '0700'
    recursive true
  end
end

link postgresql_data_dir_symlink do
  to postgresql_data_dir
  not_if { postgresql_data_dir == postgresql_data_dir_symlink }
end

execute "/opt/gitlab/embedded/bin/initdb -D #{postgresql_data_dir} -E UTF8" do
  user postgresql_user
  not_if { pg_helper.bootstrapped? }
end

postgresql_config = File.join(postgresql_data_dir, 'postgresql.conf')
bootstrapping = node['gitlab']['geo-postgresql']['bootstrap']
should_notify = omnibus_helper.should_notify?('geo-postgresql') && !bootstrapping

template postgresql_config do
  source 'postgresql.conf.erb'
  owner postgresql_user
  mode '0644'
  helper(:pg_helper) { pg_helper }
  variables(node['gitlab']['geo-postgresql'].to_hash)
  cookbook 'gitlab'
  notifies :restart, 'service[geo-postgresql]', :immediately if should_notify
end

pg_hba_config = File.join(postgresql_data_dir, 'pg_hba.conf')

template pg_hba_config do
  source 'pg_hba.conf.erb'
  owner postgresql_user
  mode '0644'
  variables(node['gitlab']['geo-postgresql'].to_hash)
  cookbook 'gitlab'
  notifies :restart, 'service[geo-postgresql]', :immediately if should_notify
end

template File.join(postgresql_data_dir, 'pg_ident.conf') do
  owner postgresql_user
  mode '0644'
  variables(node['gitlab']['geo-postgresql'].to_hash)
  cookbook 'gitlab'
  notifies :restart, 'service[geo-postgresql]', :immediately if should_notify
end

runit_service 'geo-postgresql' do
  down node['gitlab']['geo-postgresql']['ha']
  control(['t'])
  options({
            :log_directory => postgresql_log_dir
          }.merge(params))
  log_options node['gitlab']['logging'].to_hash.merge(node['gitlab']['geo-postgresql'].to_hash)
end

# This recipe must be ran BEFORE any calls to the binaries are made
# and AFTER the service has been defined
# to ensure the correct running version of PostgreSQL
# Only exception to this rule is "initdb" call few lines up because this should
# run only on new installation at which point we expect to have correct binaries.
include_recipe 'gitlab::postgresql-bin'

execute 'start geo-postgresql' do
  command '/opt/gitlab/bin/gitlab-ctl start geo-postgresql'
  retries 20
  unless bootstrapping
    action :nothing
  end
end

###
# Create the database, migrate it, and create the users we need, and grant them
# privileges.
###

# This template is needed to make the gitlab-geo-psql script and GeoPgHelper work
template '/opt/gitlab/etc/gitlab-geo-psql-rc' do
  owner 'root'
  group 'root'
end

pg_port = node['gitlab']['geo-postgresql']['port']
gitlab_sql_user = node['gitlab']['geo-postgresql']['sql_user']
database_name = node['gitlab']['geo-secondary']['db_database']

if node['gitlab']['geo-postgresql']['enable']
  execute "create #{gitlab_sql_user} database user" do
    command "/opt/gitlab/bin/gitlab-geo-psql -d template1 -c \"CREATE USER #{gitlab_sql_user}\""
    user postgresql_user
    # Added retries to give the service time to start on slower systems
    retries 20
    not_if { !pg_helper.is_running? || pg_helper.user_exists?(gitlab_sql_user) }
  end

  execute "create #{database_name} database" do
    command "/opt/gitlab/embedded/bin/createdb --port #{pg_port} -h #{postgresql_socket_dir} -O #{gitlab_sql_user} #{database_name}"
    user postgresql_user
    retries 30
    not_if { !pg_helper.is_running? || pg_helper.database_exists?(database_name) }
  end

  execute 'enable pg_trgm extension on geo-postgresql' do
    command "/opt/gitlab/bin/gitlab-geo-psql -d #{database_name} -c \"CREATE EXTENSION IF NOT EXISTS pg_trgm;\""
    user postgresql_user
    retries 20
    action :nothing
    not_if { !pg_helper.is_running? || pg_helper.is_slave? || pg_helper.extension_enabled?('pg_trgm', database_name) }
  end
end
