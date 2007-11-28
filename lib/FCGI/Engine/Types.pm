package FCGI::Engine::Types;
use Moose::Util::TypeConstraints;

use Declare::Constraints::Simple '-All';
use MooseX::Getopt::OptionTypeMap;
use MooseX::Types::Path::Class;

## FCGI::Engine

subtype 'FCGI::Engine::ListenerPort'
    => as 'Int'
    => where { $_ >= 1 && $_ <= 65535 };

subtype 'FCGI::Engine::Listener' 
    => as 'Path::Class::File | FCGI::Engine::ListenerPort';

MooseX::Getopt::OptionTypeMap->add_option_type_to_map(
    'FCGI::Engine::Listener' => '=s',
);

## FCGI::Engine::Manager

subtype 'FCGI::Engine::Manager::Server::Config'
    => as 'HashRef'
    => And(
         IsHashRef,
         HasAllKeys(qw[scriptname pidfile socket]),
         OnHashKeys(
             additional_args => IsArrayRef
         )
    );

subtype 'FCGI::Engine::Manager::Config' 
    => as 'ArrayRef[FCGI::Engine::Manager::Server::Config]';

## FCGI::Engine::ProcManager

enum 'FCGI::Engine::ProcManager::Role' => qw[manager server];

1;

__END__

=pod

=cut