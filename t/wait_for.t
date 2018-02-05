use Test::More tests=>1;
use lib 'lib';
use Net::hcloud;

my $ret = wait_for(30, 1, sub{rand()>0.5});
is($ret, 1, "wait_for succeeded");
