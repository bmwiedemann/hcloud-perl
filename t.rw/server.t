use strict;
use Test::More tests=>9;
use lib 'lib';
use Net::hcloud;

our $cleanup = 1;

# tests need a token and internet
# and will break when API output changes

# note: will do write operations on server - run it scarcely

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


SKIP: {
    skip "server deletion not desired", 1 unless $cleanup;
    del_server($server->{id});
    my $noserver = eval {get_server($server->{id})};
    is($noserver, undef, "server gone after delete");
}
