require 'spec_helper'

require_relative "../lib/sinatra/export/page.rb"

class MyFakeResponse < Struct.new(:body); end
module MyStubs
  def get_path
    resp = MyFakeResponse.new("get_path #{@path} called with status #{@status}")
    resp
  end

  def build_artefacts
    warn "Artefacts built from #{@result}"     
  end   
end

module Sinatra
module Export
describe Page do

  it "should not blow up on instantiation" do
    expect { Page.new "/" }.not_to raise_error
  end
  context "A single page" do
      
    Given(:a_page) {
      page = Page.new("/") do |resp|
        ["/about"]
      end
      page.extend MyStubs
      page
    }

    context "getting" do
      When(:get_page) { a_page.resume }
      Then { a_page.resp.body.should == "get_path / called with status 200" }
      And { a_page.milestone == :responded_to }
    end

    context "block" do
      When(:block_result) {
        a_page.resume
        a_page.resume
      }
      Then { block_result.should be_nil }
    end

    context "building" do
      When(:artefacts) {
        a_page.resume
        a_page.resume
      }
      Then { artefacts == nil }
    end

    it "Too many resumes" do
      expect { 
        a_page.resume
        a_page.resume
        a_page.resume
        a_page.resume }.to raise_error FiberError
    end
  end


  describe "Multiple pages" do
    def pages
      @pages = []
    end

    Given(:setup) do
      5.times {|i|
        page = Page.new("/#{i}") do |body| 
          puts "Page #{i} Sleeping for #{body}…";
          body.times do |t|
            print "#{i} #{t}"
            sleep 1
          end
          puts "Body: #{body} Now: #{body * 2}"
          body = body * 2
          print "\n"
          puts "#{i} Awake!"
          pages = [rand(5),rand(5),rand(5)]
          [pages,body]
        end
        page.extend MyStubs
        pages << page
      }
    end

    When(:map) { pages.map{|page| page.resume } }
    Then { pages.all?{|page| page.milestone == :responded_to } }
    When(:map) { pages.map{|page| page.resume } }
    Then { pages.all?{|page| page.milestone == :processing_block } }
    When(:map) { pages.map{|page| page.resume } }
    Then { pages.all?{|page| page.milestone == :finish } }
  end
end

end
end