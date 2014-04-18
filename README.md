# S9Y-SocialCaster  
A small sinatra app to pick out entries from your S9Y instance and broadcast  
them on social media.  Here are some of the features:  

- Picks entries at random
- Allows include list by category
- Allows exclude list by category
- Allows dryrun (send_tweets: false)
- Protection via a basic security token
- Automatically shortens URLs using bitly
  
  
### Requirements
- bundler  
- access to the S9Y database
- twitter app account
- bitly developer account + [legacy] token

### Why?
- We wanted a way to send tweets on a schedule from our massive archive of content
  
### How?  

- Setup your app on Twitter
  - Register your [application with Twitter](https://dev.twitter.com/apps)
  - Give your application appropriate access (read-write)
  - Collect consumer key/secret pair for application
  - Generate access token/secret pair for your user
- Setup your bitly account
  - Login
  - Go to Settings
  - Advanced
  - Retrieve or generate your "Legacy API key"
- git clone
- copy config.yml.template to config.yml, update with your data
- bundle install
- Start the app
  - ruby ./app.rb (thin)
  - rackup (webrick)
  - bundle exec unicorn -p $PORT -c ./config/unicorn.rb (unicorn)

### TODO
- write an admin interface that uses sqlite or something for the backend
- refactor with activerecord (maybe)
- other social media sites