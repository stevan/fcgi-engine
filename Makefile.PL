use strict;
use warnings;
use inc::Module::Install;

name 'FCGI::Engine';
all_from 'lib/FCGI/Engine.pm';
license 'perl';

( $^O eq 'Win32' or $^O eq 'cygwin' )
    || die "This module is not for Window, sorry.";

# prereqs
requires 'Moose';
requires 'MooseX::Types::Path::Class';
requires 'File::Pid';
requires 'FCGI::ProcManager';
requires 'FCGI';
requires 'CGI';
requires 'POSIX';
requires 'Best'; # we need either YAML or YAML::Syck

# things the tests need
build_requires 'Test::More';
build_requires 'Test::Exception';
build_requires 'File::Spec';
build_requires 'FindBin';

tests('t/*.t');

WriteAll();

