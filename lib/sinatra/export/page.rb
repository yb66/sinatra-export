# Sync $stdout so the call to #puts in the CHLD handler isn't
# buffered. Can cause a ThreadError if a signal handler is
# interrupted after calling #puts. Always a good idea to do
# this if your handlers will be doing IO.
$stdout.sync = true

require 'term/ansicolor'

module Sinatra

  module Export
    require 'forwardable'
    class Page
      include Rack::Test::Methods
      extend Forwardable
      def_delegators :@fibre, :resume

      class ColorString < ::String
        include ::Term::ANSIColor
      end

      # Default error handler
      # @yieldparam [String] desc Description of the error.
      DEFAULT_ERROR_HANDLER = ->(desc) {
        puts Sinatra::Export::Page::ColorString.new("failed: #{desc}").red;
      }


      class << self

        # Rack/Sinatra app
        def app
          @app
        end


        def app=( app )
          @app = app
        end


        def export_extensions
          @export_extensions ||= app.settings.export_extensions
        end


        def export_extensions_pattern
          @pattern ||= %r{
            [^/\.]+
            \.
            (
              #{export_extensions.join("|")}
            )
          $}x
        end


        def error_handler
          @error_handler ||= DEFAULT_ERROR_HANDLER
        end
      

        def error_handler=( error_handler )
          @error_handler = error_handler
        end


        def output_dir= dir
          @output_dir = Pathname(dir)
        end


        def output_dir
          @output_dir
        end


        def filters
          @filters ||= []
        end


        def reset!
          @filters = []
          @output_dir = nil
          @error_handler = nil
          @pattern = nil
          @export_extensions = nil
          @app = nil
        end
      end

      def initialize path, status: 200, &block
        @path = path
        @block = block
        @milestone = :fresh
        @blocking_io = false
        @new_paths = nil
        @status = status
        @errored = false

        @fibre = Fiber.new do
          @resp = blocking_io do
            get_path
          end
          Fiber.yield milestone_got_page

          if @block
            rd, wr = IO.pipe
            @pid = fork do
              $0 = "Forked child from Page #{@path}"
              #rd.close
              result = @block.call(@resp)
              begin
              wr.write Marshal.dump(result)
              rescue Errno::EPIPE => e
                #binding.pry
                e
              end
              #exit!(0) # skips exit handlers.
            end 
            wr.close
            milestone_processing_block
            Fiber.yield
            result = Marshal.load(rd.read)
            unless result.nil? || result.empty?
              if result.first.respond_to? :uniq
                @new_paths, body = *result
                @resp.body = [body] if body
              else
                @new_paths = result
              end
            end
          end

          blocking_io do
            build_artefacts
          end
          finish
        end
        #the_block
      end


      def blocking_io *args
        @blocking_io = true
        result = yield *args
        @blocking_io = false
        result
      end

      def milestone_got_page
        @milestone = :responded_to
      end

      def milestone_processing_block
        @milestone = :processing_block
      end

      def milestone_block_done
        @milestone = :block_done
      end

      attr_reader :resp, :new_paths, :milestone, :status, :block
      attr_accessor :pid, :exit_status

      def finish
        @milestone = :finish
      end

      def finished?
        @milestone == :finish
      end

      def errored?
        @errored
      end

      def app
        self.class.app
      end

      # Wrapper around Rack::Test's `get`
      # @param [String] path
      # @param [Integer] status The expected response status code. Anything different and the error handler is called. Defaults to 200.
      # @return [Rack::MockResponse]
      def get_path
        @status ||= 200
        resp = get(@path).tap do |resp|
          handle_error_incorrect_status!(resp.status) unless resp.status == @status
        end
        resp
      end


      # Handles the error caused by a mismatch in status code expectations.
      # @param [String] path The route path.
      # @param [#to_s] expected The status code that was expected.
      # @param [#to_s] actual The actual status code received.
      def handle_error_incorrect_status!(actual=nil)
        desc = "GET #{@path} returned #{actual} status code instead of #{@status}"
        self.class.error_handler.call(desc)
        finish
        @errored = true
      end


      # Builds the output dirs and file
      # based on the response.
      # @param [String] path
      # @param [Pathname,String] dir
      # @param [Rack::MockResponse] response
      # @return [String] file_path
      # @example
      #   file_path = build_path(path: @last_path, dir: dir, response: last_response)
      def build_artefacts
        body = @resp.body
        mtime = @resp.headers.key?("Last-Modified") ?
          Time.httpdate(@resp.headers["Last-Modified"]) :
          Time.now

        file_path = Pathname( ::File.join self.class.output_dir, @path )
        file_path = file_path.join( 'index.html' ) unless  @path.match(self.class.export_extensions_pattern)
        ::FileUtils.mkdir_p( file_path.dirname )
        write_path content: body, path: file_path
        ::FileUtils.touch(file_path, :mtime => mtime)
        file_path
      end


      # Write the response to file.
      # Uses whatever filters were set, on the content.
      # @param [String] content
      # @param [Pathname,String] path
      def write_path( content: nil, path: nil )
        # These argument checks are for Ruby v2.0 as it
        # doesn't support required keyword args.
        fail ArgumentError, "'content' is a required argument to write_path" if content.nil?
        fail ArgumentError, "'path' is a required argument to write_path" if path.nil?

        unless self.class.filters.empty?
          content = self.class.filters.inject(content) do |current_content,filter|
            filter.call current_content
          end
        end
        ::File.open(path, 'w+') do |f|
          f.write(content)
        end
      end
    end # class Page

  end
end