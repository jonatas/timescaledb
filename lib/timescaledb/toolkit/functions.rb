require 'set'
module Timescaledb
  module Toolkit
    class Argument < Struct.new :name, :type
      def returned_by
        Functions.all.select{|f|f.result_data_type == type}
      end
    end
    # Function represents a hyperfunction from the toolkit.
    class Function
      attr_reader :name, :schema, :result_data_type

      def initialize(attributes)
        attributes.each do |key,value|
          instance_variable_set("@#{key}", value)
        end
        Functions.register(self)
      end

      def used_in(ignore=[])
        (Functions.all - ignore).select{|f|(arg=f.arguments.first) && arg.type == result_data_type}
      end

      def experimental?
        @schema=="toolkit_experimental"
      end

      def full_name
        "#{schema}.#{name}"
      end

      def arguments
        @argument_data_types
          .split(', ')
          .map{|arg|Argument.new(*arg.split(' ', 2))}
      end

      def graph ignore = []
        if used_in.empty?
          return "#{name} --> #{result_data_type}"
        end
        ignore << self
        used_in(ignore).map do |function|
          recursive = result_data_type == function.result_data_type
          str = " #{name} #{"<" if recursive}--> #{function.name}"
          if recursive
            str += "\n #{function.name} --> #{name}"
          end
          ignore << function
          str += "\n"+function.graph(ignore)
          str
        end.join("\n")
      end
    end
    module Functions
      module_function
      def [](name)
        all.find{|e|e.name == name}
      end

      def names
        all.map(&:name)
      end

      def all
        fetch unless defined?(@functions)
        @functions
      end

      def register function
        all << function
      end

      def data_types
        all.map{|e|e.result_data_type}.uniq
      end

      def graph
        all.each do |function|
          puts function.graph
        end
      end


      def fetch
        @functions = Set.new
        ActiveRecord::Base.connection.execute(<<-SQL).map(&Function.method(:new))
          SELECT
            p.proname AS name,
            np.nspname AS schema,
            pg_catalog.pg_get_function_result(p.oid) as result_data_type,
            pg_catalog.pg_get_function_arguments(p.oid) as argument_data_types
          FROM pg_catalog.pg_extension AS e
            INNER JOIN pg_catalog.pg_depend AS d ON (d.refobjid = e.oid)
            INNER JOIN pg_catalog.pg_proc AS p ON (p.oid = d.objid)
            INNER JOIN pg_catalog.pg_namespace AS ne ON (ne.oid = e.extnamespace)
            INNER JOIN pg_catalog.pg_namespace AS np ON (np.oid = p.pronamespace)
          WHERE d.deptype = 'e'
            AND extname = 'timescaledb_toolkit'
            AND proname !~ '_(in|out|trans|serialize|deserialize)'
            AND pg_catalog.pg_get_function_result(p.oid) <> 'internal'
          ORDER BY 1, 3;
        SQL
      end
    end
  end
end
