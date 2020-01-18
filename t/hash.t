#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;

use Data::Dumper;

use_ok('CBOR::Free');

my @tests = (
    [ {} => "\xa0" ],
    [ { a => 12 } => "\xa1\x41\x61\x0c"],
    [ { a => [12] } => "\xa1\x41\x61\x81\x0c"],
);

for my $t (@tests) {
    my ($in, $enc) = @$t;

    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Useqq = 1;
    local $Data::Dumper::Indent = 0;

    _cmpbin( CBOR::Free::encode($in), $enc, "Encode: " . Dumper($in) );
}

#----------------------------------------------------------------------

my $empty_upgraded = "";
utf8::upgrade($empty_upgraded);

my $nul_upgraded = "\0";
utf8::upgrade($nul_upgraded);

my @canonical_tests = (
    [
        { a => 1, aa => 4, b => 7, c => 8 },
        "\xa4 \x41a \x01 \x41b \x07 \x41c \x08 \x42aa \x04",
    ],
    [
        { "\0" => 0, "\0\0" => 0, "a\0a" => 0, "a\0b" => 1, },
        "\xa4 \x41\0 \0 \x42\0\0 \0 \x43a\0a \0 \x43a\0b \1",
    ],
    [
        { q<1> => 1, "2" => 2, "\xff" => 3,
            $empty_upgraded => 4, $nul_upgraded => 5,
        },
        "\xa5 \x41 1 \1 \x41 2 \2 \x41 \xff \3 \x60 \4 \x61\0 \5",
    ],
);

$_->[1] =~ s< ><>g for @canonical_tests;

for my $t (@canonical_tests) {
    my ($in, $enc) = @$t;

    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Useqq = 1;
    local $Data::Dumper::Indent = 0;

    _cmpbin( CBOR::Free::encode($in, canonical => 1), $enc, "Encode canonical (first arg): " . Dumper($in) );

    _cmpbin( CBOR::Free::encode($in, hahaha => 0, canonical => 1), $enc, "Encode canonical (later arg): " . Dumper($in) );
}

#----------------------------------------------------------------------

{
    my $hash_w_text_key = { "\x{100}" => '123' };
    my $cbor = CBOR::Free::encode($hash_w_text_key);

    is(
        $cbor,
        "\xa1\x62\xc4\x80C123",
        'hash w/ text key encoded as expected',
    ) or diag explain sprintf('%v.02x', $cbor);
}

#----------------------------------------------------------------------

sub _cmpbin {
    my ($got, $expect, $label) = @_;

    $_ = sprintf('%v.02x', $_) for ($got, $expect);

    return is( $got, $expect, $label );
}

done_testing;
