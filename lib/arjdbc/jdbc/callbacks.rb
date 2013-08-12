module ActiveRecord
  module ConnectionAdapters
    
    module JdbcConnectionPoolCallbacks
      
      def self.included(base)
        if base.respond_to?(:set_callback) # Rails 3 callbacks
          base.set_callback :checkin, :after, :on_checkin
          base.set_callback :checkout, :before, :on_checkout
        else
          base.checkin :on_checkin
          base.checkout :on_checkout
        end
      end

      def on_checkin
        # default implementation does nothing
      end

      def on_checkout
        # default implementation does nothing
      end
      
    end

    module JndiConnectionPoolCallbacks
      
      def self.prepare(adapter, connection)
        if adapter.is_a?(JdbcConnectionPoolCallbacks) && connection.jndi?
          adapter.extend self # extend JndiConnectionPoolCallbacks
          connection.disconnect! # disconnect initial (JNDI) connection if any
        end
      end

      def on_checkin
        disconnect!
      end

      def on_checkout
        reconnect!
      end
    end
    
  end
end
