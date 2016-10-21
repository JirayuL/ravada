use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Request');

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $ravada;

my ($DOMAIN_NAME) = $0 =~ m{.*/(.*)\.};
my $DOMAIN_NAME_SON=$DOMAIN_NAME."_son";

my $RVD_BACK = rvd_back( $test->connector , 't/etc/ravada.conf');
my $USER = create_user("foo","bar");

my @ARG_CREATE_DOM = (
        id_iso => 1
        ,id_owner => $USER->id
);


#######################################################################

sub test_empty_request {
    my $request = $ravada->request();
    ok($request);
}

sub test_remove_domain {
    my $vm = shift;
    my $name = shift;

    my $domain = $name if ref($name);
    $domain = $vm->search_domain($name,1);

    if ($domain) {
        diag("Removing domain $name");
        eval { $domain->remove(user_admin()) };
        ok(!$@ , "Error removing domain $name : $@") or exit;

        # TODO check remove files base

    }
    $domain = $vm->search_domain($name,1);
    ok(!$domain, "I can't remove old domain $name");

}

sub test_req_create_domain_iso {
    my $vm_name = shift;

    my $name = new_domain_name();
    diag("Requesting create domain $name");

    $USER->mark_all_messages_read();
    test_unread_messages($USER,0, "[$vm_name] create domain $name");

    my $req = Ravada::Request->create_domain( 
        name => $name
        ,@ARG_CREATE_DOM
    );
    ok($req);
    ok($req->status);

    
    ok(defined $req->args->{name} 
        && $req->args->{name} eq $name
            ,"Expecting args->{name} eq $name "
             ." ,got '".($req->args->{name} or '<UNDEF>')."'");

    ok($req->status eq 'requested'
        ,"Status of request is ".$req->status." it should be requested");

    $ravada->_process_requests_dont_fork();

    wait_request($req);
    $ravada->_wait_pids();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$name);
    test_unread_messages($USER,1, "[$vm_name] create domain $name");

    my $req2 = Ravada::Request->open($req->id);
    ok($req2->{id} == $req->id,"req2->{id} = ".$req2->{id}." , expecting ".$req->id);

    my $vm = $RVD_BACK->search_vm($vm_name);
    my $domain =  $vm->search_domain($name);

    ok($domain,"[$vm_name] I can't find domain $name");
    ok(!$domain->is_locked,"Domain $name should not be locked");

    $USER->mark_all_messages_read();
    return $domain;
}

sub test_req_create_domain {

    my $name = new_domain_name();

    my $req = Ravada::Request->create_domain( 
        name => $name
        ,@ARG_CREATE_DOM
    );
    ok($req);
    ok($req->status);
    ok(defined $req->args->{name} 
        && $req->args->{name} eq $name
            ,"Expecting args->{name} eq $name "
             ." ,got '".($req->args->{name} or '<UNDEF>')."'");

    ok($req->status eq 'requested'
        ,"Status of request is ".$req->status." it should be requested");

    $ravada->_process_requests_dont_fork();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$name);

    my $domain =  $ravada->search_domain($name);

    ok($domain,"Searching for domain $name") or return;
    ok($domain->name eq $name,"Expecting domain name '$name', got ".$domain->name);
    ok(!$domain->is_base,"Expecting domain not base , got: ".$domain->is_base());

    return $domain;
}

sub test_req_prepare_base {
    my $vm = shift;
    my $name = shift;

    my $domain = $vm->search_domain($name);
    ok($domain, "Searching for domain $name, got ".ref($name)) or return;
    ok(!$domain->is_base, "Expecting domain base=0 , got: '".$domain->is_base."'");

    my $req = Ravada::Request->prepare_base(
        id_domain => $domain->id
        ,uid => $USER->id
    );
    ok($req);
    ok($req->status);

    ok($domain->is_locked,"Domain $name should be locked when preparing base");

    $ravada->_process_requests_dont_fork();
    ok(!$req->error,"Expecting error='', got '".$req->error."'");
    ok($domain->is_base, "Expecting domain base=1 , got: '".$domain->is_base."'");
}

sub test_req_create_from_base {
    my $vm = shift;
    my $domain_base = shift;

    my $clone_name = new_domain_name();

    my $req = Ravada::Request->create_domain(
        name => $clone_name
        , vm => $vm->name
        , id_base => $domain_base->id
        , id_owner => $USER->id
    );
    ok($req->status eq 'requested'
        ,"Status of request is ".$req->status." it should be requested");

    $ravada->_process_requests_dont_fork();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$clone_name);

    my $domain =  $ravada->search_domain($clone_name);

    ok($domain,"Searching for domain $clone_name") or return;
    ok($domain->name eq $clone_name
        ,"Expecting domain name '$clone_name', got ".$domain->name);
    ok(!$domain->is_base,"Expecting domain not base , got: ".$domain->is_base());

    return $domain;

}

sub test_volumes {
    my ($vm_name, $domain1 , $domain2) = @_;

    my @volumes1 = $domain1->list_volumes();
    my @volumes2 = $domain2->list_volumes();

    my %volumes1 = map { $_ => 1 } @volumes1;
    my %volumes2 = map { $_ => 1 } @volumes2;

    ok(scalar keys %volumes1 == scalar keys %volumes2
        ,"[$vm_name] Expecting ".scalar(keys %volumes1)." , got ".scalar(keys %volumes2)
        .Dumper(\%volumes1,\%volumes2)) or exit;

}

################################################
eval { $ravada = Ravada->new(connector => $test->connector) };

ok($ravada,"I can't launch a new Ravada");# or exit;

for my $vm_name ( qw(Void KVM)) {
    my $vm;
    eval {
        $vm= $ravada->search_vm($vm_name)  if $ravada;
        @ARG_CREATE_DOM = ( id_iso => 1, vm => $vm_name, id_owner => $USER->id )       if $vm;
    };

    SKIP: {
        my $msg = "SKIPPED: No virtual managers found";
        skip($msg,10)   if !$vm;
    
        diag("Testing requests with ".(ref $vm or '<UNDEF>'));
        remove_old_domains();
        remove_old_disks();
    
        my $domain_base = test_req_create_domain($vm);
        test_req_prepare_base($vm, $domain_base->name)                  if $domain_base;
        my $domain_clone = test_req_create_from_base($vm, $domain_base) if $domain_base;
        test_volumes($vm_name,$domain_base, $domain_clone)              if $domain_base;
    
    };
}

remove_old_domains();
remove_old_disks();

done_testing();