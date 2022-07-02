class PG::Statement < ::DB::Statement
  def initialize(connection, command : String)
    super(connection, command)
  end

  protected def conn
    connection.as(Connection).connection
  end

  protected def perform_query(args : Enumerable) : ResultSet
    send_query args
    ResultSet.new(self, receive_fields)
  rescue IO::Error
    raise DB::ConnectionLost.new(connection)
  end

  protected def perform_exec(args : Enumerable) : ::DB::ExecResult
    result = perform_query(args)
    result.each { }
    ::DB::ExecResult.new(
      rows_affected: result.rows_affected,
      last_insert_id: 0_i64 # postgres doesn't support this
    )
  rescue IO::Error
    raise DB::ConnectionLost.new(connection)
  end

  protected def send_query(args)
    params = args.map { |arg| PQ::Param.encode(arg) }
    conn.send_parse_message(command)
    conn.send_bind_message params
    conn.send_describe_portal_message
    conn.send_execute_message
    conn.send_sync_message
  end

  protected def receive_fields
    conn.flush
    conn.expect_frame PQ::Frame::ParseComplete
    conn.expect_frame PQ::Frame::BindComplete
    frame = conn.read
    case frame
    when PQ::Frame::RowDescription
      fields = frame.fields
    when PQ::Frame::NoData
      fields = nil
    else
      raise "expected RowDescription or NoData, got #{frame}"
    end
  end

  end
end
