
module Stella::Engine
  module Load
    extend Stella::Engine::Base
    extend self
    
    @timers = [:do_request]
    @counts = [:response_content_size]
    @reqlog = nil
    @logdir = nil
    
    class << self
      attr_accessor :timers, :counts, :logdir
    end
    
    def run(plan, opts={})
      
      opts = process_options! plan, opts
      @threads, @max_clients, @real_reps = [], 0, 0
      
      @logdir = log_dir(plan)
      latest = File.join(File.dirname(@logdir), 'latest')
      Stella.stdout.info "Logging to #{@logdir}", $/
      
      if Stella.sysinfo.os == :unix
        File.unlink latest if File.exists? latest
        FileUtils.ln_sf File.basename(@logdir), latest
      end

      @reqlog = Stella::Logger.new log_path(plan, 'requests')
      @failog = Stella::Logger.new log_path(plan, 'requests-exceptions')
      @sumlog = Stella::Logger.new log_path(plan, 'summary')
      @optlog = Stella::Logger.new log_path(plan, 'options')
      @authlog = Stella::Logger.new log_path(plan, 'requests-auth')
      
      @syslog = Stella::Logger.new log_path(plan, 'sysinfo')
      @syslog.info(Stella.sysinfo.dump(:yaml)) and @syslog.close
      
      @plalog = Stella::Logger.new log_path(plan, 'plan')
      @plalog.info(plan.pretty.noansi) and @plalog.close
      
      
      Stella.stdout.add_template :head, '  %s: %s'
      Stella.stdout.add_template :status,  "#{$/}%s..."
      
      @sumlog.add_template :dsummary, '%20s: %8d'
      @sumlog.add_template :fsummary, '%20s: %8.2f'
      @optlog.add_template :head, '%10s: %s'
      @failog.add_template :request, '%s %s'
      
      @dumper = prepare_dumper(plan, opts)
      
      if Stella.stdout.lev > 2
        Load.timers += [:query, :connect, :socket_gets_first_byte, :get_body]
        Load.counts  = [:request_header_size, :request_content_size]
        Load.counts += [:response_headers_size, :response_content_size]
      end
      
      counts = calculate_usecase_clients plan, opts
      
      @optlog.head 'RUNID', runid(plan)
      @optlog.head 'OPTIONS', opts.inspect
      
      packages = build_thread_package plan, opts, counts
      
      if opts[:duration] > 0
        timing = "#{opts[:duration].seconds.to_i} seconds"
      else
        timing = "#{opts[:repetitions]} repetitions"
      end
      
      Stella.stdout.head 'Plan', "#{plan.desc} (#{plan.digest.shorter})"
      Stella.stdout.head 'Clients', counts[:total]
      Stella.stdout.head 'Limit', timing
      
      @dumper.start
      
      begin 
        @optlog.head "START", Time.now.to_s
        Stella.stdout.status "Running" 
        execute_test_plan packages, opts[:repetitions], opts[:duration], opts[:arrival]
        Stella.stdout.info $/, "Done" 
      rescue Interrupt
        Stella.stdout.nstatus "Stopping test"
        Stella.abort!
        @threads.each { |t| t.join } unless @threads.nil? || @threads.empty? # wait
      rescue => ex
        STDERR.puts "Unhandled exception: #{ex.message}"
        STDERR.puts ex.backtrace if Stella.debug? || Stella.stdout.lev >= 3
      end
      
      @optlog.head "END", Time.now.to_s
      @optlog.flush
      
      @dumper.stop
      
      Stella.stdout.status "Processing" 
      
      Benelux.update_global_timeline
      
      bt = Benelux.timeline
      tt = Benelux.thread_timeline
      
      test_time = tt.stats.group(:execute_test_plan).mean
      generate_report @sumlog, plan, test_time
      report_time = tt.stats.group(:generate_report).mean
      
      # Here is the calcualtion for the number of
      # Benelux assets created for each request:
      # 
      #     [5*2*REQ+6, 5*1*REQ+3, 13*REQ]
      # 
      
      failed = bt.stats.group(:failed).merge
      total = bt.stats.group(:do_request).merge
      
      @sumlog.info $/, "Summary: "
      @sumlog.dsummary 'successful req', total.n
      @sumlog.dsummary "failed req", failed.n
      @sumlog.dsummary "max clients", @max_clients
      @sumlog.dsummary "repetitions", @real_reps
      @sumlog.fsummary "test time", test_time
      @sumlog.fsummary "reporting time", report_time
      @sumlog.flush
      
      Stella.stdout.info File.read(@sumlog.path)
      # DNE:
      #p [@real_reps, total.n]
      
      Stella.stdout.info $/, "Log dir: #{@logdir}"
      
      failed.n == 0
    end
    
  protected
    class ThreadPackage
      attr_accessor :index
      attr_accessor :client
      attr_accessor :usecase
      def initialize(i, c, u)
        @index, @client, @usecase = i, c, u
      end
    end
    
    def prepare_dumper(plan, opts)
      Stella::Hand.new(15.seconds, 2.seconds) do
        Benelux.update_global_timeline 
        #reqlog.info [Time.now, Benelux.timeline.size].inspect
        @reqlog.info Benelux.timeline.messages.filter(:kind => :request)
        @failog.info Benelux.timeline.messages.filter(:kind => :exception)
        @failog.info Benelux.timeline.messages.filter(:kind => :timeout)
        @authlog.info Benelux.timeline.messages.filter(:kind => :authentication)
        @reqlog.clear and @failog.clear and @authlog.clear
        Benelux.timeline.clear if opts[:"disable-stats"]
      end

    end
    
    def calculate_usecase_clients(plan, opts)
      counts = { :total => 0 }
      plan.usecases.each_with_index do |usecase,i|
        count = case opts[:clients]
        when 0..9
          if (opts[:clients] % plan.usecases.size > 0) 
            msg = "Client count does not evenly match usecase count"
            raise Stella::WackyRatio, msg
          else
            (opts[:clients] / plan.usecases.size)
          end
        else
          (opts[:clients] * usecase.ratio).to_i
        end
        counts[usecase.digest_cache] = count
        counts[:total] += count
      end
      counts
    end
    
    def build_thread_package(plan, opts, counts)
      packages, pointer = Array.new(counts[:total]), 0
      plan.usecases.each do |usecase|
        count = counts[usecase.digest_cache]
        Stella.ld "THREAD PACKAGE: #{usecase.desc} (#{pointer} + #{count})"
        # Fill the thread_package with the contents of the block
        packages.fill(pointer, count) do |index|
          client = Stella::Client.new opts[:hosts].first, index+1, opts
          client.add_observer(self)
          client.enable_nowait_mode if opts[:nowait]
          Stella.stdout.info4 "Created client #{client.digest.short}"
          ThreadPackage.new(index+1, client, usecase)
        end
        pointer += count
      end
      packages.compact # TODO: Why one nil element sometimes?
    end
    
    def execute_test_plan(*args)
      raise "Override execute_test_plan method in #{self}"
    end
    
    def running_threads
      @threads.select { |t| t.status }  # non-false status are still running
    end
    
    def generate_runtime_report(plan)
      gt = Benelux.timeline
      gstats = gt.stats.group(:do_request).merge
      
      plan.usecases.uniq.each_with_index do |uc,i| 
        uc.requests.each do |req| 
          filter = [uc.digest_cache, req.digest_cache]

          Load.timers.each do |sname|
            stats = gt.stats.group(sname)[filter].merge
            #Stella.stdout.info stats.inspect
            puts [sname, stats.min, stats.mean, stats.max, stats.sd, stats.n].join('; ')
          end
          
        end
      end
      
    end
        
    def generate_report(sumlog,plan,test_time)
      global_timeline = Benelux.timeline
      global_stats = global_timeline.stats.group(:do_request).merge
      if global_stats.n == 0
        Stella.ld "No stats"
        return
      end
      
      
      
      @sumlog.info " %-72s  ".att(:reverse) % ["#{plan.desc}  (#{plan.digest_cache.shorter})"]
      plan.usecases.uniq.each_with_index do |uc,i| 
        
        # TODO: Create Ranges object, like Stats object
        # global_timeline.ranges(:do_request)[:usecase => '1111']
        # The following returns globl do_request ranges. 
        requests = 0 #global_timeline.ranges(:do_request).size
        
        desc = uc.desc || "Usecase ##{i+1} "
        desc << "  (#{uc.digest_cache.shorter}) "
        str = ' ' << " %-66s %s   %d%% ".bright.att(:reverse)
        @sumlog.info str % [desc, '', uc.ratio_pretty]
        
        uc.requests.each do |req| 
          filter = [uc.digest_cache, req.digest_cache]
          desc = req.desc 
          @sumlog.info "   %-72s ".bright % ["#{req.desc}  (#{req.digest_cache.shorter})"]
          @sumlog.info "    %s" % [req.to_s]
          Load.timers.each do |sname|
            stats = global_timeline.stats.group(sname)[filter].merge
#            Stella.stdout.info stats.inspect
            str = '      %-30s %.3f <= ' << '%.3fs' << ' >= %.3f; %.3f(SD) %d(N)'
            @sumlog.info str % [sname, stats.min, stats.mean, stats.max, stats.sd, stats.n]
            @sumlog.flush
          end
          @sumlog.info $/
        end
        
        @sumlog.info "   Sub Total:".bright
        
        stats = global_timeline.stats.group(:do_request)[uc.digest_cache].merge
        failed = global_timeline.stats.group(:failed)[uc.digest_cache].merge
        respgrp = global_timeline.stats.group(:execute_response_handler)[uc.digest_cache]
        resst = respgrp.tag_values(:status)
        statusi = []
        resst.each do |status|
          size = respgrp[:status => status].size
          statusi << "#{status}: #{size}"
        end
        @sumlog.info '      %-30s %d (%s)' % ['Total requests', stats.n, statusi.join(', ')]
        @sumlog.info '       %-29s %d' % [:success, stats.n - failed.n]
        @sumlog.info '       %-29s %d' % [:failed, failed.n]
        
        Load.timers.each do |sname|
          stats = global_timeline.stats.group(sname)[uc.digest_cache].merge
          @sumlog.info '      %-30s %.3fs %.3f(SD)' % [sname, stats.mean, stats.sd]
          @sumlog.flush
        end
        
        Load.counts.each do |sname|
          stats = global_timeline.stats.group(sname)[uc.digest_cache].merge
          @sumlog.info '      %-30s %-12s (avg:%s)' % [sname, stats.sum.to_bytes, stats.mean.to_bytes]
          @sumlog.flush
        end
        @sumlog.info $/
      end
      
      @sumlog.info ' ' << " %-66s ".att(:reverse) % 'Total:'
      
      failed = global_timeline.stats.group(:failed)
      respgrp = global_timeline.stats.group(:execute_response_handler)
      resst = respgrp.tag_values(:status)
      statusi = []
      resst.each do |status|
        size = respgrp[:status => status].size
        statusi << [status, size]
      end
      @sumlog.info  '      %-30s %d' % ['Total requests', global_stats.n]
      success = global_stats.n - failed.n
      @sumlog.info  '       %-29s %d (req/s: %.2f)' % [:success, success, success/test_time]
      statusi.each do |pair|
        @sumlog.info3 '        %-28s %s: %d' % ['', *pair]
      end
      @sumlog.info  '       %-29s %d' % [:failed, failed.n]
      
      Load.timers.each do |sname|
        stats = global_timeline.stats.group(sname).merge
        @sumlog.info '      %-30s %-.3fs     %-.3f(SD)' % [sname, stats.mean, stats.sd]
        @sumlog.flush
      end
      
      Load.counts.each do |sname|
        stats = global_timeline.stats.group(sname).merge
        @sumlog.info '      %-30s %-12s (avg:%s)' % [sname, stats.sum.to_bytes, stats.mean.to_bytes]
        @sumlog.flush
      end
    end
    
    
    def update_prepare_request(client_id, usecase, req, counter)
     
    end
      
    def update_receive_response(client_id, usecase, uri, req, params, headers, counter, container)
      args = [Time.now.to_f, Stella.sysinfo.hostname, client_id.short]
      args.push usecase.digest.shorter, req.digest.shorter
      args.push req.http_method, container.status, uri
      args << params.to_a.collect { |el| 
        next if el[0].to_s == '__stella'
        '%s=%s' % [el[0], el[1].to_s] 
      }.compact.join('&') # remove skipped params
      args << headers.to_a.collect { |el|
        next if el[0].to_s == 'X-Stella-ID'
        '%s=%s' % el 
      }.compact.join('&') # remove skipped params
      args << container.unique_id[0,10]
      Benelux.thread_timeline.add_message args.join('; '), 
       :status => container.status,
       :kind => :request
      args = [client_id.shorter, container.status, req.http_method, uri, params.inspect]
      Stella.stdout.info3 '  Client-%s %3d %-6s %s %s' % args
            
    end
    
    def update_execute_response_handler(client_id, req, container)
    end
    
    def update_error_execute_response_handler(client_id, ex, req, container)
      desc = "#{container.usecase.desc} > #{req.desc}"
      if Stella.stdout.lev == 2
        Stella.stdout.print 2, '.'.color(:red)
      else
        Stella.le '  Client-%s %-45s %s' % [client_id.shorter, desc, ex.message]
        Stella.ld ex.backtrace
      end
    end
    
    def update_request_unhandled_exception(client_id, usecase, uri, req, params, ex)
      desc = "#{usecase.desc} > #{req.desc}"
      if Stella.stdout.lev == 2
        Stella.stdout.print 2, '.'.color(:red)
      else
        Stella.le '  Client-%s %-45s %s' % [client_id.shorter, desc, ex.message]
        Stella.ld ex.backtrace
      end
    end

    def update_usecase_quit client_id, msg, req, container
      args = [Time.now.to_f, Stella.sysinfo.hostname, client_id.short]
      Benelux.thread_timeline.add_count :quit, 1
      args.push [req, container.status, 'QUIT', msg, container.unique_id[0,10]]
      Benelux.thread_timeline.add_message args.join('; '), :kind => :exception
      Stella.stdout.info3 "  Client-%s     QUIT   %s" % [client_id.shorter, msg]
    end
    
    def update_request_fail client_id, msg, req, container
      args = [Time.now.to_f, Stella.sysinfo.hostname, client_id.short]
      Benelux.thread_timeline.add_count :failed, 1
      args.push [req, container.status, 'FAIL', msg, container.unique_id[0,10]]
      Benelux.thread_timeline.add_message args.join('; '), :kind => :exception
      Stella.stdout.info3 "  Client-%s     FAILED   %s" % [client_id.shorter, msg]
    end
    
    def update_request_error client_id, msg, req, container
      args = [Time.now.to_f, Stella.sysinfo.hostname, client_id.short]
      Benelux.thread_timeline.add_count :error, 1
      args.push [req, container.status, 'ERROR', msg, container.unique_id[0,10]]
      Benelux.thread_timeline.add_message args.join('; '), :kind => :exception
      if Stella.stdout.lev >= 3
        Stella.le '  Client-%s %-45s %s' % [client_id.shorter, desc, ex.message]
      end
    end
    
    def update_request_repeat client_id, counter, total, req, container
      Stella.stdout.info3 "  Client-%s     REPEAT   %d of %d" % [client_id.shorter, counter, total]
    end
    
    def update_authenticate client_id, usecase, req, kind, domain, user, pass
      args = [Time.now.to_f, Stella.sysinfo.hostname, client_id.short]
      args.push usecase.digest.shorter, req.digest.shorter
      args.push 'AUTH', kind, domain, user, pass
      Benelux.thread_timeline.add_message args.join('; '), :kind => :authentication
    end
    
    def update_request_timeout(client_id, usecase, uri, req, params, headers, counter, container)
      args = [Time.now.to_f, Stella.sysinfo.hostname, client_id.short]
      Benelux.thread_timeline.add_count :failed, 1
      args.push [uri, 'TOUT', container.unique_id[0,10]]
      Benelux.thread_timeline.add_message args.join('; '), :kind => :timeout
    end
    
    def self.rescue(client_id, &blk)
      blk.call
    rescue => ex
      Stella.le '  Error in Client-%s: %s' % [client_id.shorter, ex.message]
      Stella.ld ex.backtrace
    end
    
    Benelux.add_timer Stella::Engine::Load, :build_thread_package
    Benelux.add_timer Stella::Engine::Load, :generate_report
        
  end
end

