require "bundler/setup"
require "rake"
Bundler.require(:default)

require "action_mailbox"

spec = Gem::Specification.find_by_name("actionmailbox")
load "#{spec.gem_dir}/lib/tasks/ingress.rake"
