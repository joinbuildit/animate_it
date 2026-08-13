require "open3"

RSpec.describe "standalone AnimateIt loading" do
  it "loads the packaged entrypoint before Rails is booted" do
    library = File.expand_path("../../lib", __dir__)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-I#{library}", "-e", 'require "animate_it"; print AnimateIt::VERSION'
    )

    expect(status).to be_success, stderr
    expect(stdout).to eq(AnimateIt::VERSION)
  end
end
