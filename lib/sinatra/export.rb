require 'sinatra/base'
require 'sinatra/advanced_routes'
require 'rack/test'
require 'pathname'
require 'thread' # for Queue
require_relative 'export/page.rb'

module Sinatra

  # Export a Sinatra app to static files!
  module Export

    # required for all Sinatra Extensions, see http://www.sinatrarb.com/extensions.html
    def self.registered(app)
      if app.extensions.nil? or !app.extensions.include?(Sinatra::AdvancedRoutes)
        app.register Sinatra::AdvancedRoutes
      end
      app.set :export_extensions, %w(css js xml json html csv)
      app.extend ClassMethods
      app.set :builder, nil
    end

    # These will get extended onto the Sinatra app
    module ClassMethods

      # The entry method. Run this to export the app to files.
      # @example
      #   # The default: Will use the paths from Sinatra Namespace
      #   app.export!
      #
      #   # Skip a path (or paths)
      #   app.export! skips: ["/admin"]
      #
      #   # Only visit the homepage and the site map
      #   app.export! paths: ["/", "/site-map"]
      #
      #   # Visit the 404 error page by supplying the expected
      #   # status code (so as not to trigger an error)
      #   app.export! paths: ["/", ["/404.html",404]]
      #
      #   # Filter out mentions of localhost:4567
      #   filter = ->(content){ content.gsub("localhost:4567, "example.org") }
      #   app.export! filters: [filter]
      #
      #   # Use routes found by Sinatra AdvancedRoutes *and*
      #   # ones supplied via `paths`
      #   app.export! paths: ["/crazy/deep/page/path"], use_routes: true
      #
      #   # Supply a path and scan the output for an internal link
      #   # adding it to the list of paths to be visited
      #   app.export! paths: "/" do |builder|
      #     if builder.last_response.body.include? "/echo-1"
      #       builder.paths << "/echo-1"
      #     end
      #   end
      #
      # @param [Array<String>,Array<URI>] paths Paths that will be requested by the exporter.
      # @param [Array<String>] skips: Paths that will be ignored by the exporter.
      # @param [TrueClass] use_routes Whether to use Sinatra AdvancedRoutes to look for paths to send to the builder.
      # @param [Array<#call>] filters Filters will be applied to every file as it is written in the order given.
      # @param [#call] error_handler Define your own error handling. Takes one argument, a description of the error.
      # @yield [builder] Gives a Builder instance to the block (see Builder) that is called for every path visited.
      # @note By default the output files with be written to the public folder. Set the EXPORT_BUILD_DIR env var to choose a different location.
      def export! paths: nil, skips: [], filters: [], use_routes: nil, error_handler: nil,  &block
        @builder ||= 
          if self.builder
            self.builder
          else
            Builder.new(self, paths: paths, skips: skips, filters: filters, use_routes: use_routes, error_handler: error_handler, &block )
          end
        @builder.build!
      end
    end

    class Builder

      # TODO check this
      # @param [Sinatra::Base] app The Sinatra app
      # @param (see ClassMethods#export!)
      # @yield [builder] Gives a Builder instance to the block (see Builder) that is called for every path visited.
      def initialize app, paths: [], skips: [], use_routes: nil, filters: [], error_handler: nil, &block
        @app = app
        Page.app = app
        @block  = block
        @paths  = Queue.new
        if paths.nil? or paths.empty?
          @paths << ["/", 200]
        else
          paths.each do |path,status=200|
            @paths << [path,status]
          end
        end

        @use_routes = paths.nil? && use_routes.nil? ? true : use_routes
        if @use_routes
          app.each_route do |route|
            next if route.verb != 'GET'
            next unless route_path_usable?(route.path)
            @paths << [route.path,200]
          end
        end
        # A hash is much faster lookup than an array.
        @skips  = Hash[
                    skips.map{|path|
                      path.end_with?("?") ?
                        path.chop :
                        path
                    }.zip [nil]
                  ]
        @pids   = {}
        @initial_workers = 4
        @workers = @initial_workers
        if filters.respond_to? :each
          filters.each {|filter| Page.filters << filter }
        else
          Page.filters << filters
        end
        @pages = {}
#         @errored  = []
        Page.error_handler = error_handler if error_handler
        @dir = Pathname( ENV["EXPORT_BUILD_DIR"] || app.public_folder )
        if @dir.exist?
          if !@dir.directory?
            fail "The output directory #{@dir} is not a directory"
          end
        else
          @dir.mkpath
        end
        Page.output_dir = @dir
      end

      attr_reader :paths, :pages

      # @!attribute [r] errored
      #   @return [Array<String>] List of paths visited by the builder that called the error handler
      attr_reader :errored

      # @!attribute paths
      # Paths to visit (see ClassMethods#export!)
      #   @return [Queue<String,URI>]
      attr_accessor :paths

      # @!attribute skips
      # Paths to be skipped (see ClassMethods#export!)
      #   @return [Array<String,URI>]
      attr_accessor :skips


      def visited
        @pages.select{|_,page| page.finished? }
              .map{|path,_| path }
      end


      def errored
        @pages.select{|_,page| page.errored? }
              .map{|path,_| path }
      end

      def app
        @app
      end
  

      def build!
        loop do
          if @block
            # reap and resume any workers
            if @workers < @initial_workers
              begin
              wpid, exit_status = Process.waitpid2(-1, Process::WNOHANG)
              rescue Errno::ECHILD
                # do nothing
              end
              if wpid
                begin
                record = @pages.find{|path,page| page.pid == wpid }
                _,page = record
                page.resume if page # This might indicate a problem
                if new_paths = page.new_paths
                  new_paths.uniq.each do |path|
                    spawn_page path
                  end
                end
                rescue IO::EAGAINWaitReadable
                  # do nothing, it's not a problem
                end
              end
            end
            @workers.times do
              if record = @pages.find{|path,page| page.milestone == :responded_to }
                _,page = record
                @workers -= 1
                page.resume
              else
                break # this little loop
              end
            end
          end

          @pages.select{|path,page|
            !(page.milestone == :processing_block ||
              page.finished? )
          }.each do |_,page|
            page.resume
          end

          until @paths.empty?
            spawn_page *@paths.pop
          end
          break if @pages.all?{|path,page| page.milestone == :finish } && @paths.empty?
        end
        self
      end

      # A convenience method to keep this logic together
      # and reusable
      # @param [String,Regexp] path
      # @return [TrueClass] Whether the path is a straightforward path (i.e. usable) or it's a regex or path with named captures / wildcards (i.e. unusable).
      def route_path_usable? path
        res = path.respond_to?( :~ )  ||  # skip regex
              path =~ /(?:\:\w+)|\*/  ||  # keys and splats
              path =~ /[\%\\]/        ||  # special chars
              path[0..-2].include?("?") # an ending ? is acceptable, it'll be chomped
        !res
      end


      def spawn_page path, status=200
        path = path.chop if path.end_with? "?"
        unless @skips.has_key? path
          @pages[path] ||= Page.new path, status: status, &@block
        end
      end

    end
  end

  register Sinatra::Export
end