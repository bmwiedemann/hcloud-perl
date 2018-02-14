use Test::More tests=>17;

sub c(@)
{
    die "cannot fork: $!" unless defined ($pid = open(SAFE_KID, "-|"));
    if ($pid == 0) {
        exec('./hcloudcli.pl', @_) or die "can't exec hcloudcli.pl: $!";
    } else {
        local $/ = undef;
        $output = <SAFE_KID>;
        close SAFE_KID; # $? contains status
    }
    return $output;
}

my $arrayin = '[1, "foo"]';
my $hashin = '{a=>4, b=>"foo b"}, {a=>6, b=>1}';
my $hashcsv = "4\tfoo b\n6\t1\n";
my $hashshell = "a=\"4\"\nb=\"foo b\"\n";
is(c('1+2'), "3\n", "default number out");
is(c('-f', 'json', '"foo"."bar"'), "\"foobar\"\n", "json string out");
is(c('.r "foo"."bar"', ".r \@{$arrayin}"), "foobar\n1foo\n", "raw string+array out");
is(c(".j $arrayin"), "[\n   1,\n   \"foo\"\n]\n", "json out");
is(c('.csv (1, 7, "foo")'), "1\t7\tfoo\n", "csv out");
is(c('.s [{key=>{id=>23, name=>"foo"}}]'), "key=\"23\"\n", "flatten array");
is(c('.s {key=>{id=>23, name=>"foo"}}'), "key=\"23\"\n", "flatten hash");
like(c('help'), qr/Bernhard M. Wiedemann.*Create a new server/s, "help");
like(c('help "add_server"'), qr/Create a new server/, "topic-specific help");
is(c('-f', 'csv', '(1, 7, "foo")', $arrayin), "1\t7\tfoo\n1\tfoo\n", "-f csv out");
is(c('.s {name=>"foo bar\\\\slash\"quote", foo=>27}'), "foo=\"27\"\nname=\"foo bar\\\\slash\\\"quote\"\n", "shell out");
is(c(".c $hashin", ".r '--'", ".c [$hashin]"), "${hashcsv}--\n$hashcsv", "hash csv");
is(c(".s $hashin", ".s [$hashin]"), "$hashshell$hashshell", "arrayref hash shell out");
is(c(".y $arrayin", ".y [$hashin]"), "---\n- 1\n- foo\n---\n- a: 4\n  b: foo b\n- a: 6\n  b: 1\n", "arrayref hash yaml");
is(c(".c get 'image', 1, 'name', 'type'"), "ubuntu-16.04\tsystem\n", "get element extraction");
is(c(".c get 'images', 'id'"), "1\n2\n3\n4\n", "get images and csv array output");
#is(c('.raw get_image(1)->{name}'), "ubuntu-16.04\n", "raw image type");
is(c('(get_images {name=>"debian-9"})->[0]->{id}'), "2\n", "get_images");
