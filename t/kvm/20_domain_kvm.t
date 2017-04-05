use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $BACKEND = 'KVM';

use_ok('Ravada');
use_ok("Ravada::Domain::$BACKEND");

my $test = Test::SQL::Data->new( config => 't/etc/sql.conf');

my $RAVADA = rvd_back($test->connector , 't/etc/ravada.conf');
my $USER = create_user('foo','bar');

sub test_vm_kvm {
    my $vm = $RAVADA->search_vm('kvm');
    ok($vm,"No vm found") or exit;
    ok(ref($vm) =~ /KVM$/,"vm is no kvm ".ref($vm)) or exit;

    ok($vm->type, "Not defined $vm->type") or exit;
    ok($vm->host, "Not defined $vm->host") or exit;

}
sub test_remove_domain {
    my $name = shift;
    my $user = (shift or $USER);

    my $domain;
    $domain = $RAVADA->search_domain($name,1);

    if ($domain) {
        diag("Removing domain $name");
        eval { $domain->remove($user) };
        ok(!$@,"Domain $name should be removed ".$@) or exit;
    }
    $domain = $RAVADA->search_domain($name);
    die "I can't remove old domain $name"
        if $domain;

    ok(!search_domain_db($name),"Domain $name still in db");
}

sub test_remove_domain_by_name {
    my $name = shift;

    diag("Removing domain $name");
    $RAVADA->remove_domain(name => $name, uid => $USER->id);

    my $domain = $RAVADA->search_domain($name, 1);
    die "I can't remove old domain $name"
        if $domain;

}

sub search_domain_db
 {
    my $name = shift;
    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($name);
    my $row =  $sth->fetchrow_hashref;
    return $row;

}

sub test_new_domain {
    my $active = shift;

    my $name = new_domain_name();

    test_remove_domain($name);

    diag("Creating domain $name");
    my $domain = $RAVADA->create_domain(name => $name, id_iso => 1, active => $active
        , id_owner => $USER->id
        , vm => $BACKEND
    );

    ok($domain,"Domain not created");
    my $exp_ref= 'Ravada::Domain::KVM';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;

    my @cmd = ('virsh','desc',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");

    my $row =  search_domain_db($domain->name);
    ok($row->{name} && $row->{name} eq $domain->name,"I can't find the domain at the db");

    my $domain2 = $RAVADA->search_domain($domain->name);
    ok($domain2->id eq $domain->id,"Expecting id = ".$domain->id." , got ".$domain2->id);
    ok($domain2->name eq $domain->name,"Expecting name = ".$domain->name." , got "
        .$domain2->name);

    return $domain;
}

sub test_prepare_base {
    my $domain = shift;
    $domain->prepare_base($USER);

    my $sth = $test->dbh->prepare("SELECT is_base FROM domains WHERE name=? ");
    $sth->execute($domain->name);
    my ($is_base) =  $sth->fetchrow;
    ok($is_base
            ,"Expecting is_base=1 got "
            .(${is_base} or '<UNDEF>'));
    $sth->finish;
}


sub test_domain_inactive {
    my $vm = shift;
    my $domain = test_domain($vm, 0);
}

sub test_domain{
    my $vm =shift or confess "Missing VM";
    my $active = shift;
    $active = 1 if !defined $active;

    my $n_domains = scalar $vm->list_domains();
    my $domain = test_new_domain($active);

    if (ok($domain,"test domain not created")) {
        my @list = $vm->list_domains();
        ok(scalar(@list) == $n_domains + 1,"Found ".scalar(@list)." domains, expecting "
            .($n_domains+1)
            ." "
            .join(" * ", sort map { $_->name } @list)
        ) or exit;
        ok(!$domain->is_base,"Domain shouldn't be base "
            .Dumper($domain->_select_domain_db()));

        # test list domains
        my @list_domains = $vm->list_domains();
        ok(@list_domains,"No domains in list");
        my $list_domains_data = $RAVADA->list_domains_data();
        ok($list_domains_data && $list_domains_data->[0],"No list domains data ".Dumper($list_domains_data));
        my $is_base = $list_domains_data->[0]->{is_base} if $list_domains_data;
        ok($is_base eq '0',"Mangled is base '$is_base', it should be 0 "
            .Dumper($list_domains_data));

        ok(!$domain->is_active  ,"domain should be inactive") if defined $active && $active==0;
        ok($domain->is_active   ,"domain should be active")   if defined $active && $active==1;

        # test prepare base
        test_prepare_base($domain);
        ok($domain->is_base,"Domain should be base"
            .Dumper($domain->_select_domain_db())

        );
 
        ok(test_domain_in_virsh($domain->name,$domain->name)," not in virsh list all");
        my $domain2;
        $vm->connect();
        eval { $domain2 = $vm->vm->get_domain_by_name($domain->name)};
        ok($domain2,"Domain ".$domain->name." missing in VM") or exit;

        test_remove_domain($domain->name);
    }
}

sub test_domain_in_virsh {
    my $name = shift;
    my $vm = $RAVADA->search_vm('kvm');

    $vm->connect();
    for my $domain ($vm->vm->list_all_domains) {
        if ( $domain->get_name eq $name ) {
            $vm->disconnect;
            return 1 
        }
    }
    $vm->disconnect();
    return 0;
}

sub test_domain_missing_in_db {
    # test when a domain is in the VM but not in the DB

    my $active = shift;
    $active = 1 if !defined $active;

    my $n_domains = scalar $RAVADA->list_domains();
    my $domain = test_new_domain($active);
    ok($RAVADA->list_domains > $n_domains,"There should be more than $n_domains");

    if (ok($domain,"test domain not created")) {

        my $sth = $test->connector->dbh->prepare("DELETE FROM domains WHERE id=?");
        $sth->execute($domain->id);

        my $domain2 = $RAVADA->search_domain($domain->name);
        ok(!$domain2,"This domain should not show up in Ravada, it's not in the DB");

        my $vm = $RAVADA->search_vm('kvm');
        my $domain3;
        $vm->connect();
        eval { $domain3 = $vm->vm->get_domain_by_name($domain->name)};
        ok($domain3,"I can't find the domain in the VM") or return;

        my @list_domains = $RAVADA->list_domains;
        ok($RAVADA->list_domains == $n_domains,"There should be only $n_domains domains "
                                        .", there are ".scalar(@list_domains));

        test_remove_domain($domain->name, user_admin());
    }
}


sub test_domain_by_name {
    my $domain = test_new_domain();

    if (ok($domain,"test domain not created")) {
        test_remove_domain_by_name($domain->name);
    }
}

sub test_prepare_import {
    my $domain = test_new_domain();

    if (ok($domain,"test domain not created")) {

        test_prepare_base($domain);
        ok($domain->is_base,"Domain should be base"
            .Dumper($domain->_select_domain_db())

        );

        test_remove_domain($domain->name);
    }

}

################################################################

init_ip();

remove_old_domains();
remove_old_disks();

my @host = ('localhost');
push @host,(remote_ip) if remote_ip;

for my $host (@host) {

    my ($vm, $vm_real);
    eval { 
        my $vm = $RAVADA->add_vm( name => "KVM_$host", type => 'KVM', host => $host) ;
        $vm_real  = $vm->vm if $vm;

    } if $RAVADA;
    warn $@ if $@;
    SKIP: {
        my $msg = "SKIPPED test: No KVM backend found at $host";
        if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm_real;
        skip $msg,11    if !$vm_real;
    
        next if !$vm;
        test_vm_kvm()   if $host eq 'localhost';
    
        test_domain($vm);
        test_domain_missing_in_db();
        test_domain_inactive($vm);
        test_domain_by_name();
        test_prepare_import();
    
    };
}

remove_old_domains();
remove_old_disks();
    
done_testing();
