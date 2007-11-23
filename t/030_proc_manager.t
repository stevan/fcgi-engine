#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 5;

use FCGI::Engine::ProcManager;

my $m;

ok $m = FCGI::Engine::ProcManager->new(n_processes => 100, pid_fname => '/tmp/foo.pid');

ok $m->n_processes() == 100;
ok $m->n_processes(2) == 2;
ok $m->n_processes(0) == 0;

ok !$m->pm_manage();

#ok $m->n_processes(-3);
#eval { $m->pm_manage(); };
#ok $@ =~ /dying from number of processes exception: -3/;
#undef $@;

if ($ENV{PM_N_PROCESSES}) {
  $m->n_processes($ENV{PM_N_PROCESSES});
  $m->pm_manage();
  sample_request_loop($m);
}

exit 0;

sub sample_request_loop {
  my ($m) = @_;

  while (1) {
    # Simulate blocking for a request.
    my $t1 = int(rand(2)+2);
    print "TEST: simulating blocking for request: $t1 seconds.\n";
    sleep $t1;
    # (Here is where accept-fail-on-intr would exit request loop.)

    $m->pm_pre_dispatch();

    # Simulate a request dispatch.
    my $t = int(rand(3)+2);
    print "TEST: simulating new request: $t seconds.\n";
    while (my $nslept = sleep $t) {
      $t -= $nslept;
      last unless $t;
    }

    $m->pm_post_dispatch();
  }
}
