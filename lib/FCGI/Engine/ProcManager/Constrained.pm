package FCGI::Engine::ProcManager::Constrained;
use Moose;
use Config;

extends 'FCGI::Engine::ProcManager';

has max_requests => (
    isa => 'Int',
    is => 'ro',
    default => sub { $ENV{PM_MAX_REQUESTS} || 0 },
);

has request_count => (
    isa => 'Int',
    is => 'ro',
    traits => ['Counter'],
    handles => {
        _reset_request_counter => 'reset',
        _inc_request_counter => 'inc',
    },
    init_arg => undef,
    default => 0,
);

has sizecheck_num_requests => (
    isa => 'Int',
    is => 'ro',
    default => 0,
);

augment server_init => sub {
    my $self = shift;
    $self->_reset_request_counter();
};

augment post_dispatch => sub {
    my $self = shift;
    $self->exit("safe exit after max_requests (" . $self->max_requests . ")")
        if ($self->max_requests and $self->_inc_request_counter == $self->max_requests);

    if ($self->sizecheck_num_requests and $self->request_count and $self->request_count % $self->sizecheck_num_requests == 0) {
        $self->exit("safe exit due to memory limits exceeded")
            if $self->_limits_are_exceeded;
    }
};

sub _limits_are_exceeded {
    my $self = shift;

    my ($size, $share, $unshared) = $self->_check_size();

    return 1 if $self->max_process_size  && $size > $self->max_process_size;
    return 0 unless $share;
    return 1 if $self->min_share_size    && $share < $self->min_share_size;
    return 1 if $self->max_unshared_size && $unshared > $self->max_unshared_size;

    return 0;
}


# The following code is wholesale is nicked from Apache::SizeLimit::Core

sub _check_size {
    my $class = shift;

    my ($size, $share) = $class->_platform_check_size();

    return ($size, $share, $size - $share);
}

sub _load {
    my $mod = shift;

    Class::MOP::load_class($mod)
        or die
            "You must install $mod for " . __PACKAGE__ . " to work on your" .
            " platform.\n";
}

BEGIN {
    our $USE_SMAPS;
    my ($major,$minor) = split(/\./, $Config{'osvers'});
    if ($Config{'osname'} eq 'solaris' &&
        (($major > 2) || ($major == 2 && $minor >= 6))) {
        *_platform_check_size   = \&_solaris_2_6_size_check;
        *_platform_getppid = \&_perl_getppid;
    }
    elsif ($Config{'osname'} eq 'linux') {
        _load('Linux::Pid');

        *_platform_getppid = \&_linux_getppid;

        if (eval { require Linux::Smaps } && Linux::Smaps->new($$)) {
            $USE_SMAPS = 1;
            *_platform_check_size = \&_linux_smaps_size_check;
        }
        else {
            $USE_SMAPS = 0;
            *_platform_check_size = \&_linux_size_check;
        }
    }
    elsif ($Config{'osname'} =~ /(?:bsd|aix)/i) {
        # on OSX, getrusage() is returning 0 for proc & shared size.
        _load('BSD::Resource');

        *_platform_check_size   = \&_bsd_size_check;
        *_platform_getppid = \&_perl_getppid;
    }
#    elsif (IS_WIN32i && $mod_perl::VERSION < 1.99) {
#        _load('Win32::API');
#
#        *_platform_check_size   = \&_win32_size_check;
#        *_platform_getppid = \&_perl_getppid;
#    }
    else {
        die __PACKAGE__ . " is not implemented on your platform.";
    }
}

sub _linux_smaps_size_check {
    my $class = shift;

    return $class->_linux_size_check() unless $USE_SMAPS;

    my $s = Linux::Smaps->new($$)->all;
    return ($s->size, $s->shared_clean + $s->shared_dirty);
}

sub _linux_size_check {
    my $class = shift;

    my ($size, $share) = (0, 0);

    if (open my $fh, '<', '/proc/self/statm') {
        ($size, $share) = (split /\s/, scalar <$fh>)[0,2];
        close $fh;
    }
    else {
        $class->_error_log("Fatal Error: couldn't access /proc/self/status");
    }

    # linux on intel x86 has 4KB page size...
    return ($size * 4, $share * 4);
}

sub _solaris_2_6_size_check {
    my $class = shift;

    my $size = -s "/proc/self/as"
        or $class->_error_log("Fatal Error: /proc/self/as doesn't exist or is empty");
    $size = int($size / 1024);

    # return 0 for share, to avoid undef warnings
    return ($size, 0);
}

# rss is in KB but ixrss is in BYTES.
# This is true on at least FreeBSD, OpenBSD, & NetBSD
sub _bsd_size_check {

    my @results = BSD::Resource::getrusage();
    my $max_rss   = $results[2];
    my $max_ixrss = int ( $results[3] / 1024 );

    return ($max_rss, $max_ixrss);
}

sub _win32_size_check {
    my $class = shift;

    # get handle on current process
    my $get_current_process = Win32::API->new(
        'kernel32',
        'get_current_process',
        [],
        'I'
    );
    my $proc = $get_current_process->Call();

    # memory usage is bundled up in ProcessMemoryCounters structure
    # populated by GetProcessMemoryInfo() win32 call
    my $DWORD  = 'B32';    # 32 bits
    my $SIZE_T = 'I';      # unsigned integer

    # build a buffer structure to populate
    my $pmem_struct = "$DWORD" x 2 . "$SIZE_T" x 8;
    my $mem_counters
        = pack( $pmem_struct, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 );

    # GetProcessMemoryInfo is in "psapi.dll"
    my $get_process_memory_info = new Win32::API(
        'psapi',
        'GetProcessMemoryInfo',
        [ 'I', 'P', 'I' ],
        'I'
    );

    my $bool = $get_process_memory_info->Call(
        $proc,
        $mem_counters,
        length $mem_counters,
    );

    # unpack ProcessMemoryCounters structure
    my $peak_working_set_size =
        (unpack($pmem_struct, $mem_counters))[2];

    # only care about peak working set size
    my $size = int($peak_working_set_size / 1024);

    return ($size, 0);
}

sub _perl_getppid { return getppid }
sub _linux_getppid { return Linux::Pid::getppid() }

no Moose;
__PACKAGE__->meta->make_immutable;
1;
