use strict;
use Test::More tests=>27;
use lib 'lib';
use Net::hcloud;

our $cleanup = 1;

# tests need a token and internet
# and will break when API output changes

# note: will do write operations on server - run it scarcely

sub ping($)
{
    my ($ip) = @_;
    system(qw(ping -q -c 2 -W 1), $ip);
}
sub ssh($$)
{
    my ($ip, $cmd) = @_;
    system(qw(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -l root), $ip, $cmd);
}

my $keyid = $::keyid or BAIL_OUT('need to set $::keyid in ~/.hcloudrc.pm');
my $server = find_or_add_server("testserver", "cx11", "debian-9", {datacenter=>1, ssh_keys=>[$keyid]});
is($server->{name}, "testserver", "add_server") or BAIL_OUT("server could not be found or created");
{
    my $server2 = find_or_add_server("testserver", "cx11", "debian-9", {datacenter=>1, ssh_keys=>[$keyid]});
    is($server->{id}, $server2->{id}, "found server");
}
SKIP: {
    skip "server not newly created", 3 unless $server->{action};
    my $a = wait_for_action($server->{action}->{id}, 60);
    is($a->{id}, $server->{action}->{id}, "same action returned");
    isnt($a->{finished}, undef, "has finished value");
    is($a->{status}, "success", "add_server has succeeded");
}

my $ip = $server->{public_net}->{ipv4}->{ip};
my $dnsname = "testserver.zq1.de";
SKIP: {
    skip "already has reverse DNS", 3 if $server->{public_net}->{ipv4}->{dns_ptr} eq $dnsname;
    my $ptraction = do_server_action($server->{id}, "change_dns_ptr", {
        ip=>$ip,
        dns_ptr=>$dnsname});
    is($ptraction->{command}, "change_dns_ptr", "ptr action returned");
    $a = wait_for_action($ptraction->{id});
    is($a->{status}, "success", "change_dns_ptr has succeeded");
    my $s = get_server $server->{id};
    is($s->{public_net}->{ipv4}->{dns_ptr}, $dnsname, "server has new DNS name");
}

wait_for(20, 1, sub{0 == ping $ip});

my $flips = get_floating_ips();
my $flip = (grep {$_->{server} == $server->{id}} @$flips)[0];
SKIP: {
    skip "floating IP already assigned", 3 if $flip or @$flips >= 25;
    $flip = add_floating_ip({server=>$server->{id}, description=>"testflip"});
    is($flip->{server}, undef, "flip was not assiged to server");
    my $a = wait_for_action($flip->{action}->{id});
    isnt($a->{finished}, undef, "action has finished value");
    is($a->{status}, "success", "add_floating_ip has succeeded");
    $flip = get_floating_ip($flip->{id});
}
is($flip->{server}, $server->{id}, "flip is assiged to server");
is($flip->{type}, "ipv4", "is IPv4 by default");
is($flip->{description}, "testflip", "flip has description");
is($flip->{blocked}, 0, "flip is not blocked");

my $flipdnsname = "testserverflip.zq1.de";
SKIP: {
    skip "flip already has reverse DNS", 3 if $flip->{dns_ptr}[0]{dns_ptr} eq $flipdnsname;
    my $ptraction = do_floating_ip_action($flip->{id}, "change_dns_ptr", {
        ip=>$flip->{ip},
        dns_ptr=>$flipdnsname});
    is($ptraction->{command}, "change_dns_ptr", "ptr action returned");
    $a = wait_for_action($ptraction->{id});
    is($a->{status}, "success", "flip change_dns_ptr has succeeded");
    my $f = get_floating_ip $flip->{id};
    is($f->{dns_ptr}[0]{dns_ptr}, $flipdnsname, "flip has new DNS name");
}

ssh($ip, "ip addr show dev eth0 | grep $flip->{ip}/32 ||
    ip addr add $flip->{ip}/32 dev eth0");
is($?, 0, "ip addr add");
ping $flip->{ip};
is($?, 0, "ping flip");

{
    my $unassignaction = do_floating_ip_action($flip->{id}, "unassign");
    my $a = wait_for_action($unassignaction->{id});
    is($a->{status}, "success", "flip unassign has succeeded");
    ping $flip->{ip};
    isnt($?, 0, "cannot ping unassigned flip");
}
{
    my $assignaction = do_floating_ip_action($flip->{id}, "assign", {server=>$server->{id}});
    my $a = wait_for_action($assignaction->{id});
    is($a->{status}, "success", "flip assign has succeeded");
    ping $flip->{ip};
    is($?, 0, "can ping assigned flip");
}

SKIP: {
    skip "flip deletion not desired", 2 unless $cleanup;
    ssh($ip, "ip addr del $flip->{ip}/32 dev eth0");
    is($?, 0, "ip addr del");
    del_floating_ip($flip->{id});
    my $no = eval {get_floating_ip($flip->{id})};
    is($no, undef, "flip gone after delete");
}

SKIP: {
    skip "server deletion not desired", 1 unless $cleanup;
    del_server($server->{id});
    my $noserver = eval {get_server($server->{id})};
    is($noserver, undef, "server gone after delete");
}
