@spec = Gem::Specification.new do |s|
  s.name = "stella"
  s.rubyforge_project = 'stella'
  s.version = "0.7.0.016"
  s.summary = "Stella: Perform load tests on your web applications with beauty and brute strength."
  s.description = s.summary
  s.author = "Delano Mandelbaum"
  s.email = "delano@solutious.com"
  s.homepage = "http://solutious.com/projects/stella/"
  
  s.extra_rdoc_files = %w[README.rdoc LICENSE.txt CHANGES.txt]
  s.has_rdoc = true
  s.rdoc_options = ["--line-numbers", "--title", s.summary, "--main", "README.rdoc"]
  s.require_paths = %w[lib]
  
  s.executables = %w[stella]
  
  s.add_dependency 'benelux',    '>= 0.4.3'
  s.add_dependency 'drydock',    '>= 0.6.8'
  s.add_dependency 'gibbler',    '>= 0.7.0'
  s.add_dependency 'sysinfo',    '>= 0.7.0'
  s.add_dependency 'storable',   '>= 0.5.8'
  s.add_dependency 'nokogiri'
  
  # = MANIFEST =
  # git ls-files
  s.files = %w(
  CHANGES.txt
  LICENSE.txt
  README.rdoc
  Rakefile
  Rudyfile
  bin/stella
  examples/cookies/plan.rb
  examples/essentials/logo.png
  examples/essentials/plan.rb
  examples/essentials/search_terms.csv
  examples/exceptions/plan.rb
  lib/stella.rb
  lib/stella/cli.rb
  lib/stella/client.rb
  lib/stella/client/container.rb
  lib/stella/client/modifiers.rb
  lib/stella/config.rb
  lib/stella/data.rb
  lib/stella/data/http.rb
  lib/stella/data/http/body.rb
  lib/stella/data/http/request.rb
  lib/stella/data/http/response.rb
  lib/stella/engine.rb
  lib/stella/engine/functional.rb
  lib/stella/engine/load.rb
  lib/stella/engine/stress.rb
  lib/stella/exceptions.rb
  lib/stella/guidelines.rb
  lib/stella/mixins.rb
  lib/stella/mixins/numeric.rb
  lib/stella/mixins/thread.rb
  lib/stella/stats.rb
  lib/stella/testplan.rb
  lib/stella/testplan/stats.rb
  lib/stella/testplan/usecase.rb
  lib/stella/utils.rb
  lib/stella/utils/httputil.rb
  lib/stella/version.rb
  lib/threadify.rb
  stella.gemspec
  support/sample_webapp/app.rb
  support/sample_webapp/config.ru
  support/useragents.txt
  tryouts/01_numeric_mixins_tryouts.rb
  vendor/httpclient-2.1.5.2/httpclient.rb
  vendor/httpclient-2.1.5.2/httpclient/auth.rb
  vendor/httpclient-2.1.5.2/httpclient/cacert.p7s
  vendor/httpclient-2.1.5.2/httpclient/cacert_sha1.p7s
  vendor/httpclient-2.1.5.2/httpclient/connection.rb
  vendor/httpclient-2.1.5.2/httpclient/cookie.rb
  vendor/httpclient-2.1.5.2/httpclient/http.rb
  vendor/httpclient-2.1.5.2/httpclient/session.rb
  vendor/httpclient-2.1.5.2/httpclient/ssl_config.rb
  vendor/httpclient-2.1.5.2/httpclient/timeout.rb
  vendor/httpclient-2.1.5.2/httpclient/util.rb
  )

  
end
