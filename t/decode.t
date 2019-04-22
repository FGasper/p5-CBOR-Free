#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use Data::Dumper;

use_ok('CBOR::Free');

my @tests = (

    # uint
    [ "\x00" => 0 ],
    [ "\x01" => 1 ],
    [ "\x17" => 23 ],
    [ "\x18\x18" => 24 ],
    [ "\x18\xfe" => 254 ],
    [ "\x18\xff" => 255 ],
    [ "\x19\x01\x00" => 256 ],
    [ "\x19\xff\xff" => 65535 ],
    [ "\x1a\x00\x01\x00\x00" => 65536 ],
    [ "\x1a\xff\xff\xff\xff" => 0xffffffff ],
);

for my $t (@tests) {
    my ($in, $enc) = @$t;

    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Useqq = 1;
    local $Data::Dumper::Indent = 0;

    _cmpbin( CBOR::Free::decode($in), $enc, sprintf("Decode: %v02x", $in) );
}

sub _cmpbin {
    my ($got, $expect, $label) = @_;

    $_ = sprintf('%v.02x', $_) for ($got, $expect);

    return is( $got, $expect, $label );
}

done_testing;
