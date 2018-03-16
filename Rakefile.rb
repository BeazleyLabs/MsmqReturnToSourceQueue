require 'bundler/setup'
require 'albacore'
require 'rake/clean'
require 'fileutils'
require 'json'

require_relative 'buildtools/rakehelpers'               # General purpose helpers

#--------------------------------------
# VARIABLES
#--------------------------------------
SOLUTION_DIR = Rake.original_dir
SOLUTION_NAME = 'MsmqReturnToSourceQueue.sln'

BUILD_TOOLS_DIR = File.join(SOLUTION_DIR, 'BuildTools')
OCTOPUS_DEPLOY = Octopus_Deploy.new("#{ENV['Octopus_Server']}", "#{ENV['Octopus_API_Key']}")
NUGET_ARTIFACTS = Nuget.new("#{ENV['NuGet_Server']}", "#{ENV['NuGet_API_Key']}")
NUGET_DEPLOYMENT_ARTIFACTS = Nuget.new("#{ENV['NuGet_Deployments_Server']}", "#{ENV['NuGet_Deployments_API_Key']}")

BUILD_OUTPUT_BASE_DIR = File.join(SOLUTION_DIR, 'BuildOutput')
BUILD_OUTPUT_TEST_DIR = File.join(BUILD_OUTPUT_BASE_DIR, 'TestResults')
BUILD_OUTPUT_NUGET_DIR = File.join(BUILD_OUTPUT_BASE_DIR, 'nuget.bfl.local')
BUILD_OUTPUT_NUGET_DEPLOYMENTS_DIR = File.join(BUILD_OUTPUT_BASE_DIR, 'nugetdeployments.bfl.local')

XUNIT_ASSEMBLIES = FileList[
  'ReturnToSourceQueueTests\bin\Release\ReturnToSourceQueueTests.dll'
]

arg_defaults = {
    build_number: "0.0.0",
    msbuild_debug?: ENV['MSBuild_Debug'] == "True",
}

CONFIG_FILE = File.join(SOLUTION_DIR, 'config.json')
CONFIG = OpenStruct.new()

def init()
    puts CONFIG.inspect
end

init()

DEPENDENCIES_DIR = File.join(SOLUTION_DIR, 'lib')
DEPENDENT_NUGET_PACKAGES = []

CLOBBER.include(DEPENDENCIES_DIR)
directory DEPENDENCIES_DIR => :clobber

PACKAGE = Package_Information.new(
    name: "Beazley.MsmqReturnToSourceQueue",
    artifact_store: NUGET_DEPLOYMENT_ARTIFACTS,
    source_spec_dir: SOLUTION_DIR,
    output_folder: BUILD_OUTPUT_NUGET_DEPLOYMENTS_DIR
  )

PACKAGES_INFO = [
    PACKAGE
]

# Clean up
CLOBBER.include(BUILD_OUTPUT_BASE_DIR)
directory BUILD_OUTPUT_BASE_DIR => :clobber


#--------------------------------------
# BUILD TASKS
#--------------------------------------
task default: %w[build]

task :build_valid_packages, [:build_number] => [:build, :validate, :build_packages]

task :publish, [:build_number] => [:publish_packages]

task :build => [:msbuild]

task :validate => [:run_tests]

#only needed because rakehelper depends on :build_release for :deploy_to_local
task :build_release do |t,args|    
    task(:build).invoke()
end

desc 'Restore NuGet Packages required for Building'
exec :nuget_restore do |cmd, args|

    puts "Restoring NuGet Packages..."

    ENV['EnableNuGetPackageRestore'] = 'true'
    cmd.command = File.join(BUILD_TOOLS_DIR, 'NuGet.exe')
    cmd.parameters = [
        "restore",
        "\"#{File.join(SOLUTION_DIR, SOLUTION_NAME)}\""
    ]
end

desc 'Sets up the developers local machine so they can develop the solution'
task :setup_dev_experience, [:server, :port_number] do |sql, args|

    puts "Nothing special required!"

end

desc "Updates AssemblyInfo.cs file with desired version information"
assemblyinfo :version_assembly_file do |asm, args|

    common_assembly_file = File.join(SOLUTION_DIR, 'CommonAssemblyInfo.cs')
    asm.version = args.build_number
    asm.file_version = args.build_number
    asm.output_file = common_assembly_file
    asm.input_file = common_assembly_file
end

desc "Run any tests that are required"
xunit :run_tests do |xunit|
  puts "running tests..."
  runner_dir = get_runner_directory
  puts "runner directory: #{runner_dir}"
  xunit.command = File.join(runner_dir, 'tools', 'net452', 'xunit.console.exe')
  xunit.assemblies XUNIT_ASSEMBLIES
end

msbuild :msbuild, [:config] => [:clobber, :nuget_restore, :version_assembly_file] do |msb, args|
    apply_build_defaults_to msb
    msb.nologo
    msb.solution = File.join(SOLUTION_DIR, SOLUTION_NAME)
    msb.targets = [ :Clean, :Build ]
    msb.properties = { configuration: args.msbuild_debug? ? :Debug : :Release}
end

task :build_packages, [:build_number] => [:build, :install_dependencies] do |cmd, args|    
    mkdir_p(BUILD_OUTPUT_NUGET_DIR)
    mkdir_p(BUILD_OUTPUT_NUGET_DEPLOYMENTS_DIR)    
    # Create package artifacts
    PACKAGES_INFO.each { |package|
        package.artifact_store.create_package(args.build_number, package.source, package.output_folder)
    }

end

task :publish_packages, [:build_number] do |cmd, args|
    # Publish package artifacts
    PACKAGES_INFO.each { |package|
        full_file_path = File.join(package.output_folder, "#{package.name}.#{args.build_number}.nupkg")
        puts "Pushing #{full_file_path}..."
        package.artifact_store.push_package(full_file_path)
    }
end

task :install_dependencies => [DEPENDENCIES_DIR] do |cmd, args|
    puts "Installing NuGet Dependencies..."
    DEPENDENT_NUGET_PACKAGES.each{ |package|
        install_dependency(package[:id], package[:version], package[:install_location] || DEPENDENCIES_DIR)
    }
end

task :install_dependency, [:package_id, :package_version] => [DEPENDENCIES_DIR] do |cmd, args|
    install_dependency(args.package_id, args.package_version)
end

def install_dependency(package_id, package_version = nil, install_location)
    puts "Installing #{package_id}"
    versionArg = "-Version #{package_version}" unless package_version.nil?

    cmd = Exec.new()
    cmd.command = File.join(BUILD_TOOLS_DIR, 'NuGet.exe')
    cmd.parameters = [
        "install",
        "#{package_id}",
        "-OutputDirectory \"#{install_location}\"",
        "-ExcludeVersion",
        versionArg
    ]
    cmd.execute()
end

def get_runner_directory
    search_dir = File.join(SOLUTION_DIR, 'packages')
  
    powershell_command = %Q("Get-ChildItem #{search_dir} xunit.runner* -Recurse -Directory | Select-Object -First 1 -ExpandProperty FullName")
  
    search_command = [
      'powershell',
      '-command',
      powershell_command,
    ].join(' ')
  
    return %x(#{search_command}).strip
  end

#this needs to be at the end of the file
set_default_args(arg_defaults)
