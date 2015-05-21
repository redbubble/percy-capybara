require 'json'
require 'digest'

RSpec.describe Percy::Capybara::Client::Snapshots, type: :feature do
  let(:capybara_client) { Percy::Capybara::Client.new }

  # Start a temp webserver that serves the testdata directory.
  # You can test this server manually by running:
  # ruby -run -e httpd spec/lib/percy/capybara/client/testdata/ -p 9090
  before(:all) do
    port = get_random_open_port
    Capybara.app_host = "http://localhost:#{port}"
    Capybara.run_server = false

    # Note: using this form of popen to keep stdout and stderr silent and captured.
    dir = File.expand_path('../testdata/', __FILE__)
    @process = IO.popen([
      'ruby', '-run', '-e', 'httpd', dir, '-p', port.to_s, err: [:child, :out]
    ].flatten)

    # Block until the server is up.
    WebMock.disable_net_connect!(allow_localhost: true)
    verify_server_up(Capybara.app_host)
  end
  after(:all) { Process.kill('INT', @process.pid) }

  before(:each) do
    # Special setting for capybara-webkit. If clients are using capybara-webkit they would
    # also have to have this setting enabled since apparently all resources are blocked by default.
    page.driver.respond_to?(:allow_url) && page.driver.allow_url('*')
  end

  def find_resource(resources, regex)
    resources.select { |resource| resource.resource_url.match(regex) }.fetch(0)
  end

  describe '#_get_root_html_resource', type: :feature, js: true do
    it 'includes the root DOM HTML' do
      visit '/'
      resource = capybara_client.send(:_get_root_html_resource, page)

      expect(resource.is_root).to be_truthy
      expect(resource.mimetype).to eq('text/html')
      expect(resource.resource_url).to match(/http:\/\/localhost:\d+\//)
      expect(resource.content).to include('Hello World!')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))
    end
  end
  describe '#_get_css_resources', type: :feature, js: true do
    it 'includes all linked and imported stylesheets' do
      visit '/test-css.html'
      resources = capybara_client.send(:_get_css_resources, page)

      expect(resources.length).to eq(7)
      expect(resources.collect(&:mimetype).uniq).to eq(['text/css'])
      expect(resources.collect(&:is_root).uniq).to match_array([nil])

      resource = find_resource(resources, /http:\/\/localhost:\d+\/css\/base\.css/)

      expect(resource.content).to include('.colored-by-base { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, /http:\/\/localhost:\d+\/css\/simple-imports\.css/)
      expect(resource.content).to include('@import url("imports.css")')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, /http:\/\/localhost:\d+\/css\/imports\.css/)
      expect(resource.content).to include('.colored-by-imports { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, /http:\/\/localhost:\d+\/css\/level0-imports\.css/)
      expect(resource.content).to include('@import url("level1-imports.css")')
      expect(resource.content).to include('.colored-by-level0-imports { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, /http:\/\/localhost:\d+\/css\/level1-imports\.css/)
      expect(resource.content).to include('@import url("level2-imports.css")')
      expect(resource.content).to include('.colored-by-level1-imports { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, /http:\/\/localhost:\d+\/css\/level2-imports\.css/)
      expect(resource.content).to include(".colored-by-level2-imports { color: red; }")
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = resources.select do |resource|
        resource.resource_url == (
          'https://maxcdn.bootstrapcdn.com/bootstrap/3.3.4/css/bootstrap.min.css')
      end.fetch(0)
      expect(resource.content).to include('Bootstrap v3.3.4 (http://getbootstrap.com)')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))
    end
  end
  describe '#_get_image_resources', type: :feature, js: true do
    it 'includes all images' do
      visit '/test-images.html'
      resources = capybara_client.send(:_get_image_resources, page)

      expect(resources.length).to eq(9)
      expect(resources.collect(&:is_root).uniq).to match_array([nil])

      # The order of the following matches the order of their use in test-images.html.

      resource = find_resource(resources, /http:\/\/localhost:\d+\/images\/img-relative\.png/)
      content = File.read(File.expand_path('../testdata/images/img-relative.png', __FILE__))
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/localhost:\d+\/images\/img-relative-to-root\.png/)
      content = File.read(File.expand_path('../testdata/images/img-relative-to-root.png', __FILE__))
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /https:\/\/percy.io\/images\/percy.svg/)
      content = Faraday.get('https://percy.io/images/percy.svg').body
      expect(resource.mimetype).to eq('image/svg+xml')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/i.imgur.com\/Umkjdao.png/)
      content = Faraday.get('http://i.imgur.com/Umkjdao.png').body
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/localhost:\d+\/images\/bg-relative\.png/)
      content = File.read(File.expand_path('../testdata/images/bg-relative.png', __FILE__))
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/localhost:\d+\/images\/bg-relative-to-root\.png/)
      content = File.read(File.expand_path('../testdata/images/bg-relative-to-root.png', __FILE__))
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/i.imgur.com\/5mLoBs1.png/)
      content = Faraday.get('http://i.imgur.com/5mLoBs1.png').body
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/localhost:\d+\/images\/bg-stacked\.png/)
      content = File.read(File.expand_path('../testdata/images/bg-stacked.png', __FILE__))
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/i.imgur.com\/61AQuplb.jpg/)
      content = Faraday.get('http://i.imgur.com/61AQuplb.jpg').body
      expect(resource.mimetype).to eq('image/jpeg')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)
    end
  end
  describe '#snapshot', type: :feature, js: true do
    context 'simple page with no resources' do
      let(:content) { '<html><body>Hello World!</body><head></head></html>' }

      it 'creates a snapshot and uploads missing resource' do
        visit '/'

        mock_response = {
          'data' => {
            'id' => '123',
            'type' => 'builds',
          },
        }
        stub_request(:post, 'https://percy.io/api/v1/repos/percy/percy-capybara/builds/')
          .to_return(status: 201, body: mock_response.to_json)

        resource = capybara_client.send(:_get_root_html_resource, page)
        mock_response = {
          'data' => {
            'id' => '256',
            'type' => 'snapshots',
            'links' => {
              'self' => "/api/v1/snapshots/123",
              'missing-resources' => {
                'linkage' => [
                  {
                    'type' => 'resources',
                    'id' => resource.sha,
                  },
                ],
              },
            },
          },
        }
        stub_request(:post, 'https://percy.io/api/v1/builds/123/snapshots/')
          .to_return(status: 201, body: mock_response.to_json)

        stub_request(:post, "https://percy.io/api/v1/builds/123/resources/")
          .with(body: /#{resource.sha}/).to_return(status: 201, body: {success: true}.to_json)

        resource_map = capybara_client.snapshot(page)
      end
    end
  end
end
