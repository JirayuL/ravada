use warnings;
use strict;

package Ravada::VM;

use Carp qw(croak);
use Data::Dumper;
use Socket qw( inet_aton inet_ntoa );
use Moose::Role;
use Net::DNS;
use IO::Socket;
use IO::Interface;
use Sys::Hostname;

requires 'connect';

# global DB Connection

our $CONNECTOR = \$Ravada::CONNECTOR;
our $CONFIG = \$Ravada::CONFIG;

our $MIN_MEMORY_MB = 128 * 1024;

# domain
requires 'create_domain';
requires 'search_domain';

requires 'list_domains';

# storage volume
requires 'create_volume';

requires 'connect';
requires 'disconnect';

############################################################
#
has 'name' => (
       isa => 'Str'
       ,is => 'ro'
  ,builder => '_set_default_name'
     ,lazy => 1
);

has 'host' => (
          isa => 'Str'
         , is => 'ro',
    , default => 'localhost'
);

has 'storage_pool' => (
     isa => 'Object'
    , is => 'ro'
);

has 'default_dir_img' => (
      isa => 'String'
     , is => 'ro'
);

has 'readonly' => (
    isa => 'Str'
    , is => 'ro'
    ,default => 0
);
############################################################
#
# Method Modifiers definition
# 
#
before 'create_domain' => \&_pre_create_domain;

before 'search_domain' => \&_connect;

before 'create_volume' => \&_connect;

=head1 CONSTRUCTORS

=head2 open

Opens a Virtual Machine Manager

    my $vm = Ravada::VM->open($name);

=cut

sub open {
    my $self = shift;
    my $name = shift;

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT vtype, host "
        ." FROM vms "
        ." WHERE name=?"
    );
    $sth->execute($name);

    my ($type, $host) = $sth->fetchrow;
    $sth->finish;
    return if !$type;

    my $class = "Ravada::VM::$type";
    my $vm0 = {};
    bless $vm0,$class;

    return $vm0->new( 
        name => $name
       ,host => $host
    );

}

#############################################################
#
# setters
#
sub _set_name {
    my $self = shift;

    return $self->type." VM on ".$self->host;
}

#############################################################
#
# method modifiers
#
sub _check_readonly {
    my $self = shift;
    confess "ERROR: You can't create domains in read-only mode "
        if $self->readonly 

}

sub _connect {
    my $self = shift;
    $self->connect();
}

sub _pre_create_domain {
    _check_create_domain(@_);
    _connect(@_);
}

############################################################
#
sub _domain_remove_db {
    my $self = shift;
    my $name = shift;
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM domains WHERE name=?");
    $sth->execute($name);
    $sth->finish;
}

=head2 domain_remove

Remove the domain. Returns nothing.

=cut


sub domain_remove {
    my $self = shift;
    $self->domain_remove_vm();
    $self->_domain_remove_bd();
}

=head2 name

Returns the name of this Virtual Machine Manager

    my $name = $vm->name();

=cut

sub name {
    my $self = shift;

    my ($ref) = ref($self) =~ /.*::(.*)/;

    return ($ref or ref($self));
}

=head2 search_domain_by_id

Returns a domain searching by its id

    $domain = $vm->search_domain_by_id($id);

=cut

sub search_domain_by_id {
    my $self = shift;
      my $id = shift;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT name FROM domains "
        ." WHERE id=?");
    $sth->execute($id);
    my ($name) = $sth->fetchrow;
    return if !$name;

    return $self->search_domain($name);
}

=head2 ip

Returns the external IP this for this VM

=cut

sub ip {
    my $self = shift;

    my $name = $self->host() or confess "this vm has no host name";
    my $ip = inet_ntoa(inet_aton($name)) ;

    return $ip if $ip && $ip !~ /^127\./;

    $name = Ravada::display_ip();

    if ($name) {
        if ($name =~ /^\d+\.\d+\.\d+\.\d+$/) {
            $ip = $name;
        } else {
            $ip = inet_ntoa(inet_aton($name));
        }
    }
    return $ip if $ip && $ip !~ /^127\./;

    $ip = _ip_from_hostname();
    return $ip if $ip && $ip !~ /^127\./;

    $ip = $self->_interface_ip();
    return $ip if $ip && $ip !~ /^127/ && $ip =~ /^\d+\.\d+\.\d+\.\d+$/;

    warn "WARNING: I can't find the IP of host ".$self->host.", using localhost."
        ." This virtual machine won't be available from the network.";

    return '127.0.0.1';
}

sub _localhost {
    my $self = shift;
    return $self->host =~ /^localhost$/i
        || $self->host eq '127.0.0.1';
}

sub _ip_from_hostname {
    my $res = Net::DNS::Resolver->new();
    my $reply = $res->search(hostname());
    return if !$reply;

    for my $rr ($reply->answer) {
        return $rr->address if $rr->type eq 'A';
    }
}

sub _interface_ip {
    my $s = IO::Socket::INET->new(Proto => 'tcp');

    for my $if ( $s->if_list) {
        my $addr = $s->if_addr($if);
        return $addr if $addr && $addr !~ /^127\./;
    }
    return;
}

sub _check_memory {
    my $self = shift;
    my %args = @_;
    return if !exists $args{memory};

    die "ERROR: Low memory '$args{memory}' required ".int($MIN_MEMORY_MB/1024)." MB " if $args{memory} < $MIN_MEMORY_MB;
}

sub _check_disk {
    my $self = shift;
    my %args = @_;
    return if !exists $args{disk};

    die "ERROR: Low Disk '$args{disk}' required 1 Gb " if $args{disk} < 1024*1024;
}


sub _check_create_domain {
    my $self = shift;

    my %args = @_;

    $self->_check_readonly(@_);

    $self->_check_require_base(@_);
    $self->_check_memory(@_);
    $self->_check_disk(@_);

}

sub _check_require_base {
    my $self = shift;

    my %args = @_;
    return if !$args{id_base};

    my $base = $self->search_domain_by_id($args{id_base});
    die "ERROR: Domain ".$self->name." is not base"
            if !$base->is_base();

}

=head2 file_exists

Return true if the file exists in the storage pool in the VM

=cut

sub file_exists {
    my $self = shift;
    my $file = shift;

    return -e $file && -s $file if $self->_localhost;

    my @cmd = ('test','-e',$file,'&&','test','-s',$file,'&&','echo','ok');

    my $out = $self->_run_remote(@cmd);
    return $out =~ /ok/i;
}

sub _run_remote {
    my $self = shift;
    my @cmd = @_;

    my $ssh = Net::SSH2->new();
#    $ssh->timeout(1000);
    $ssh->connect($self->host) or die $ssh->die_with_error;
    $ssh->auth_publickey('root',$ENV{HOME}."/.ssh/id_rsa.pub",$ENV{HOME}.'/.ssh/id_rsa');
    my $chan = $ssh->channel();

    warn "Executing in ".$self->host."\n"
        .join(" ",@cmd);
    $chan->exec(join(" ",@cmd)) or die $ssh->die_with_error;
    $chan->send_eof();
    
    my $out = '';
    while (<$chan>) {
        $out .= $_;
    }
#    warn "exit status: ".$chan->exit_status;
    my $stderr;
    my $err = $chan->read(\$stderr,1000,1);
#    warn $err if $err;

    return $out;
}



1;
