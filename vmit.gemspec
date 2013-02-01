# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "vmit/version"

Gem::Specification.new do |s|
  s.name        = "vmit"
  s.version     = Vmit::VERSION
  s.authors     = ["Duncan Mac-Vicar P."]
  s.email       = ["dmacvicar@suse.de"]
  s.homepage    = ""
  s.summary     = %q{Virtual machine (kvm) command line tool}
  s.description = %q{vmit makes easy to maintain and run virtual machines.}

  s.rubyforge_project = "vmit"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.add_dependency('clamp')
  s.add_dependency('open4')
  s.add_dependency('pidfile')
end
