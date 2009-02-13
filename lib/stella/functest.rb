


module Stella
  class FunctionalTest
    include TestRunner
    
    
    def run(ns)
      raise "No testplan defined" unless @testplan
      
      # TODO: one thread for each of @testplan.servers
      
      puts "Running Test: #{@name}"
      puts " -> type: #{self.class}"
      puts " -> testplan: #{@testplan.name}"
      
      if @testplan.proxy
        client = HTTPClient.new(@testplan.proxy.uri)
        client.set_proxy_auth(@testplan.proxy.user, @testplan.proxy.pass) if @testplan.proxy.user
      else
        client = HTTPClient.new
      end
      
      if @testplan.auth
        auth_domain = "#{@testplan.protocol}://#{@testplan.servers.first.to_s}/"
        puts "setting auth: #{@testplan.auth.user}:#{@testplan.auth.pass} @ #{auth_domain}"
        client.set_auth(auth_domain, @testplan.auth.user, @testplan.auth.pass)
      end
        
      client.set_cookie_store('/tmp/cookie.dat')
      
      request_methods = ns.methods.select { |meth| meth =~ /\d+\s[A-Z]/ }
      
      @retries = 1
      previous_methname = nil
      request_methods.each do |methname|
        @retries = 1 unless previous_methname == methname
        previous_methname = methname
        
        # We need to define the request only the first time it's run. 
        req = ns.send(methname) unless @retries > 1
        puts req
        puts
        
        uri = req.uri.is_a?(URI) ? req.uri : URI.parse(req.uri.to_s)
        uri.scheme ||= @testplan.protocol
        uri.host ||= @testplan.servers.first.host
        uri.port ||= @testplan.servers.first.port
        puts "#{req.http_method} #{uri}"
        
        query = {}.merge!(req.params)
        
        if req.http_method =~ /POST|PUT/
          query[req.body.form_param.to_s] = File.new(req.body.path) if req.body && req.body.path
          res = client.post(uri.to_s, query)
        elsif req.http_method =~ /GET|HEAD/
          res = client.get(uri.to_s, query)
          p query if @verbose > 0
        end
        
        puts "HTTP #{res.version} #{res.status} (#{res.reason})"
        
        if res && req.response.has_key?(res.status)
          response_handler_ret = req.response[res.status].call(res.header, res.body.content)
          
          if response_handler_ret.is_a?(Stella::TestPlan::ResponseHandler) && response_handler_ret.action == :repeat
            @retries ||= 1
            
            if @retries > response_handler_ret[:times]
              puts "Giving up."
              @retries = 1
              next
            else  
              puts "repeat #{@retries} of #{response_handler_ret[:times]} (sleep: #{response_handler_ret[:wait]})"
              sleep response_handler_ret[:wait]
              @retries += 1
              redo
            end
          end
        else
          puts res.body.content[0..100]
          puts '...' if res.body.content.length >= 100
        end
        
        puts
      end
      
      client.save_cookie_store
    end
  end
end




module Stella
    module DSL 
      module FunctionalTest
      attr_accessor :current_test
      
      def functest(name=:default, &define)
        @tests ||= {}
        @current_test = @tests[name] = Stella::FunctionalTest.new(name)
        define.call if define
      end
      
      def plan(testplan)
        raise "Unknown testplan, '#{testplan}'" unless @plans.has_key?(testplan)
        return unless @current_test
        @current_test.testplan = @plans[testplan]
      end
      
      def run(test=nil)
        to_run = (test.nil?) ? @tests : [@tests[test]]
        to_run.each do |t|
          t.run(self)
        end
      end
      
      def verbose(*args)
        @current_test.verbose += args.first || 1
      end
      
    end
  end
end