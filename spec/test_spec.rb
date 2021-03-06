require File.expand_path '../spec_helper.rb', __FILE__

describe "The S9Y SocialCaster App" do
  include Rack::Test::Methods
  
  def app
      Sinatra::Application
  end
  
  it "responds to slash" do
    get '/'
    expect(last_response).to be_ok
  end
 
  it "responds with 404 for non-existent pages" do
    get "/nothere"
    expect(last_response).to be_not_found
  end
end
