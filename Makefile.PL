use strict;
use warnings;
use inc::Module::Install;

name 'FCGI::Engine';
all_from 'lib/FCGI/Engine.pm';
license 'perl';

( $^O eq 'Win32' or $^O eq 'cygwin' )
    || die "This module is not for Window, sorry.";

# prereqs
requires 'Moose' => 0.32;
requires 'MooseX::Types::Path::Class';
requires 'File::Pid';
requires 'Declare::Constraints::Simple';
requires 'FCGI';
requires 'CGI';
requires 'POSIX';
requires 'Config::Any';

# things the tests need
build_requires 'Test::More';
build_requires 'Test::Exception';
build_requires 'File::Spec';
build_requires 'FindBin';

tests('t/*.t');

WriteAll();

