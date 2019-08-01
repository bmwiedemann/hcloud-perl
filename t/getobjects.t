use Test::More tests=>8;
use lib 'lib';
use Net::hcloud;

# FIXME: tests need a token and server available
# and will break when server output changes -> mock it

my $ret = eval {Net::hcloud::get_objects("testinvalid")};
is($ret, undef, "invalid object access must fail");
like  ($@, qr{bad/unexpected API reply at }, "nice error msg");

my $img = get_image(1);
is($img->{name}, "ubuntu-16.04", "get_image");

my $img = get_images();
is($img->[0]->{name}, "ubuntu-16.04", "get_images");

$img = get_images("?name=debian-9");
is($img->[0]->{name}, "debian-9", "get_images with name filter");

$img = get_images({name=>"debian-9"});
is($img->[0]->{name}, "debian-9", "get_images with name filter from ref");

my $pricing = get_pricing();
is($pricing->{currency}, "EUR", "get_pricing");

my $dc = get_datacenters();
is($dc->[0]->{name}, "nbg1-dc3", "get_datacenters");
