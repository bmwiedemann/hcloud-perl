#!/usr/bin/perl -w
use strict;
use JSON::XS;
use Term::ReadLine;
use lib 'lib';
use Net::hcloud;

=head1 NAME

 hcloudcli.pl - the Hetzner Cloud Command Line Interface

=head1 SYNOPIS

 example usage:
 ./hcloudcli.pl help
 ./hcloudcli.pl 'help "add_server"'

 json obj output (-f json is default):
 ./hcloudcli.pl 'get_images'
 ./hcloudcli.pl 'get_images {name=>"debian-9"}'
 ./hcloudcli.pl 'get_image 1'
 ./hcloudcli.pl '(get_images {name=>"debian-9"})->[0]->{id}'
 ./hcloudcli.pl "update_ssh_key 1234, {name=>'foo'}"
 ./hcloudcli.pl 1+2

 formatted value output:
 ./hcloudcli.pl '.raw get_image(1)->{name}'
 ./hcloudcli.pl -f raw 'get_image(1)->{name}'
 ./hcloudcli.pl ".c get 'image', 1, 'name', 'type'"
 ./hcloudcli.pl ".csv get 'images', 'id', 'name'"
 ./hcloudcli.pl ".shell get 'image', 1"
 ./hcloudcli.pl ".yaml get_image 1"

 interactive mode:
 ./hcloudcli.pl

=head1 FILES

 ~/.hcloudapitoken
 mandatory file - must contain only the API token

 ~/.hcloudcli_history
 will be read on startup and every interactive command is appended.
 User needs to create the file to enable history.

=cut

$| = 1;
our $histfile = "$ENV{HOME}/.hcloudcli_history";
our $encoder = JSON::XS->new->allow_nonref->pretty->canonical;
our $defaultoutputformat = "json";
our %outputformatabbrev = (c=>"csv", j=>"json", r=>"raw", s=>"shell", y=>"yaml");
sub jsonout(@) {$encoder->encode($_[0])}
sub rawout(@) { @_, "\n" }
sub flatten_hash($)
{
    return map {
	$_[0]->{$_}||""
    } sort keys(%{$_[0]});
}
sub flatten($);
sub flatten($) {
    my $h = shift;
    if(ref($h) eq "ARRAY") {
        for(my $i=$#$h; $i>=0; $i--) {
            $h->[$i] = flatten($h->[$i]);
        }
    }
    if(ref($h) eq "HASH") {
        foreach my $k (keys %$h) {
            if(ref($h->{$k}) eq "HASH" and $h->{$k}->{id}) {
                $h->{$k} = $h->{$k}->{id};
            }
        }
    }
    return $h;
}

sub csvout(@) {
    my @obj = @_;
    if(ref($obj[0]) ne "ARRAY") { @obj = [@obj] }
    if(ref($obj[0]->[0]) eq "HASH") {
        @obj = map {[flatten_hash(flatten($_))]} @{$obj[0]};
    }
    join("", map {
        join("\t", @$_)."\n"
    } @obj)
}
sub shellout(@) {
    my $o = shift;
    if(ref($o) eq "ARRAY") { $o = $o->[0] }
    flatten($o);
    join("",
        map {
            my $v = $o->{$_}||"";
            $v =~ s/["\\]/\\$&/g;
            "$_=\"$v\"\n"
        }
        (sort keys %$o))
}
sub yamlout(@)
{
    require YAML;
    YAML::Dump(@_);
}

sub run_line($)
{
    my $in = shift;
    my $outfunc;
    my $outputformat = $defaultoutputformat;
    $in =~ s/^\.(\w+)\s+// and $outputformat = $outputformatabbrev{$1}||$1;
    $outfunc = eval "\\&${outputformat}out";
    no strict;
    my @res = eval $in;
    use strict;
    warn $@ if $@;
    print(&$outfunc(@res)) unless $@;
}

if($ARGV[0] and $ARGV[0] eq "-f") {
    shift;
    $defaultoutputformat = shift;
}

# non-interactive mode:
my $exit = 0;
while(@ARGV) {
    $exit = 1;
    run_line(shift);
}
exit(0) if $exit;

# interactive mode:
sub hcloud_completion
{
    my ($text, $state) = @_;
#    print STDERR "text=$text state=$state\n"; # debug
    return Term::ReadLine::Gnu->list_completion_function($text, $state);
}

sub help(;$)
{
    my $search = shift||"";
    if($search) { $search = "| grep -A3 $search" }
    system("perldoc Net::hcloud $search")
}
sub quit() { exit 0 }

sub get($;@)
{
    my $type = shift;
    if($type =~ m/s$/) {
        my $obj = Net::hcloud::get_objects($type);
        if(@_) {
            return map {
                my $oneobj = $_;
                [map {$oneobj->{$_}} @_]
            } @$obj;
        }
        return $obj;
    }
    my $id = shift;
    my $obj = Net::hcloud::get_one_object($type, $id);
    if(@_) {
        return map {$obj->{$_}} @_;
    }
    return $obj;
}

my $term = Term::ReadLine->new('hcloud');
$term->Attribs->{completion_word} = [qw(get help quit), @Net::hcloud::EXPORT];
$term->Attribs->{'completion_entry_function'} = \&hcloud_completion;
$term->read_history($histfile);
my $prompt = "> ";
while ( defined ($_ = $term->readline($prompt)) ) {
    run_line($_);
    $term->append_history(1, $histfile);
}
print "exit\n";
