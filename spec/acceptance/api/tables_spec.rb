require File.expand_path(File.dirname(__FILE__) + '/../acceptance_helper')

feature "Tables JSON API" do

  background do
    Capybara.current_driver = :rack_test
  end

  scenario "Retrieve different pages of rows from a table" do
    user = create_user
    table = create_table :user_id => user.id

    100.times do
      table.execute_sql("INSERT INTO \"#{table.name}\" (Name,Location,Description) VALUES ('#{String.random(10)}','#{Point.from_x_y(rand(10.0), rand(10.0)).as_ewkt}','#{String.random(100)}')")
    end

    content = table.execute_sql("select * from \"#{table.name}\"")

    authenticate_api user

    get_json "/api/json/tables/#{table.id}?rows_per_page=2"
    response.status.should == 200
    json_response = JSON(response.body)
    json_response['total_rows'].should == 100
    json_response['rows'][0].symbolize_keys.should == content[0]
    json_response['rows'][1].symbolize_keys.should == content[1]

    get_json "/api/json/tables/#{table.id}?rows_per_page=2&page=1"
    response.status.should == 200
    json_response = JSON(response.body)
    json_response['rows'][0].symbolize_keys.should == content[2]
    json_response['rows'][1].symbolize_keys.should == content[3]
  end

  scenario "Update the privacy status of a table" do
    user = create_user
    table = create_table :user_id => user.id, :privacy => Table::PRIVATE

    table.should be_private

    authenticate_api user

    put_json "/api/json/tables/#{table.id}/toggle_privacy"
    response.status.should == 200
    json_response = JSON(response.body)
    json_response['privacy'].should == 'PUBLIC'
    table.reload.should_not be_private

    put_json "/api/json/tables/#{table.id}/toggle_privacy"
    response.status.should == 200
    json_response = JSON(response.body)
    json_response['privacy'].should == 'PRIVATE'
    table.reload.should be_private
  end

  scenario "Update the name of a table" do
    user = create_user
    old_table = create_table :user_id => user.id, :privacy => Table::PRIVATE, :name => 'Old table'
    table = create_table :user_id => user.id, :privacy => Table::PRIVATE

    authenticate_api user

    put_json "/api/json/tables/#{table.id}/update", {:name => "My brand new name"}
    response.status.should == 200
    table.reload
    table.name.should == "My brand new name"

    put_json "/api/json/tables/#{table.id}/update", {:name => ""}
    response.status.should == 400
    json_response = JSON(response.body)
    json_response['errors'].should == ["name can't be blank"]
    table.reload
    table.name.should == "My brand new name"

    put_json "/api/json/tables/#{table.id}/update", {:name => "Old table"}
    response.status.should == 400
    json_response = JSON(response.body)
    json_response['errors'].should == ["name and user_id is already taken"]
    table.reload
    table.name.should == "My brand new name"
  end

  scenario "Update the tags of a table" do
    user = create_user
    table = create_table :user_id => user.id

    authenticate_api user

    put_json "/api/json/tables/#{table.id}/update", {:tags => "tag1, tag2, tag3"}
    response.status.should == 200
    Tag.count.should == 3
    tags = Tag.filter(:user_id => user.id, :table_id => table.id).all
    tags.size.should == 3
    tags.map(&:name).sort.should == %W{ tag1 tag2 tag3 }

    put_json "/api/json/tables/#{table.id}/update", {:tags => ""}
    response.status.should == 200
    Tag.count.should == 0
  end

  scenario "Get the schema of a table" do
    user = create_user
    table = create_table :user_id => user.id

    authenticate_api user

    get_json "/api/json/tables/#{table.id}/schema"
    response.status.should == 200
    json_response = JSON(response.body)
    json_response.should == [["id", "integer"], ["name", "text"], ["location", "geometry"], ["description", "text"]]
  end

  scenario "Get a list of tables" do
    user = create_user

    authenticate_api user

    get_json "/api/json/tables"
    response.status.should == 200
    JSON(response.body).should == []

    table1 = create_table :user_id => user.id, :name => 'My table #1', :privacy => Table::PUBLIC
    table2 = create_table :user_id => user.id, :name => 'My table #2', :privacy => Table::PRIVATE
    get_json "/api/json/tables"
    response.status.should == 200
    response.body.should == [
      {
        "id" => table1.id,
        "name" => "My table #1",
        "privacy" => "PUBLIC"
      },
      {
        "id" => table2.id,
        "name" => "My table #2",
        "privacy" => "PRIVATE"
      }
    ].to_json
  end

  scenario "Modify the schema of a table" do
    user = create_user
    table = create_table :user_id => user.id

    authenticate_api user

    put_json "/api/json/tables/#{table.id}/update_schema", {
                                                              :what => "add", :column => {
                                                                  :type => "integer", :name => "postal code"
                                                              }
                                                           }
    response.status.should == 200
    table.reload
    table.schema.should == [[:id, "integer"], [:name, "text"], [:location, "geometry"], [:description, "text"], [:"postal code", "integer"]]

    put_json "/api/json/tables/#{table.id}/update_schema", {
                                                              :what => "modify", :column => {
                                                                  :type => "text", :name => "postal code"
                                                              }
                                                           }
    response.status.should == 200
    table.reload
    table.schema.should == [[:id, "integer"], [:name, "text"], [:location, "geometry"], [:description, "text"], [:"postal code", "text"]]

    put_json "/api/json/tables/#{table.id}/update_schema", {
                                                              :what => "add", :column => {
                                                                  :type => "integerrrr", :name => "no matter what"
                                                              }
                                                           }
    response.status.should == 400
    json_response = JSON(response.body)
    json_response['errors'].should == ["PGError: ERROR:  type \"integerrrr\" does not exist"]

    put_json "/api/json/tables/#{table.id}/update_schema", {
                                                              :what => "drop", :column => {
                                                                :name => "postal code"
                                                              }
                                                           }
    response.status.should == 200
    table.reload
    table.schema.should == [[:id, "integer"], [:name, "text"], [:location, "geometry"], [:description, "text"]]

    put_json "/api/json/tables/#{table.id}/update_schema", {
                                                              :what => "drop", :column => {
                                                                :name => "postal code"
                                                              }
                                                           }
    response.status.should == 400
    table.reload
    json_response = JSON(response.body)
    json_response['errors'].should == ["PGError: ERROR:  column \"postal code\" of relation \"#{table.name}\" does not exist"]

    put_json "/api/json/tables/#{table.id}/update_schema", {
                                                              :what => "wadus", :column => {
                                                                :name => "postal code"
                                                              }
                                                           }
    response.status.should == 400
    table.reload
    json_response = JSON(response.body)
    json_response['errors'].should == ["what parameter has an invalid value"]

    put_json "/api/json/tables/#{table.id}/update_schema", {
                                                              :what => "add", :column => {}
                                                           }
    response.status.should == 400
    table.reload
    json_response = JSON(response.body)
    json_response['errors'].should == ["column parameter can't be blank"]
  end

  scenario "Insert a new row in a table" do
    user = create_user
    table = create_table :user_id => user.id

    authenticate_api user

    post_json "/api/json/tables/#{table.id}/rows", { :name => "Name 123", :description => "The description", :location => Point.from_x_y(1,1).as_ewkt }
    response.status.should == 200
    table.reload
    table.rows_count.should == 1
    table.to_json[:total_rows].should == 1
  end

  scenario "Update the value from a ceil" do
    user = create_user
    table = create_table :user_id => user.id

    authenticate_api user

    table.insert_row!({:name => String.random(12)})

    row = table.to_json(:rows_per_page => 1, :page => 0)[:rows].first
    row[:description].should be_blank

    put_json "/api/json/tables/#{table.id}/rows/#{row[:id]}", {:description => "Description 123"}
    response.status.should == 200
    table.reload
    row = table.to_json(:rows_per_page => 1, :page => 0)[:rows].first
    row[:description].should == "Description 123"
  end

end