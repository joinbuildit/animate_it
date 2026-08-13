# Dependency sets the CI matrix + `bundle exec appraisal <name> rspec` run
# against. The gem supports Rails >= 7.2; these pin the two we actively test.
appraise "rails-7.2" do
  gem "rails", "~> 7.2.0", ">= 7.2.3.2"
end

appraise "rails-8.1" do
  gem "rails", "~> 8.1.0", ">= 8.1.3.1"
end
