require File.expand_path('../test_helper', __FILE__)
require 'sinatra/export'

class SinatraExportBuildTest < UnitTest

  class App < UnitTest::App
    register Sinatra::Export

    get '/' do
      "homepage"
    end

    get '/contact' do
      "contact"
    end

    get '/data.json' do
      "{test: 'ok'}"
    end

    get '/yesterday' do
      last_modified Time.local(2002, 10, 31)
      "old content"
    end

  end

  def test_build
    # Temporary public folder
    public_folder = App.public_folder
    FileUtils.rm_rf public_folder
    FileUtils.mkdir public_folder

    App.export!

    assert File.read(File.join(public_folder, 'index.html')).include?('homepage')
    assert File.read(File.join(public_folder, 'contact/index.html')).include?('contact')
    assert File.read(File.join(public_folder, 'data.json')).include?("{test: 'ok'}")

    assert File.mtime(File.join(public_folder, 'yesterday/index.html')) == Time.local(2002, 10, 31)
  end

end