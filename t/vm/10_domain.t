use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use JSON::XS;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => $test->connector);

my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
    ,Void => [ ]
);

my $RVD_BACK;

eval { $RVD_BACK = rvd_back($test->connector, $FILE_CONFIG) };
ok($RVD_BACK) or exit;

my $USER = create_user("foo","bar");
ok($USER);

##########################################################

sub test_vm_connect {
    my $vm_name = shift;

    my $class = "Ravada::VM::$vm_name";
    my $obj = {};

    bless $obj,$class;

    my $vm = $obj->new();
    ok($vm);
    ok($vm->host eq 'localhost');
}

sub test_search_vm {
    my $vm_name = shift;
    my $vm_type = shift;

    return if $vm_type eq 'Void';

    my $class = "Ravada::VM::$vm_type";

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find a $vm virtual manager");
    ok(ref $vm eq $class,"Virtual Manager is of class ".(ref($vm) or '<NULL>')
        ." it should be $class");
}


sub test_create_domain {
    my $vm_name = shift;
    my $vm_type = shift;

    ($vm_type) = $vm_name =~ /(\w+)_?/   if !$vm_type;

    confess "Missing vm_type"   if !$vm_type;

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    if (!$ARG_CREATE_DOM{$vm_type}) {
        diag("VM $vm_name should be defined at \%ARG_CREATE_DOM");
        return;
    }
    my @arg_create = @{$ARG_CREATE_DOM{$vm_type}};

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , @{$ARG_CREATE_DOM{$vm_type}})
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or exit;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );


    return $domain;
}

sub test_manage_domain {
    my $vm_name = shift;
    my $domain = shift;

    $domain->start($USER) if !$domain->is_active();
    ok(!$domain->is_locked,"Domain ".$domain->name." should not be locked");

    my $display;
    eval { $display = $domain->display($USER) };
    ok($display,"No display for ".$domain->name." $@");

    ok($domain->is_active(),"[$vm_name] domain should be active");
    $domain->shutdown(user => $USER, timeout => 1);
    ok(!$domain->is_active(),"[$vm_name] domain should not be active");
}

sub test_pause_domain {
    my $vm_name = shift;
    my $domain = shift;

    $domain->start($USER) if !$domain->is_active();
    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active) or return;

    my $display;
    eval { $domain->pause($USER) };
    ok(!$@,"[$vm_name] Pausing domain, expecting '', got '$@'");

    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active);

    ok($domain->is_paused,"[$vm_name] Expecting domain paused, got ".$domain->is_paused);

    eval { $domain->resume($USER) };
    ok(!$@,"[$vm_name] Resuming domain, expecting '', got '$@'");

    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active);

}

sub test_shutdown_paused_domain {
    my $vm_name = shift;
    my $domain = shift;

    $domain->start($USER) if !$domain->is_active();
    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active) or return;

    eval { $domain->pause($USER) };
    ok(!$@,"[$vm_name] Pausing domain, expecting '', got '$@'");

    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active);

    ok($domain->is_paused,"[$vm_name] Expecting domain paused, got ".$domain->is_paused);

    eval { $domain->shutdown(user => $USER, timeout => 2) };
    ok(!$@,"[$vm_name] Shutting down paused domain, expecting '', got '$@'");

    ok(!$domain->is_paused,"[$vm_name] Expecting domain not paused, got ".$domain->is_paused);

    eval { $domain->shutdown_now($USER) };
    ok(!$@,"[$vm_name] Shutting down paused domain, expecting '', got '$@'");

    ok(!$domain->is_active,"[$vm_name] Expecting domain not active, got ".$domain->is_active);

    eval { $domain->shutdown_now($USER) };
    ok(!$@,"[$vm_name] Shutting down paused domain, expecting '', got '$@'");

}

sub test_shutdown_suspended_domain {
    my $vm_name = shift;
    my $domain = shift;

    return if ref($domain) !~ /KVM/i;

    $domain->start($USER) if !$domain->is_active();
    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active) or return;

    eval { $domain->domain->suspend() };
    ok(!$@,"[$vm_name] Pausing domain, expecting '', got '$@'");

    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active);

    ok($domain->is_paused,"[$vm_name] Expecting domain paused, got ".$domain->is_paused);

    eval { $domain->shutdown(user => $USER, timeout => 2) };
    ok(!$@,"[$vm_name] Shutting down paused domain, expecting '', got '$@'");

    ok(!$domain->is_paused,"[$vm_name] Expecting domain not paused, got ".$domain->is_paused);

    eval { $domain->shutdown_now($USER) };
    ok(!$@,"[$vm_name] Shutting down paused domain, expecting '', got '$@'");

    ok(!$domain->is_active,"[$vm_name] Expecting domain not active, got ".$domain->is_active);

    eval { $domain->shutdown_now($USER) };
    ok(!$@,"[$vm_name] Shutting down paused domain, expecting '', got '$@'");

}


sub test_remove_domain {
    my $vm_name = shift;
    my $domain = shift;
    diag("Removing domain ".$domain->name);
    my $domain0 = rvd_back()->search_domain($domain->name);
    ok($domain0, "[$vm_name] Domain ".$domain->name." should be there in ".ref $domain);


    eval { $domain->remove($USER) };
    ok(!$@ , "[$vm_name] Error removing domain ".$domain->name." ".ref($domain).": $@") or exit;

    my $domain2 = rvd_back()->search_domain($domain->name);
    ok(!$domain2, "Domain ".$domain->name." should be removed in ".ref $domain);

}

sub test_search_domain {
    my $domain = shift;
    my $domain0 = rvd_back()->search_domain($domain->name);
    ok($domain0, "Domain ".$domain->name." should be there in ".ref $domain);
};

sub test_json {
    my $vm_name = shift;
    my $domain_name = shift;

    my $domain = rvd_back()->search_domain($domain_name);

    my $json = $domain->json();
    ok($json);
    my $dec_json = decode_json($json);
    ok($dec_json->{name} && $dec_json->{name} eq $domain->name
        ,"[$vm_name] expecting json->{name} = '".$domain->name."'"
        ." , got ".($dec_json->{name} or '<UNDEF>')." for json ".Dumper($dec_json)
    );

    my $vm = rvd_back()->search_vm($vm_name);
    my $domain2 = $vm->search_domain_by_id($domain->id);
    my $json2 = $domain2->json();
    ok($json2);
    my $dec_json2 = decode_json($json2);
    ok($dec_json2->{name} && $dec_json2->{name} eq $domain2->name
        ,"[$vm_name] expecting json->{name} = '".$domain2->name."'"
        ." , got ".($dec_json2->{name} or '<UNDEF>')." for json ".Dumper($dec_json2)
    );

}

sub test_screenshot {
    my $vm_name = shift;
    my $domain= shift;

    return if !$domain->can_screenshot;

    my $file = "/var/tmp/screenshot.$$.png";

    diag("[$vm_name] testing screenshot");
    $domain->start($USER)   if !$domain->is_active;
    sleep 2;

    eval { $domain->screenshot($file) };
    ok(!$@,"[$vm_name] $@");

    $domain->shutdown(user => $USER, timeout => 1);
    ok(-e $file,"[$vm_name] Checking screenshot $file");
    ok(-e $file && -s $file,"[$vm_name] Checking screenshot $file should not be empty")
        and do {
            unlink $file or die "$! unlinking $file";
        };
}

sub test_screenshot_file {
    my $vm_name = shift;
    my $domain= shift;

    return if !$domain->can_screenshot;

    my $file = $domain->_file_screenshot();
    ok($file,"Expecting a screnshot filename, got '".($file or '<UNDEF>'));
}

sub test_change_interface {
    my ($vm_name) = @_;
    return if $vm_name !~ /kvm/i;
    
    my $domain = test_create_domain($vm_name);

    set_bogus_ip($domain);
    eval { $domain->start($USER) };
    ok(!$@,"Expecting error='' after starting domain, got ='".($@ or '')."'") or return;

    my $display = $domain->display($USER);
    like($display,qr{spice://\d+.\d+.});
}

sub set_bogus_ip {
    my $domain = shift;
    my $doc = XML::LibXML->load_xml(string
                            => $domain->domain->get_xml_description) ;
    my @graphics = $doc->findnodes('/domain/devices/graphics');
    is(scalar @graphics,1) or return;
    
    my $bogus_ip = '999.999.999.999';
    $graphics[0]->setAttribute('listen' => $bogus_ip);

    my $listen;
    for my $child ( $graphics[0]->childNodes()) {
        $listen = $child if $child->getName() eq 'listen';
    }
    ok($listen,"Expecting child node listen , got :'".($listen or '')) 
        or return;

    $listen->setAttribute('address' => $bogus_ip);

    $domain->domain->update_device($graphics[0]);
}
#######################################################

init_ip();

remove_old_domains();
remove_old_disks();

my @ips = ( undef );
push @ips, (remote_ip()) if remote_ip();

for my $ip ( @ips ) {
for my $vm_type (qw( Void KVM )) {

    diag("Testing $vm_type VM on ".($ip or 'localhost'));
    my $CLASS= "Ravada::VM::$vm_type";

    use_ok($CLASS) or next;

    my $RAVADA;
    eval { $RAVADA = Ravada->new(@ARG_RVD) };

    my $vm;
    my $vm_name = $vm_type;
    eval { 
        if ($ip) {
            $vm_name = "${vm_type}_$ip";
            $vm = $RAVADA->add_vm( 
                name => $vm_name
                ,type => $vm_type
                ,host => $ip
            ) if $vm_type ne 'Void';
        } else {
            $vm = $RAVADA->search_vm($vm_type);
        }
    } if $RAVADA;
    warn $@ if $@;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_vm_connect($vm_type);
        test_search_vm($vm_name, $vm_type);

        my $domain = test_create_domain($vm_name, $vm_type);
        test_change_interface($vm_name,$domain);
        ok($domain->has_clones==0,"[$vm_name] has_clones expecting 0, got ".$domain->has_clones);
        my $clone1;
        diag("going to clone");
        eval { $clone1 = $domain->clone(user=>$USER,name=>new_domain_name) };
        diag("cloned");
        is($@,'');
        ok($clone1, "Expecting clone ");
        ok($domain->has_clones==1,"[$vm_name] has_clones expecting 1, got ".$domain->has_clones);
        $clone1->shutdown_now($USER);

        my $clone2 = $domain->clone(user=>$USER,name=>new_domain_name);
        ok($clone2, "Expecting clone ");
        ok($domain->has_clones==2,"[$vm_name] has_clones expecting 2, got ".$domain->has_clones);
        $clone2->shutdown_now($USER);

        test_json($vm_name, $domain->name);
        test_search_domain($domain);
        test_screenshot_file($vm_name, $domain);
        test_manage_domain($vm_name, $domain);
        test_screenshot($vm_name, $domain);

        test_shutdown_suspended_domain($vm_name, $domain);
        test_pause_domain($vm_name, $domain);
        test_shutdown_paused_domain($vm_name, $domain);

        test_remove_domain($vm_name, $clone1);
        test_remove_domain($vm_name, $clone2);
        test_remove_domain($vm_name, $domain);
    };
}
}
remove_old_domains();
remove_old_disks();

done_testing();
