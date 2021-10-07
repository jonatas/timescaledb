ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper.class_eval do
  def table(table_name, stream)
    super(table_name, stream)
    if hypertable=Timescale::Hypertable.find_by(hypertable_name: table_name)
      dim = hypertable.dimensions
      # TODO Build compression settings for the template:
      # #{build_compression_settings_for(hypertable)})
      stream.puts <<TEMPLATE
  create_hypertable('#{table_name}',
                    time_column: '#{dim.column_name}',
                    chunk_time_interval: '#{dim.time_interval.inspect}')
TEMPLATE
    end
  end
end

=begin
    def build_compression_settings_for(hypertable)
      return if hypertable.compression_settings.nil?
      hypertable.compression_settings.map do |settings|
        ", compress_segmentby: #{settings.segmentby_column_index},
                    compress_orderby: 'created_at',
                    compression_interval: nil)
=end
