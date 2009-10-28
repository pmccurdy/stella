
module Stella::Engine
  module Functional
    extend Stella::Engine::Base
    extend self
    
    def run(plan, opts={})
      opts = process_options! plan, opts
      
      Stella.ld "OPTIONS: #{opts.inspect}"
      Stella.li2 "Hosts: " << opts[:hosts].join(', ') if !opts[:hosts].empty?
      
      client = Stella::Client.new opts[:hosts].first
      client.add_observer(self)

      client.enable_nowait_mode if opts[:nowait]
      
      Stella.li2 $/, "Starting test...", $/
      Stella.lflush
      sleep 0.3
      
      dig = Stella.loglev > 1 ? plan.digest_cache : plan.digest_cache.shorter
      Stella.li " %-65s  ".att(:reverse) % ["#{plan.desc}  (#{dig})"]
      plan.usecases.each_with_index do |uc,i|
        desc = (uc.desc || "Usecase ##{i+1}")
        dig = Stella.loglev > 1 ? uc.digest_cache : uc.digest_cache.shorter
        Stella.li ' %-65s '.att(:reverse).bright % ["#{desc}  (#{dig}) "]
        Stella.rescue { client.execute uc }
      end
      
      #Benelux.update_all_track_timelines
      #tl = Benelux.timeline
      
      # errors?
      
    end
    
    
    def update_prepare_request(client_id, usecase, req, counter)
      notice = "repeat: #{counter-1}" if counter > 1
      dig = Stella.loglev > 1 ? req.digest_cache : req.digest_cache.shorter
      desc = "#{req.desc}  (#{dig}) "
      Stella.li2 "  %-46s %16s ".bright % [desc, notice]
    end
    
    def update_receive_response(client_id, usecase, uri, req, params, counter, container)
      msg = '  %-6s %-53s ' % [req.http_method, uri]
      msg << container.status.to_s if Stella.loglev == 1
      Stella.li msg
      
      Stella.li2 $/, "   Params:"
      params.each do |pair|
        Stella.li2 "     %s: %s" % pair
      end
      
      Stella.li2 $/, '   ' << container.response.request.header.send(:request_line)
      
      container.response.request.header.all.each do |pair|
        Stella.li2 "   %s: %s" % pair
      end
      
      if req.http_method == 'POST'
        cont = container.response.request.body.content
        if String === cont
          Stella.li2 ('   ' << cont.split($/).join("#{$/}    "))
        elsif HTTP::Message::Body::Parts === cont
          cont.parts.each do |part|
            if File === part
              Stella.li2 "<#{part.path}>"
            else
              Stella.li2 part
            end
          end
        end
      end
      
      resh = container.response.header
      Stella.li2 $/, '   HTTP/%s %3d %s' % [resh.http_version, resh.status_code, resh.reason_phrase]
      container.headers.all.each do |pair|
        Stella.li2 "   %s: %s" % pair
      end
      Stella.li4 container.body.empty? ? '   [empty]' : container.body
      Stella.li2 $/
    end
    
    def update_execute_response_handler(client_id, req, container)
    end
    
    def update_error_execute_response_handler(client_id, ex, req, container)
      Stella.le ex.message
      Stella.ld ex.backtrace
    end
    
    def update_request_error(client_id, usecase, uri, req, params, ex)
      desc = "#{usecase.desc} > #{req.desc}"
      Stella.le '  Client-%s %-45s %s' % [client_id.short, desc, ex.message]
      Stella.ld ex.backtrace
    end
    
    def update_quit_usecase client_id, msg
      Stella.li "  QUIT   %s" % [msg]
    end
    
    
    def update_repeat_request client_id, counter, total
      Stella.li4 "  Client-%s     REPEAT   %d of %d" % [client_id.shorter, counter, total]
    end
    
  end
end

__END__


$ stella verify -p examples/basic/plan.rb http://localhost:3114
$ stella load -p examples/basic/plan.rb http://localhost:3114
$ stella remote-load -p examples/basic/plan.rb http://localhost:3114
$ stella remote-verify -p examples/basic/plan.rb http://localhost:3114

