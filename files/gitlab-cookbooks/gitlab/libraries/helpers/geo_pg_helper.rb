require_relative 'base_pg_helper'

# Helper class to interact with bundled Geo PostgreSQL instance
class GeoPgHelper < BasePgHelper
  protected

  # internal name for the service (node['gitlab'][service_name])
  def service_name
    'geo-postgresql'
  end

  # command wrapper name
  def service_cmd
    'gitlab-geo-psql'
  end
end
