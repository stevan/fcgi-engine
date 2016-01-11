package Plack::Handler::FCGI::Engine::PSGI;

use strict;

use base 'Plack::Handler';

our $VERSION   = '0.22';
our $AUTHORITY = 'cpan:STEVAN';

use FCGI::Engine::PSGI;

sub new {
    my($class, %args) = @_;
    bless { %args }, $class;
}

sub run {
    my($self, $app) = @_;
    my $server = FCGI::Engine::PSGI->new(%$self, app => $app);
    $server->run();
}

1;

__END__

=pod

=head1 NAME

Plack::Handler::FCGI::Engine::PSGI - A Plack::Handler backend for FCGI::Engine::PSGI

=head1 SYNOPSIS

  use Plack::Handler::FCGI::Engine::PSGI;

  my $handler = Plack::Handler::FCGI::Engine::PSGI->new(
      nproc  => $num_proc,
      listen => $listen,
      detach => 1,
  );

  $handler->run($app);

=head1 DESCRIPTION

This is a subclass of L<Plack::Handler> which will use the
L<FCGI::Handler::PSGI> as handler.

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Stevan Little E<lt>stevan.little@iinteractive.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2009-2010 Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
