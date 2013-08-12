ArJdbc::ConnectionMethods.module_eval do
  def derby_connection(config)
    begin
      require 'jdbc/derby'
      ::Jdbc::Derby.load_driver(:require) if defined?(::Jdbc::Derby.load_driver)
    rescue LoadError # assuming driver.jar is on the class-path
    end

    config[:url] ||= "jdbc:derby:#{config[:database]};create=true"
    config[:driver] ||= defined?(::Jdbc::Derby.driver_name) ? ::Jdbc::Derby.driver_name : 'org.apache.derby.jdbc.EmbeddedDriver'
    config[:adapter_spec] ||= ::ArJdbc::Derby
    config[:connection_alive_sql] ||= 'SELECT 1 FROM SYS.SYSSCHEMAS FETCH FIRST 1 ROWS ONLY' # FROM clause is mandatory
    
    connection = embedded_driver(config)
    md = connection.jdbc_connection.meta_data
    if md.database_major_version < 10 || (md.database_major_version == 10 && md.database_minor_version < 5)
      raise ::ActiveRecord::ConnectionFailed, "Derby adapter requires Derby 10.5 or later"
    end
    connection
  end
  alias_method :jdbcderby_connection, :derby_connection
end
