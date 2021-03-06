
module Stella::Engine
  module LoadCreate
    extend Stella::Engine::Base
    extend Stella::Engine::Load
    extend self
    
    CREATE_THREAD_SLEEP = 0.001
    CHECK_THREAD_SLEEP = 0.0005
    
    def execute_test_plan(packages, reps=1, duration=0)
      @mode = :rolling
      
      time_started = Time.now

      (1..reps).to_a.each { |rep|
        @real_reps += 1  # Increments when duration is specified.
        Stella.stdout.info3 "*** REPETITION #{@real_reps} of #{reps} ***"
        packages.each { |package|
          if running_threads.size <= packages.size
            @threads << Thread.new do
              c, uc = package.client, package.usecase
              msg = "THREAD START: client %s: " % [c.digest.short] 
              msg << "%s:%s (rep: %d)" % [uc.desc, uc.digest.short, @real_reps]
              Stella.stdout.info4 $/, "======== " << msg
              # This thread will stay on this one track. 
              Benelux.current_track c.digest
              Benelux.add_thread_tags :usecase => uc.digest_cache
          
              Benelux.add_thread_tags :rep =>  @real_reps
              Stella::Engine::Load.rescue(c.digest_cache) {
                break if Stella.abort?
                print '.' if Stella.stdout.lev == 2
                stats = c.execute uc
              }
              Benelux.remove_thread_tags :rep
              Benelux.remove_thread_tags :usecase
            
            end
            Stella.sleep CREATE_THREAD_SLEEPx
          end
          
          if running_threads.size > @max_clients
            @max_clients = running_threads.size
          end
          
          if @mode == :rolling
            tries = 0
            while (reps > 1 || duration > 0) && running_threads.size >= packages.size
              Stella.sleep CHECK_THREAD_SLEEP
              msg = "#{running_threads.size} (max: #{@max_clients})"
              Stella.stdout.info3 "*** RUNNING THREADS: #{msg} ***"
              (tries += 1)
            end
          end
        }
        
        if @mode != :rolling && running_threads.size > 0
          args = [running_threads.size, @max_clients]
          Stella.stdout.info3 "*** WAITING FOR %d THREADS TO FINISH (max: %d) ***" % args
          @threads.each { |t| t.join } # wait
        end
        
        # If a duration was given, we make sure 
        # to run for only that amount of time.
        # TODO: do not redo if 
        # time_elapsed + usecase.mean > duration
        if duration > 0
          time_elapsed = (Time.now - time_started).to_i
          msg = "#{time_elapsed} of #{duration} (threads: %d)" % running_threads.size
          Stella.stdout.info3 "*** TIME ELAPSED: #{msg} ***"
          redo if time_elapsed <= duration 
          break if time_elapsed >= duration
        end

      }
      
      if @mode == :rolling && running_threads.size > 0
        Stella.stdout.info3 "*** WAITING FOR THREADS TO FINISH ***"
        @threads.each { |t| t.join } # wait
      end
      Stella.stdout.info2 $/, $/
    end
    
    Benelux.add_timer Stella::Engine::LoadCreate, :execute_test_plan
    
  end
end