require File.expand_path("spec_helper", File.dirname(__FILE__))

describe 'Rodauth' do
  it "should keep private methods private when overridden" do
    rodauth do
      use_database_authentication_functions? false
    end
    roda do |r|
      rodauth.use_database_authentication_functions?.to_s
    end

    proc{visit '/'}.must_raise NoMethodError
  end

  it "should require login to perform certain actions" do
    rodauth do
      enable :login, :change_password, :change_login, :close_account
    end
    roda do |r|
      r.rodauth

      r.is "a" do
        rodauth.require_login
      end
    end

    visit '/change-password'
    page.current_path.must_equal '/login'

    visit '/change-login'
    page.current_path.must_equal '/login'

    visit '/close-account'
    page.current_path.must_equal '/login'

    visit '/a'
    page.current_path.must_equal '/login'
  end

  it "should handle case where account is no longer valid during session" do
    rodauth do
      enable :login, :change_password
      already_logged_in{request.redirect '/'}
      skip_status_checks? false
    end
    roda do |r|
      r.rodauth

      r.root do
        view :content=>(rodauth.logged_in? ? "Logged In" : "Not Logged")
      end
    end

    login
    page.body.must_include("Logged In")

    DB[:accounts].update(:status_id=>3)
    visit '/change-password'
    page.current_path.must_equal '/login'
    visit '/'
    page.body.must_include("Not Logged")
  end

  it "should handle cases where you are already logged in on pages that don't expect a login" do
    rodauth do
      enable :login, :logout, :create_account, :reset_password, :verify_account
      already_logged_in{request.redirect '/'}
    end
    roda do |r|
      r.rodauth

      r.root do
        view :content=>''
      end
    end

    login

    visit '/login'
    page.current_path.must_equal '/'

    visit '/create-account'
    page.current_path.must_equal '/'

    visit '/reset-password'
    page.current_path.must_equal '/'

    visit '/verify-account'
    page.current_path.must_equal '/'

    visit '/logout'
    page.current_path.must_equal '/logout'
  end

  it "should have rodauth.features and rodauth.session_value work when not logged in" do
    rodauth do
      enable :login
    end
    roda do |r|
      "#{rodauth.features.first.inspect}#{rodauth.session_value.inspect}"
    end

    visit '/'
    page.body.must_equal ':loginnil'
  end

  it "should support auth_class_eval for evaluation inside Auth class" do
    rodauth do
      enable :login
      login_label{foo}
      auth_class_eval do
        def foo
          'Lonig'
        end
      end
    end
    roda do |r|
      r.rodauth
    end

    visit '/login'
    fill_in 'Lonig', :with=>'foo@example.com'
  end

  it "should support multiple rodauth configurations in an app" do
    app = Class.new(Base)
    app.plugin(:rodauth) do
      enable :login
    end
    app.plugin(:rodauth, :name=>:r2) do
      enable :logout
    end
    app.route do |r|
      r.on 'r1' do
        r.rodauth
        'r1'
      end
      r.on 'r2' do
        r.rodauth(:r2)
        'r2'
      end
      rodauth.session_value.inspect
    end
    app.freeze
    self.app = app

    login(:path=>'/r1/login')
    page.body.must_equal DB[:accounts].get(:id).to_s

    visit '/r2/logout'
    click_button 'Logout'
    page.body.must_equal 'nil'

    visit '/r1/logout'
    page.body.must_equal 'r1'
    visit '/r2/login'
    page.body.must_equal 'r2'
  end

  it "should support account_model setting for backwards compatibility" do
    warning = nil
    rodauth do
      enable :login
      (class << self; self end).send(:define_method, :warn){|msg| warning = msg}
      account_model Sequel::Model(DB[:accs].select(:id))
    end
    roda do |r|
      "#{rodauth.accounts_table}#{rodauth.account_select.length}"
    end

    visit '/'
    page.body.must_equal 'accs1'
    warning.must_equal "account_model is deprecated, use db and accounts_table settings"
  end

  it "should support account_select setting for choosing account columns" do
    warning = nil
    rodauth do
      enable :login
      account_select [:id, :email]
    end
    roda do |r|
      r.rodauth
      rodauth.account_from_session
      rodauth.account.keys.map(&:to_s).sort.join(' ')
    end

    login
    page.body.must_equal 'email id'
  end

  it "should support :csrf=>false and :flash=>false plugin options" do
    rodauth{}
    roda(:csrf=>false, :flash=>false){}
    app.instance_variable_get(:@middleware).length.must_equal 1
    app.ancestors.map(&:to_s).wont_include 'Roda::RodaPlugins::Flash::InstanceMethods'
  end
end
