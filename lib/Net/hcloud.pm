# This file is licensed under GPLv2. See the COPYING file for details.

=head1 NAME

Net::hcloud - access Hetzner cloud services API

=head1 SYNOPSIS

 # have ~/.hcloudapitoken - recommended to be chmod 0600
 use Net::hcloud;
 for my $img (@{get_images()}) {
    print "$img->{id} $img->{name}\n";
 }
 my $img = get_image(1);
 print "$img->{id} $img->{name}\n";

 my $keys = get_ssh_keys({name=>"mykey"});
 my $key = $keys->[0] || add_ssh_key("mykey", "ssh-rsa AAAA...");
 my $server = add_server("myserver", "cx11", "debian-9",
     {ssh_keys=>[$key->{id}]});
 my $actions = get_server_actions($server->{id});
 my $metrics = get_server_metrics($server->{id}, {type=>"cpu", start=>"2018-01-29T04:42:00Z", end=>"2018-01-29T04:46:00Z"});
 do_server_action($server->{id}, "shutdown");
 del_server($server->{id}); # Danger! kills server

=head1 DESCRIPTION

 This module provides access to several APIs of Hetzner cloud services

 currently it knows about these objects:
 actions servers floating_ips locations datacenters images isos
 server_types ssh_keys volumes networks pricing

 See https://docs.hetzner.cloud/ for which data fields are returned.

=head1 AUTHOR

 Bernhard M. Wiedemann <hcloud-perl@lsmod.de>
 https://github.com/bmwiedemann/hcloud-perl

=head1 FUNCTIONS
=cut

use strict;
package Net::hcloud;
use Carp;
use LWP::UserAgent ();
use URI::Escape;
use JSON::XS;
use base 'Exporter';
our @EXPORT=qw(wait_for wait_for_action add_ssh_key
find_or_add_server add_server
add_floating_ip);

our $VERSION = 0.21;
our $debug = $ENV{HCLOUDDEBUG}||0;
our $baseURI = "https://api.hetzner.cloud/";
our $UA = LWP::UserAgent->new(requests_redirectable=>[],
    parse_head=>0, timeout=>9,
    agent=>"https://github.com/bmwiedemann/hcloud-perl $VERSION");
our $token = `cat ~/.hcloudapitoken`; chomp($token);
our @configfiles = ("/etc/hcloudrc.pm", "$ENV{HOME}/.hcloudrc.pm");


sub wait_for($$$)
{
    my($count, $delay, $sub) = @_;
    for(1..$count) {
        my $ret = &$sub();
        return $ret if $ret;
        sleep($delay);
    }
    confess "timed out waiting";
}
=head2 wait_for_action($actionid, $maxwait)

 wait for an action to leave running state
 returns succeeding action object
 $maxwait defaults to 30 seconds

=cut
sub wait_for_action($;$)
{
    my $actionid = shift;
    my $maxwait = shift || 30;
    wait_for($maxwait, 1, sub{
        my $a = get_action($actionid);
        return undef if $a->{status} eq "running";
        return $a;
    });
}

sub api_req($$;$)
{
    my $method = shift;
    my $uri = $baseURI.shift;
    my $request_body = shift;
    my $request = HTTP::Request->new($method, $uri);
    if($request_body) {
        $request->content(encode_json $request_body);
    }
    $request->header("Authorization", "Bearer $token");
    my $response = $UA->request($request);
    if($debug) {
        print STDERR "Request: $uri\n";
        print STDERR "Request body: ".$request->content()."\n";
        print STDERR "status: ", $response->code, " ", $response->message, "\n";
        for my $h (qw(Content-Type RateLimit-Limit RateLimit-Remaining RateLimit-Reset)) {
            print STDERR $h, ": ", $response->header($h), "\n";
        }
        print STDERR $response->content;
    }
    return decode_json($response->content||"{}");
}

sub api_get($)
{
    return api_req("GET", shift);
}

sub bad_reply($)
{
    print STDERR JSON::XS->new->pretty->canonical->encode( shift );
    confess "bad/unexpected API reply";
}

# in: hashref e.g. {name=>"foo", sort=>"type"}
# out: url-encoded param string: "name=foo&sort=type"
sub hash_to_uri_param($)
{
    my $h = shift;
    return join('&', map {"$_=".uri_escape($h->{$_})} sort keys(%$h));
}

sub req_objects($$;$$$)
{
    my $method = shift;
    my $object = shift;
    my $extra = shift || "";
    if(ref($extra) eq "HASH") {$extra="?".hash_to_uri_param($extra)}
    my $targetkey = shift || $object;
    my $request_body = shift;
    my $result = api_req($method, "v1/$object$extra", $request_body);
    my $r = $result->{$targetkey};
    bad_reply($result) unless $r;
    for my $key (qw(action root_password password wss_url)) {
        if(ref($r) eq "HASH" && $targetkey ne $key && exists $result->{$key}) {
            $r->{$key} ||= $result->{$key};
        }
    }
    return $r;
}

sub get_objects($;$$)
{
    req_objects("GET", shift, shift, shift);
}

sub req_one_object($$$;$$)
{
    my $method = shift;
    my $object = shift;
    my $id = shift;
    my $extra = shift || "";
    my $body = shift;
    confess "missing id" unless $id;
    req_objects($method, "${object}s/$id", $extra, $object, $body);
}

sub get_one_object($$;$)
{
    req_one_object("GET", shift, shift, shift);
}

=head2 get_...s({name=>"foo", sort=>"name:asc"})

 Get a list of objects, e.g. get_servers()

=head2 get_...($id)

 Get one object e.g. get_server($serverid)

=head2 get_server_actions($serverid)

 Get list of actions associated with a server

=head2 get_server_metrics($serverid, {type=>"cpu", start=>"2018-01-29T04:42:00Z", end=>"2018-01-29T04:46:00Z"});

 Get numbers about resource usage

=cut
for my $o (qw(actions servers floating_ips locations datacenters images isos server_types ssh_keys volumes networks pricing)) {
    my $f = "get_${o}";
    eval "sub $f(;\$) { get_objects('${o}', shift) }";
    push(@EXPORT, $f);
    if($o =~m/(.*)s$/) {
        my $singular = $1;
        $f = "get_${singular}";
        eval "sub $f(\$;\$) { get_one_object('${singular}', shift) }";
        push(@EXPORT, $f);
    }
}
for my $o (qw(server floating_ip ssh_key image volume network)) {
    my $f = "del_$o";
    eval qq!sub $f(\$) { my \$id=shift; confess "missing id" unless \$id; api_req("DELETE", "v1/${o}s/\$id") }!;
    push(@EXPORT, $f);
    $f = "update_$o";
    eval qq!sub $f(\$\$) { my \$id=shift;  req_one_object("PUT", "${o}", \$id, undef, shift) }!;
    push(@EXPORT, $f);
}
for my $o (qw(server floating_ip image volume network)) {
    my $f = "get_${o}_actions";
    eval "sub $f(\$;\$) { my \$id=shift; get_objects(\"${o}s/\$id/actions\", shift, 'actions') }";
    push(@EXPORT, $f);
    $f = "do_${o}_action";
    eval "sub $f(\$\$;\$) { my \$id=shift; my \$action=shift; req_objects(\"POST\", \"${o}s/\$id/actions/\$action\", undef, 'action', shift) }";
    push(@EXPORT, $f);
}
for my $o (qw(metrics)) {
    my $f = "get_server_$o";
    eval "sub $f(\$;\$) { my \$id=shift; get_objects(\"servers/\$id/${o}\", shift, '$o') }";
    push(@EXPORT, $f);
}

=head2 add_ssh_key($name, $pubkey)

 Upload a new SSH key with the given name and public_key.
 Returns the new ssh_key object.
 The key id can be used in calls for creating servers
 and enabling the rescue system.

=cut
sub add_ssh_key($$)
{
    my $name = shift;
    my $public_key = shift;
    return req_objects("POST", "ssh_keys", undef, "ssh_key", {name=>$name, public_key=>$public_key});
}

=head2 update_ssh_key($keyid, {name=>$newname})

 Changes the name of a ssh_key to $newname
 Returns the new ssh_key object.

=head2 del_ssh_key($keyid)

 Deletes the ssh_key

=head2 find_or_add_server($name, $type, $image, {datacenter=>1, ssh_keys=>[1234]})

=head2 add_server($name, $type, $image, {datacenter=>1, ssh_keys=>[1234]})

 Create a new server with the last parameter passing optional args

=cut
sub add_server($$$;$)
{
    my $name = shift;
    my $server_type = shift;
    my $image = shift;
    my $optionalargs = shift||{};
    my %args=(name=>$name, server_type=>$server_type, image=>$image, %$optionalargs);
    return req_objects("POST", "servers", undef, "server", \%args);
}

sub find_or_add_server($$$;$)
{
    my $name = shift;
    my $server = get_servers({name=>$name});
    if ($server && @$server) { return $server->[0] }
    add_server($name, shift, shift, shift);
}

=head2 update_server($serverid, {name=>$newname})

 Changes the name of a server to $newname
 Returns the new server object

=head2 do_server_action($serverid, $action, {arg=>"value"})

 Do an action with the server. Possible actions are
 poweron reboot reset shutdown poweroff reset_password enable_rescue
 disable_rescue create_image rebuild change_type enable_backup
 disable_backup attach_iso detach_iso change_dns_ptr

=cut

my $param = '$';
for my $o (qw(poweron reboot reset shutdown poweroff reset_password disable_rescue disable_backup detach_iso
        __marker_for_extra_param__
        enable_rescue create_image rebuild change_type enable_backup attach_iso change_dns_ptr)) {
    if($o eq '__marker_for_extra_param__') { $param = '$;$'; next }
    my $f = "do_server_$o";
    eval "sub $f($param) { my \$id=shift; do_server_action(\$id, \"${o}\", shift) }";
    push(@EXPORT, $f);
}

=head2 do_server_poweron($serverid)

=head2 do_server_reboot($serverid)

=head2 do_server_reset($serverid)

=head2 do_server_shutdown($serverid)

=head2 do_server_poweroff($serverid)

=head2 do_server_reset_password($serverid)

=head2 do_server_enable_rescue($serverid, {ssh_keys=>[$keyid]})

=head2 do_server_disable_rescue($serverid)

=head2 do_server_create_image($serverid, {type=>"snapshot", description=>"foo"})

=head2 do_server_rebuild($serverid, {image=>$imageid})

=head2 do_server_change_type($serverid, {server_type=>"cx21"})

=head2 do_server_enable_backup($serverid, {backup_window=>"02-06"})

=head2 do_server_disable_backup($serverid)

=head2 do_server_attach_iso($serverid, {iso=>"someISOname"})

=head2 do_server_detach_iso($serverid)

=head2 do_server_change_dns_ptr($serverid, {ip=>"1.2.3.4", dns_ptr=>"hostname.fqdn"})

=head2 del_server($serverid)

 Deletes the server, losing all its data.

=head2 add_floating_ip({server=>$serverid, description=>"foo", type=>"ipv6"})

 Create a new floating_ip

=cut
sub add_floating_ip($)
{
    my %args=%{$_[0]};
    $args{type} ||= "ipv4";
    return req_objects("POST", "floating_ips", undef, "floating_ip", \%args);
}

=head2 update_floating_ip($floating_ipid, {description=>$newdescription})

 Changes the description of a floating_ip to $newdescription
 Returns the new object

=head2 do_floating_ip_action($floating_ipid, $action, {arg=>"value"})

 Do an action with the floating_ip. Possible actions are
 assign unassign change_dns_ptr

=cut

for my $o (qw(assign unassign change_dns_ptr)) {
    my $f = "do_floating_ip_$o";
    eval "sub $f(\$;\$) { my \$id=shift; do_floating_ip_action(\$id, \"${o}\", shift) }";
    push(@EXPORT, $f);
}

=head2 do_floating_ip_assign($floating_ipid, {server=>$serverid})

=head2 do_floating_ip_unassign($floating_ipid)

=head2 do_floating_ip_change_dns_ptr($floating_ipid, {ip=>"1.2.3.4", dns_ptr=>"hostname.fqdn"})

=head2 del_floating_ip($floating_ipid)

 Deletes the floating_ip.

=head2 update_image($imageid, {type=>'snapshot', description=>$newdescription})

 Changes the description or type of an image
 Returns the new object

=head2 del_image($imageid)

 Deletes the image.

=head2 add_volume($name, $size, {location=>1, server=>1234, labels=>["foo"], automount=>1})

 Create a new volume with the last parameter passing optional args

=cut
sub add_volume($$;$)
{
    my $name = shift;
    my $size = shift;
    my $optionalargs = shift||{};
    my %args=(name=>$name, size=>$size, %$optionalargs);
    return req_objects("POST", "volumes", undef, "volume", \%args);
}

=head2 do_volume_action($volumeid, $action, {arg=>"value"})

 Do an action with the volume. Possible actions are
 attach detach resize change_protection

=cut

for my $o (qw(attach detach resize change_protection)) {
    my $f = "do_volume_$o";
    eval "sub $f(\$;\$) { my \$id=shift; do_volume_action(\$id, \"${o}\", shift) }";
    push(@EXPORT, $f);
}

=head2 del_volume($volumeid)

 Deletes the volume.

=head2 update_volume($volumeid, {name=>'foo', labels=>["bar"]})

 Changes the name or labels of a volume
 Returns the new object

=head2 add_network($name, $iprange, {labels=>["foo=bar"], subnets=>[{type=>"server", ip_range=>"10.0.1.0/24", network_zone=>"eu-central"}], routes=>[{destination=>"10.100.1.0/24", gateway=>"10.0.1.1"]})

 Create a new network with the last parameter passing optional args

=cut
sub add_network($$;$)
{
    my $name = shift;
    my $iprange = shift;
    my $optionalargs = shift||{};
    my %args=(name=>$name, ip_range=>$iprange, %$optionalargs);
    return req_objects("POST", "networks", undef, "network", \%args);
}

=head2 do_network_action($networkid, $action, {arg=>"value"})

 Do an action with the network. Possible actions are
 add_subnet delete_subnet add_route delete_route change_ip_range change_protection

=cut

for my $o (qw(add_subnet delete_subnet add_route delete_route change_ip_range change_protection)) {
    my $f = "do_network_$o";
    eval "sub $f(\$;\$) { my \$id=shift; do_network_action(\$id, \"${o}\", shift) }";
    push(@EXPORT, $f);
}

=head2 del_network($networkid)

 Deletes the network.

=head2 update_network($networkid, {name=>'foo', labels=>["bar"]})

 Changes the name or labels of a network
 Returns the new object



=head1 ENVIRONMENT

The following environment variables are used by hcloud:

=over

=item HOME

The module will look for .hcloudrc.pm in your home directory.

=item HCLOUDDEBUG

Set to 1 to enable extra verbose output of HTTP queries and responses

=back

=cut

for my $conf (@configfiles) {
    if(-e $conf) {
        do $conf or die "could not parse $conf: $@";
    }
}

1;
