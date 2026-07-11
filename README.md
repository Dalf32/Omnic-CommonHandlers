# Omnic - Common Handlers
A set of Handlers for Omnic which are not quite core functionality, but are widely applicable.

### Polling
Simple anonymous polling of users.

Handler: `handlers/poll_handler.rb`

Config: none

### Starboard
Allows setting a channel where messages that receive a certain number of reactions will be reposted.

Handler: `handlers/starboard_handler.rb`

Config:
```ruby
config.handlers.starboard do |starboard|
  starboard.image_extensions = %w[jpg jpeg gif bmp png]
end
```
