package Plack::Server::FCGI::Engine;
use Moose;
use MooseX::NonMoose;

use Plack::Server::FCGI::Engine::ProcManager;

our $VERSION   = '0.12';
our $AUTHORITY = 'cpan:STEVAN';

extends 'Plack::Server::FCGI';

has 'manager' => (
    is      => 'ro',
    isa     => 'Str | ClassName',
    default => sub { 'Plack::Server::FCGI::Engine::ProcManager' },
);

__PACKAGE__->meta->make_immutable;

no Moose; 1;

__END__

=pod

=head1 NAME

Plack::Server::FCGI::Engine - A Plack::Server backend for FCGI::Engine

=head1 SYNOPSIS

  use Plack::Server::FCGI::Engine;

  my $server = Plack::Server::FCGI::Engine->new(
      nproc  => $num_proc,
      listen => $listen,
      detach => 1,
  );

  $server->run($app);

=head1 DESCRIPTION

This is a subclass of L<Plack::Server::FCGI> which will use the
L<Plack::Server::FCGI::Engine::ProcManager> process manager by default,
instead of L<FCGI::ProcManager>.

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Stevan Little E<lt>stevan.little@iinteractive.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2009 Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
