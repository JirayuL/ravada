use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');
my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
init($test->connector);

#########################################################3

sub test_defaults {
    my $user= create_user("foo","bar");
    my $rvd_back = rvd_back();

    ok($user->can_clone);
    ok($user->can_change_settings);
    ok($user->can_screenshot);

    ok($user->can_remove);
    ok($user->can_start);

    ok(!$user->can_remove_clone);

    ok(!$user->can_clone_all);
    ok(!$user->can_change_settings_all);
    ok(!$user->can_change_settings_clones);


    ok(!$user->can_screenshot_all);
    ok(!$user->can_grant);

    ok(!$user->can_create_domain);
    ok(!$user->can_remove_all);
    ok(!$user->can_remove_clone_all);

    ok(!$user->can_shutdown_clone);
    ok(!$user->can_shutdown_all);

    ok(!$user->can_hibernate_clone);
    ok(!$user->can_hibernate_all);

    for my $perm (user_admin->list_permissions) {
        if ( $perm =~ m{^(clone|change_settings|screenshot|remove)$}) {
            is($user->can_do($perm),1,$perm);
        } else {
            is($user->can_do($perm),undef,$perm);
        }
    }

    $user->remove();
}

sub test_admin {
    my $user = create_user("foo$$","bar",1);
    ok($user->is_admin);
    for my $perm ($user->list_all_permissions) {
        is($user->can_do($perm->{name}),1);
    }
}

sub test_grant {
    my $user = create_user("bar$$","bar",1);
    ok($user->is_admin);
    for my $perm ($user->list_all_permissions) {
        user_admin()->grant($user,$perm->{name});
        ok($user->can_do($perm->{name}));
        user_admin()->grant($user,$perm->{name});
        ok($user->can_do($perm->{name}));

        user_admin()->revoke($user,$perm->{name});
        is($user->can_do($perm->{name}),0, $perm->{name}) or exit;
        user_admin()->revoke($user,$perm->{name});
        is($user->can_do($perm->{name}),0, $perm->{name}) or exit;

        user_admin()->grant($user,$perm->{name});
        ok($user->can_do($perm->{name}));
        user_admin()->revoke($user,$perm->{name});
        is($user->can_do($perm->{name}),0, $perm->{name});

    }

}

sub test_operator {
    my $usero = create_user("oper$$","bar");
    ok(!$usero->is_operator);
    ok(!$usero->is_admin);

    my $usera = create_user("admin$$","bar",'is admin');
    ok($usera->is_operator);
    ok($usera->is_admin);

    $usera->grant($usero,'shutdown_clone');
    ok($usero->is_operator);
    ok(!$usero->is_admin);

    $usero->remove();
    $usera->remove();
}

sub test_remove_clone {
    my $vm_name = shift;

    my $user = create_user("oper_rm$$","bar");
    my $usera = create_user("admin_rm$$","bar",'is admin');

    my $domain = create_domain($vm_name, $user);
    $domain->prepare_base($user);
    ok($domain->is_base) or return;

    my $clone = $domain->clone(user => $usera,name => new_domain_name());
    eval { $clone->remove($user); };
    like($@,qr(.));

    my $clone2;
    eval { $clone2 = rvd_back->search_domain($clone->name) };
    ok($clone2, "Expecting ".$clone->name." not removed");

    $usera->grant($user,'remove_clone');
    eval { $clone->remove($user); };
    is($@,'');

    eval { $clone2 = rvd_back->search_domain($clone->name) };
    ok(!$clone2, "Expecting ".$clone->name." removed");

    # revoking remove clone permission

    $clone = $domain->clone(user => $usera,name => new_domain_name());
    $usera->revoke($user,'remove_clone');

    eval { $clone->remove($user); };
    like($@,qr(.));

    eval { $clone2 = rvd_back->search_domain($clone->name) };
    ok($clone2, "Expecting ".$clone->name." not removed");

    $clone->remove($usera);
    $domain->remove($usera);

    $user->remove();
    $usera->remove();
}

sub test_shutdown_clone {
    my $vm_name = shift;

    my $user = create_user("oper$$","bar");
    ok(!$user->is_operator);
    ok(!$user->is_admin);

    my $usera = create_user("admin$$","bar",'is admin');
    ok($usera->is_operator);
    ok($usera->is_admin);


    my $domain = create_domain($vm_name, $user);
    $domain->prepare_base($user);
    ok($domain->is_base) or return;

    my $clone = $domain->clone(user => $usera,name => new_domain_name());
    $clone->start($usera)   if !$clone->is_active;

    is($clone->is_active,1) or return;

    eval { $clone->shutdown_now($user); };
    like($@,qr(.));
    is($clone->is_active,1);

    is($clone->is_active,1) or return;

    $usera->grant($user,'shutdown_clone');

    eval { $clone->shutdown_now($user); };
    is($@,'');
    is($clone->is_active,0);


    $clone->start($usera)   if !$clone->is_active;
    is($clone->is_active,1);

    $usera->revoke($user,'shutdown_clone');
    eval { $clone->shutdown_now($user); };
    like($@,qr(.));
    is($clone->is_active,1);

    $clone->remove($usera);
    $domain->remove($user);

    my $domain2 = create_domain($vm_name, $user);
    $domain2->start($user);
    $domain2->shutdown_now($user);
    $domain2->remove($user);

    $user->remove();
    $usera->remove();
}

sub test_remove {
    my $vm_name = shift;

    my $user = create_user("oper_r$$","bar");
    ok(!$user->is_operator);
    ok(!$user->is_admin);

    user_admin()->revoke($user,'remove');

    is($user->can_remove,0) or return;

    # user can't remove own domains
    my $domain = create_domain($vm_name, $user);
    eval { $domain->remove($user)};
    like($@,qr'.');

    # user can't remove domains from others
    my $domain2 = create_domain($vm_name, user_admin());
    eval { $domain2->remove($user)};
    like($@,qr'.');

    # user is granted remove
    user_admin()->grant($user,'remove');
    eval { $domain->remove($user)};
    is($@,'');

    # but can't remove domains from others
    eval { $domain2->remove($user)};
    like($@,qr'.');

    # admin can remove the domain
    eval { $domain2->remove(user_admin())};
    is($@,'');

    $user->remove();

}

sub test_shutdown_all {
    my $vm_name = shift;

    my $user = create_user("oper_sa$$","bar");
    is($user->can_shutdown_all,undef) or return;

    my $usera = create_user("admin_sa$$","bar",1);
    is($usera->can_shutdown_all,1);

    my $domain = create_domain($vm_name, $usera);
    $domain->start($usera)      if !$domain->is_active;
    is($domain->is_active,1)    or return;

    eval { $domain->shutdown_now($user)};
    like($@,qr'.');
    is($domain->is_active,1)    or return;

    $usera->grant($user,'shutdown_all');
    is($user->can_shutdown_all,1) or return;

    eval { $domain->shutdown_now($user)};
    is($@,'');

    is($domain->is_active,0);

    # revoke the grant
    $domain->start($usera)      if !$domain->is_active;
    is($domain->is_active,1);

    $usera->revoke($user,'shutdown_all');
    eval { $domain->shutdown_now($user)};
    like($@,qr'.');
    is($domain->is_active,1);

    $domain->remove($usera);

    $user->remove();
    $usera->remove();

}

sub test_start {
    my $vm_name = shift;

    my $user = create_user("oper_start$$","bar");
    my $usera = create_user("admin_st$$","bar",1);

    my $rvd_back = rvd_back();

    is($user->can_start(),1) or exit;
    is($user->can_start_clone(),undef);
    is($user->can_start_all(),undef);

    my $domain = create_domain($vm_name,$usera);
    $domain->prepare_base($usera);

    my $clone = $domain->clone(name => new_domain_name, user => $usera);
    $clone->shutdown_now($usera)    if $clone->is_active;

    eval { $clone->start($user); };
    is($@,'');
    is($clone->is_active,1) or return;
    
    $clone->shutdown_now($usera)    if $clone->is_active();
    is($clone->is_active,0) or return;

    $usera->revoke($user,'start');
    is($user->can_start(),0);

    eval { $clone->start($user); };
    like($@,qr'.');
    is($clone->is_active,0) or return;
    $clone->shutdown_now($usera);

    $usera->grant($user,'start');
    is($user->can_start(),1);

    # start clone:
    # user allowed to start a clone from owned domain
    my $clone2 = $clone->clone(name => new_domain_name,user => $usera);

    eval { $clone2->start($user); };
    like($@,qr'.');
    is($clone2->is_active,0) or return;

    $usera->grant($user,'start_clone');
    is($user->can_start_clone(),1);

    eval { $clone2->start($user); };
    is($@,'');
    is($clone2->is_active,1) or return;
    $clone2->shutdown_now($user);

    $usera->revoke($user,'start_clone');
    is($user->can_start_clone(),0);

    eval { $clone2->start($user); };
    like($@,qr'.');
    is($clone2->is_active,0) or return;
}

# TODO
sub test_start_all {
}
##########################################################

test_defaults();
test_admin();
test_grant();

test_operator();

test_start('Void');

test_shutdown_clone('Void');
test_shutdown_all('Void');

test_remove('Void');
test_remove_clone('Void');
#test_remove_all('Void');

test_start_all('Void');
done_testing();
