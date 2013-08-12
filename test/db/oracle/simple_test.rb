require 'db/oracle'
require 'simple'

class OracleSimpleTest < Test::Unit::TestCase
  include SimpleTestMethods
  include ActiveRecord3TestMethods
  include DirtyAttributeTests
  include XmlColumnTests

  def xml_sql_type; 'XMLTYPE'; end

  # @override
  def test_insert_returns_id
    # not supported (we pre-select id values from sequences) {#test_exec_insert}
  end

  # @override
  def test_time_usec_formatting_when_saved_into_string_column
    e = DbType.create!(:sample_string => '', :sample_text => '')
    value = Time.utc 2013, 7, 2, 10, 13, 39, 0 # usec == 0
    e.sample_string = value
    e.sample_text = value
    e.save!; e.reload
    assert_match /02\-JUL\-13 10.13.39/, e.sample_string
    # assert_match /02\-JUL\-13 10.13.39/, e.sample_text
  end

  # @override
  def test_exec_insert
    name_column = Thing.columns.detect { |column| column.name.to_s == 'name' }
    created_column = Thing.columns.detect { |column| column.name.to_s == 'created_at' }
    updated_column = Thing.columns.detect { |column| column.name.to_s == 'updated_at' }
    now = Time.zone.now

    created_date = "to_date('2013/07/24 01:44:56', 'yyyy/mm/dd hh24:mi:ss')"
    updated_date = "to_date('2013/07/24 01:44:56', 'yyyy/mm/dd hh24:mi:ss')"
    connection.exec_insert "INSERT INTO things VALUES ( '01', #{created_date}, #{updated_date} )", nil, []

    binds = [ [ name_column, 'ferko' ], [ created_column, now ], [ updated_column, now ] ]
    connection.exec_insert "INSERT INTO things VALUES ( ?, ?, ? )", 'INSERT Thing(ferko)', binds
    assert Thing.find_by_name 'ferko'
    # NOTE: #exec_insert accepts 5 arguments on AR-4.0 :
    binds = [ [ name_column, 'jozko' ], [ created_column, now ], [ updated_column, now ] ]
    connection.exec_insert "INSERT INTO things (name, created_at, updated_at) VALUES (?,?,?)", 'INSERT Thing(jozko)', binds, nil, nil
    assert Thing.find_by_name 'jozko'

    result = connection.exec_insert "INSERT INTO entries(ID, TITLE) VALUES ( '4200', 'inserted-title' )", nil, []
    assert_nil result # returns no generated id

    connection.exec_insert "INSERT INTO entries(ID, TITLE) VALUES ( '4201', 'inserted-title' )", nil, [], 'ID'
  end

  # @override
  def test_execute_insert
    assert_nil connection.execute("INSERT INTO entries (ID, TITLE) VALUES (4242, 'inserted-title')")
    assert entry = Entry.find(4242)
    assert_equal 'inserted-title', entry.title
  end

  def test_default_id_type_is_integer
    user = User.create! :login => 'id_type'
    Entry.create! :title => 'first', :user_id => user.id
    assert Integer === Entry.first.id
  end

  def test_sequences_are_not_cached
    ActiveRecord::Base.transaction do
      e1 = Entry.create :title => "hello1"
      e2 = Entry.create :title => "hello2"
      assert e1.id != e2.id
    end
  end

  def test_find_by_sql_WITH_statement
    user = User.create! :login => 'ferko'
    Entry.create! :title => 'aaa', :user_id => user.id
    entries = Entry.find_by_sql '' +
      ' WITH EntryLogin (title, login) AS ' +
      ' ( ' +
      '  SELECT e.title, u.login ' +
      '  FROM entries e INNER JOIN users u ON e.user_id = u.id ' +
      ' ) ' +
      ' ' +
      ' SELECT * FROM EntryLogin ORDER BY title ASC '
    assert entries.first
    assert entries.first.title
    assert entries.first.login
  end

  # @override
  def test_exec_insert_bind_param_with_q_mark
    sql = "INSERT INTO entries(id, title) VALUES (?, ?)"
    connection.exec_insert sql, 'INSERT(with_q_mark)', [ [ nil, 1000 ], [ nil, "bar?!?" ] ]

    entries = Entry.find_by_sql "SELECT * FROM entries WHERE title = 'bar?!?'"
    assert entries.first
  end

  # @override
  def test_raw_insert_bind_param_with_q_mark
    sql = "INSERT INTO entries(id, title) VALUES (?, ?)"
    name = "INSERT(raw_with_q_mark)"
    pk = nil; id_value = 1001; sequence_name = nil
    connection.insert sql, name, pk, id_value, sequence_name, [ [ nil, id_value ], [ nil, "?!huu!?" ] ]
    assert Entry.exists?([ 'title LIKE ?', "%?!huu!?%" ])
  end if Test::Unit::TestCase.ar_version('3.1') # no binds argument for <= 3.0

  include ExplainSupportTestMethods if ar_version("3.1")

  def test_quotes_reserved_word_column
    connection.create_table 'lusers', :force => true do |t|
      t.string :file
      t.text "desc", :limit => 16777216
      t.date :'date', :null => false
    end
  ensure
    connection.drop_table('lusers') rescue nil
  end

  def test_emulates_booleans_by_default
    assert_true ArJdbc::Oracle.emulate_booleans
    # assert_true ActiveRecord::ConnectionAdapters::OracleAdapter.emulate_booleans
  end if ar_version('3.0')

  def test_boolean_emulation_can_be_disabled
    db_type = DbType.create! :sample_boolean => true
    column = DbType.columns.find { |col| col.name.to_s == 'sample_boolean' }
    assert_equal :boolean, column.type
    ArJdbc::Oracle.emulate_booleans = false

    DbType.reset_column_information
    column = DbType.columns.find { |col| col.name.to_s == 'sample_boolean' }
    assert_equal :integer, column.type

    assert_equal 1, db_type.reload.sample_boolean
  ensure
    ArJdbc::Oracle.emulate_booleans = true
    DbType.reset_column_information
  end if ar_version('3.0')

  def test_set_table_name_prefixed_with_schema
    schema = connection.config[:username]
    activity = Class.new(ActiveRecord::Base) do # class Activity
      if respond_to?(:table_name=)
        self.table_name = "#{schema}.activities"
        self.sequence_name = "#{schema}.activities_seq"
      else
        set_table_name "#{schema}.activities"
        set_sequence_name "#{schema}.activities_seq"
      end
    end
    connection.create_table(:activities) { |t| t.string :name }
    assert activity.create! :name => 'an-activity' # Activity.create! ...
  ensure
    connection.drop_table(:activities) rescue nil
  end

  test 'returns correct visitor type' do
    assert_not_nil visitor = connection.instance_variable_get(:@visitor)
    assert defined? Arel::Visitors::Oracle
    assert_kind_of Arel::Visitors::Oracle, visitor
  end if ar_version('3.0')

  protected

  def assert_empty_string value
    # An empty string is treated as a null value in Oracle :
    # http://www.techonthenet.com/oracle/questions/empty_null.php
    assert_equal nil, value
  end

  def assert_null_text value
    # Oracle adapter initializes all CLOB fields with empty_clob()
    # fn, so they all have a initial value of an empty string ''
    assert_equal '', value
  end

  def assert_date_type(value)
    # NOTE: no support for bare Date type in Oracle :
    assert_instance_of Date, value.to_date
  end

  def assert_timestamp_equal expected, actual
    e_utc = expected.utc; a_utc = actual.utc
    [ :year, :month, :day, :hour, :min, :sec ].each do |method|
      assert_equal e_utc.send(method), a_utc.send(method), "<#{expected}> but was <#{actual}> (differ at #{method.inspect})"
    end
    # Oracle does only support storing milliseconds with TIMESTAMP :
    e_usec = ( e_utc.usec / 10000.0 ).round * 10000
    a_usec = ( a_utc.usec / 10000.0 ).round * 10000
    assert_equal e_usec, a_usec, "<#{expected}> but was <#{actual}> (differ at :usec / 1000)"
  end

end
