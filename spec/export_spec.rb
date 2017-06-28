require 'spec_helper'
require 'sinatra'
require_relative "../lib/sinatra/export.rb"

describe "Sinatra Export" do

  shared_context "app" do
    def app
      Sinatra.new do
        register Sinatra::Export

        configure do
          set :root, File.join(__dir__, "support/fixtures", "app")
          enable :raise_errors
          disable :show_exceptions
        end

        get '/' do
          "<p>homepage</p><p><a href='/echo-1'>echo-1</a></p>"
        end

        get '/contact/?' do
          "contact"
        end

        get '/data.json' do
          "{test: 'ok'}"
        end

        get '/yesterday' do
          last_modified Time.local(2002, 10, 31)
          "old content"
        end

        get "/echo-:this" do |this|
          this.to_s
        end

        not_found do
          'This is nowhere to be found.'
        end

        get "/this-will-send-non-200/*" do
          halt 401, "No thanks!" 
        end
      end
    end
  end

  shared_examples "Server is up" do
    before { get "/" }
    subject {  last_response }
    it { should be_ok }
  end

  shared_context "Cleanup" do
    before :all do
      Sinatra::Export::Page.reset!
      path = Pathname(__dir__).join("support/fixtures", "app" )
      path.rmtree if path.exist?
      path.join("public").mkpath
    end

    after :all do
      Pathname(__dir__).join("support/fixtures", "app" ).rmtree
      Sinatra::Export::Page.reset!
    end
  end

  Given(:public_folder) { Pathname(app.public_folder) }


  context "Using the default settings" do
    include_context "app"
    include_examples "Server is up"

    describe "Straightfoward exporting" do
      include_context "Cleanup"

      When(:builder) { app.export! }

      Given(:index) { public_folder.join('index.html') }
      Given(:contact) { public_folder.join('contact/index.html') }
      Given(:data_json) { public_folder.join('data.json') }
      Given(:yesterday) { public_folder.join('yesterday/index.html') }
      Then { index.exist? }
      And { index.read.should include 'homepage' }
      And { contact.read.should include 'contact' }
      And { data_json.read.should include "{test: 'ok'}" }
      And { yesterday.read.should include 'old content' }
      And { yesterday.mtime.should == Time.local(2002, 10, 31) }

      And { builder.visited.should =~ ["/", "/contact/", "/data.json", "/yesterday"] }
    end


    describe "Raising errors" do
      include_context "Cleanup"

      context "this-will-send-non-200/for-sure" do
        context "Using the default error handler" do
          When(:builder) { app.export! paths: ["/this-will-send-non-200/for-sure"] }
          Then { builder.errored.should =~ ["/this-will-send-non-200/for-sure"] }
        end
        context "Supplying an error handler" do
          it "should raise error" do
            expect {
              @builder = app.export! paths: ["/this-will-send-non-200/for-sure"], error_handler: ->(desc){ fail "Please stop" }
            }.to raise_error
          end
        end
      end
    
    end 

    describe "Given paths" do
      include_context "Cleanup"

      When(:builder) { 
        app.export! paths: ["/", "/contact", ["/404.html", 404]]
      }

      Given(:index) { public_folder.join 'index.html' }
      Given(:contact) { public_folder.join 'contact/index.html' }
      Given(:data_json) { public_folder.join 'data.json' }
      Given(:yesterday) { public_folder.join 'yesterday/index.html' }
      Given(:fourOhFour) { public_folder.join '404.html' }

      Then { index.read.include? 'homepage' }
      And { contact.read.include? 'contact' }
      And { data_json.exist? == false }
      And { yesterday.exist? == false }
      And { fourOhFour.read.include? 'This is nowhere to be found.' }
      And { builder.pages["/404.html"].status == 404 }
      And { builder.pages["/404.html"].resp.status == 404 }
    end
    
    context "Given skips" do
      include_context "Cleanup"

      Given(:index) { public_folder.join('index.html') }
      Given(:contact) { public_folder.join('contact/index.html') }
      Given(:data_json) { public_folder.join('data.json') }
      Given(:yesterday) { public_folder.join('yesterday/index.html') }
      When { app.export! skips: ["/", "/contact/?"] }
      Then { index.exist? == false }
      And { contact.exist? == false }
      And { data_json.exist? }
      And { yesterday.exist? }
      And { yesterday.read.include? 'old content' }
      And { yesterday.mtime == Time.local(2002, 10, 31) }
    end

    context "Using a block" do
      context "To add a path" do
        include_context "Cleanup"

        Given(:index) { public_folder.join('index.html') }
        Given(:contact) { public_folder.join('contact/index.html') }
        Given(:data_json) { public_folder.join('data.json') }
        Given(:yesterday) { public_folder.join('yesterday/index.html') }
        Given(:echo1) { public_folder.join('echo-1/index.html') }

        When(:builder) {
          app.export! do |resp|
            paths = []
            if resp.body.include? "/echo-1"
              paths << "/echo-1"
            end
            paths
          end
        }

        Then { index.read.include? 'homepage' }
        And { contact.read.include? 'contact' }
        And { data_json.read.include? "{test: 'ok'}" }
        And { yesterday.read.include? 'old content' }
        And { yesterday.mtime  == Time.local(2002, 10, 31) }
        context "named parameters" do
          Then { echo1.read.include? '1' }
        end
      end

      context "To filter output" do
        include_context "Cleanup"

        When(:builder) {
          app.export! do |resp|
            [[],resp.body.upcase]
          end
        }

        Given(:index) { public_folder.join('index.html') }
        Given(:contact) { public_folder.join('contact/index.html') }
        Given(:data_json) { public_folder.join('data.json') }
        Given(:yesterday) { public_folder.join('yesterday/index.html') }
        Then { index.read.include? 'HOMEPAGE' }
        And { contact.read.include? 'CONTACT' }
        And { data_json.read.include? "{TEST: 'OK'}" }
        And { yesterday.read.include? 'OLD CONTENT' }
        And { yesterday.mtime  == Time.local(2002, 10, 31) }
      end
    end

    context "Given a builder" do
      include_context "Cleanup"
      When(:builder) {  
        app.builder = Sinatra::Export::Builder.new(app,paths: ["/", "/contact"])
        app.export!
      }

      Given(:index) { public_folder.join('index.html') }
      Given(:contact) { public_folder.join('contact/index.html') }
      Given(:data_json) { public_folder.join('data.json') }
      Given(:yesterday) { public_folder.join('yesterday/index.html') }

      Then { index.read.include? 'homepage' }
      And { contact.read.include? 'contact' }
      And { data_json.read.include? "{test: 'ok'}" }
      And { yesterday.read.include? 'old content' }
      And { yesterday.mtime  == Time.local(2002, 10, 31) }
    end

    context "Given filters" do
      include_context "Cleanup"

      When(:builder) {
        app.export! filters: [->(text){ text.upcase }]
      }

      Given(:index) { public_folder.join('index.html') }
      Given(:contact) { public_folder.join('contact/index.html') }
      Given(:data_json) { public_folder.join('data.json') }
      Given(:yesterday) { public_folder.join('yesterday/index.html') }

      Then { index.read.include? 'HOMEPAGE' }
      And { contact.read.include? 'CONTACT' }
      And { data_json.read.include? "{TEST: 'OK'}" }
      And { yesterday.read.include? 'OLD CONTENT' }
      And { yesterday.mtime  == Time.local(2002, 10, 31) }
    end
  end

  context "Using an env var" do
    include_context "app"
    include_examples "Server is up"

    before :all do
      path = Pathname(__dir__).join("support/fixtures/static/001")
      ENV["EXPORT_BUILD_DIR"] = path.to_path
      path.rmtree if path.exist?
      path.mkpath
      Sinatra::Export::Page.reset!
    end

    after :all do
      path = Pathname(ENV["EXPORT_BUILD_DIR"])
      path.rmtree
      ENV["EXPORT_BUILD_DIR"] = nil
      Sinatra::Export::Page.reset!
    end

    When(:builder) { app.export! }
    Given(:export_build_dir) { Pathname(ENV["EXPORT_BUILD_DIR"]) }

    Given(:index) { export_build_dir.join('index.html') }
    Given(:contact) { export_build_dir.join('contact/index.html') }
    Given(:data_json) { export_build_dir.join 'data.json' }
    Given(:yesterday) { export_build_dir.join('yesterday/index.html') }
    Then { index.read.include? 'homepage' }
    And { contact.read.include? 'contact' }
    And { data_json.read.include? "{test: 'ok'}" }
    And { yesterday.read.include? 'old content' }
    And { yesterday.mtime == Time.local(2002, 10, 31) }
  end

end