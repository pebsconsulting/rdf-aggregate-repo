source "https://rubygems.org"

gemspec

group :debug do
  gem "wirble"
  gem "redcarpet",  platforms: :ruby
  gem "byebug",     platforms: :mri_21
end

group :test do
  gem "rake"
end

platforms :rbx do
  gem 'rubysl', '~> 2.0'
  gem 'rubinius', '~> 2.0'
end

