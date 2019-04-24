#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::FailWarnings;

use CBOR::Free;

my $narcissus = [];
push @$narcissus, $narcissus;

throws_ok(
    sub { CBOR::Free::encode($narcissus) },
    'CBOR::Free::X::Recursion',
    'recursive object triggers recursion error',
);

my $a = [];
my $b = [$a];
push @$a, $b;

throws_ok(
    sub { CBOR::Free::encode($a) },
    'CBOR::Free::X::Recursion',
    'object that recurses with another object triggers recursion error',
);

#----------------------------------------------------------------------

my $weird = bless( [], 'Weird' );

throws_ok(
    sub { diag sprintf('%v.02x', CBOR::Free::encode($weird)) },
    'CBOR::Free::X::Unrecognized',
    'unrecognized object triggers expected error',
);

#----------------------------------------------------------------------

my @incompletes = (
    [ "\x18" => 'small uint', 1 ],
    [ "\x19" => 'medium uint', 2 ],
    [ "\x19a" => 'medium uint', 1 ],
    [ "\x1a" => 'large uint', 4 ],
    [ "\x1az" => 'large uint', 3 ],
    [ "\x1azz" => 'large uint', 2 ],
    [ "\x1azzz" => 'large uint', 1 ],
    [ "\x1b" => 'huge uint', 8 ],
    [ "\x1bz" => 'huge uint', 7 ],
    [ "\x1bzz" => 'huge uint', 6 ],
    [ "\x1bzzz" => 'huge uint', 5 ],
    [ "\x1bzzzz" => 'huge uint', 4 ],
    [ "\x1bzzzzz" => 'huge uint', 3 ],
    [ "\x1bzzzzzz" => 'huge uint', 2 ],
    [ "\x1bzzzzzzz" => 'huge uint', 1 ],

    [ "\x38" => 'small negint', 1 ],
    [ "\x39" => 'medium negint', 2 ],
    [ "\x39a" => 'medium negint', 1 ],
    [ "\x3a" => 'large negint', 4 ],
    [ "\x3az" => 'large negint', 3 ],
    [ "\x3azz" => 'large negint', 2 ],
    [ "\x3azzz" => 'large negint', 1 ],
    [ "\x3b" => 'huge negint', 8 ],
    [ "\x3bz" => 'huge negint', 7 ],
    [ "\x3bzz" => 'huge negint', 6 ],
    [ "\x3bzzz" => 'huge negint', 5 ],
    [ "\x3bzzzz" => 'huge negint', 4 ],
    [ "\x3bzzzzz" => 'huge negint', 3 ],
    [ "\x3bzzzzzz" => 'huge negint', 2 ],
    [ "\x3bzzzzzzz" => 'huge negint', 1 ],

    #----------------------------------------------------------------------

    [ "\x41" => 'tiny binary string (missing string)', 1 ],
    [ "\x47z" => 'tiny binary string (short string)', 6 ],

    [ "\x58" => 'small binary string (number)', 1 ],
    [ "\x58\1" => 'small binary string (missing string)', 1 ],
    [ "\x58\7z" => 'small binary string (short string)', 6 ],

    [ "\x59" => 'medium binary string (number)', 2 ],
    [ "\x59a" => 'medium binary string (number)', 1 ],
    [ "\x59\0\1" => 'medium binary string (missing string)', 1 ],
    [ "\x59\0\7z" => 'medium binary string (short string)', 6 ],

    [ "\x5a" => 'large binary string (number)', 4 ],
    [ "\x5az" => 'large binary string (number)', 3 ],
    [ "\x5azz" => 'large binary string (number)', 2 ],
    [ "\x5azzz" => 'large binary string (number)', 1 ],
    [ "\x5a\0\0\0\1" => 'large binary string (missing string)', 1 ],
    [ "\x5a\0\0\0\7z" => 'large binary string (short string)', 6 ],

    [ "\x5b" => 'huge binary string (number)', 8 ],
    [ "\x5bz" => 'huge binary string (number)', 7 ],
    [ "\x5bzz" => 'huge binary string (number)', 6 ],
    [ "\x5bzzz" => 'huge binary string (number)', 5 ],
    [ "\x5bzzzz" => 'huge binary string (number)', 4 ],
    [ "\x5bzzzzz" => 'huge binary string (number)', 3 ],
    [ "\x5bzzzzzz" => 'huge binary string (number)', 2 ],
    [ "\x5bzzzzzzz" => 'huge binary string (number)', 1 ],
    [ "\x5b\0\0\0\0\0\0\0\1" => 'huge binary string (missing string)', 1 ],
    [ "\x5b\0\0\0\0\0\0\0\7z" => 'huge binary string (short string)', 6 ],

    [ "\x5f" => 'indefinite binary string (empty, no termination)', 1 ],
    [ "\x5f\x41z" => 'indefinite binary string (1 piece, no termination)', 1 ],

    #----------------------------------------------------------------------

    [ "\x61" => 'tiny UTF-8 string (missing string)', 1 ],
    [ "\x67z" => 'tiny UTF-8 string (short string)', 6 ],

    [ "\x78" => 'small UTF-8 string (number)', 1 ],
    [ "\x78\1" => 'small UTF-8 string (missing string)', 1 ],
    [ "\x78\7z" => 'small UTF-8 string (short string)', 6 ],

    [ "\x79" => 'medium UTF-8 string (number)', 2 ],
    [ "\x79a" => 'medium UTF-8 string (number)', 1 ],
    [ "\x79\0\1" => 'medium UTF-8 string (missing string)', 1 ],
    [ "\x79\0\7z" => 'medium UTF-8 string (short string)', 6 ],

    [ "\x7a" => 'large UTF-8 string (number)', 4 ],
    [ "\x7az" => 'large UTF-8 string (number)', 3 ],
    [ "\x7azz" => 'large UTF-8 string (number)', 2 ],
    [ "\x7azzz" => 'large UTF-8 string (number)', 1 ],
    [ "\x7a\0\0\0\1" => 'large UTF-8 string (missing string)', 1 ],
    [ "\x7a\0\0\0\7z" => 'large UTF-8 string (short string)', 6 ],

    [ "\x7b" => 'huge UTF-8 string (number)', 8 ],
    [ "\x7bz" => 'huge UTF-8 string (number)', 7 ],
    [ "\x7bzz" => 'huge UTF-8 string (number)', 6 ],
    [ "\x7bzzz" => 'huge UTF-8 string (number)', 5 ],
    [ "\x7bzzzz" => 'huge UTF-8 string (number)', 4 ],
    [ "\x7bzzzzz" => 'huge UTF-8 string (number)', 3 ],
    [ "\x7bzzzzzz" => 'huge UTF-8 string (number)', 2 ],
    [ "\x7bzzzzzzz" => 'huge UTF-8 string (number)', 1 ],
    [ "\x7b\0\0\0\0\0\0\0\1" => 'huge UTF-8 string (missing string)', 1 ],
    [ "\x7b\0\0\0\0\0\0\0\7z" => 'huge UTF-8 string (short string)', 6 ],

    #----------------------------------------------------------------------

    [ "\x81" => 'tiny array (no elements)', 1 ],
    [ "\x82\xf5" => 'tiny array (missing element)', 1 ],
    [ "\x81\x47z" => 'tiny array, incomplete element', 6 ],

    #----------------------------------------------------------------------

    [ "\xa1" => 'tiny map (no elements)', 1 ],
    [ "\xa1\x18" => 'tiny map (incomplete key)', 1 ],
    [ "\xa1\x01" => 'tiny map (missing value)', 1 ],
    [ "\xa1\x01\x47z" => 'tiny map, incomplete value', 6 ],

    #----------------------------------------------------------------------

    [ "\xc0" => 'tiny tag (missing tagged)', 1 ],

    [ "\xd8" => 'small tag (incomplete number)', 1 ],
    [ "\xd8\x20" => 'small tag (missing tagged)', 1 ],

    [ "\xd9" => 'medium tag (incomplete number)', 2 ],
    [ "\xd9a" => 'medium tag (incomplete number)', 1 ],
    [ "\xd9zz" => 'medium tag (missing tagged)', 1 ],

    [ "\xda" => 'large tag (incomplete number)', 4 ],
    [ "\xdaz" => 'large tag (incomplete number)', 3 ],
    [ "\xdazz" => 'large tag (incomplete number)', 2 ],
    [ "\xdazzz" => 'large tag (incomplete number)', 1 ],
    [ "\xdazzzz" => 'large tag (missing tagged)', 1 ],

    [ "\xdb" => 'huge tag (incomplete number)', 8 ],
    [ "\xdbz" => 'huge tag (incomplete number)', 7 ],
    [ "\xdbzz" => 'huge tag (incomplete number)', 6 ],
    [ "\xdbzzz" => 'huge tag (incomplete number)', 5 ],
    [ "\xdbzzzz" => 'huge tag (incomplete number)', 4 ],
    [ "\xdbzzzzz" => 'huge tag (incomplete number)', 3 ],
    [ "\xdbzzzzzz" => 'huge tag (incomplete number)', 2 ],
    [ "\xdbzzzzzzz" => 'huge tag (incomplete number)', 1 ],
    [ "\xdbzzzzzzzz" => 'huge tag (missing tagged)', 1 ],

    #----------------------------------------------------------------------

    [ "\xf9" => 'half-float (missing bytes)', 2 ],
    [ "\xf9z" => 'half-float (missing byte)', 1 ],

    [ "\xfa" => 'float (missing bytes)', 4 ],
    [ "\xfaz" => 'float (missing byte)', 3 ],
    [ "\xfazz" => 'float (missing byte)', 2 ],
    [ "\xfazzz" => 'float (missing byte)', 1 ],

    [ "\xfb" => 'double float (missing bytes)', 8 ],
    [ "\xfbz" => 'double float (missing byte)', 7 ],
    [ "\xfbzz" => 'double float (missing byte)', 6 ],
    [ "\xfbzzz" => 'double float (missing byte)', 5 ],
    [ "\xfbzzzz" => 'double float (missing byte)', 4 ],
    [ "\xfbzzzzz" => 'double float (missing byte)', 3 ],
    [ "\xfbzzzzzz" => 'double float (missing byte)', 2 ],
    [ "\xfbzzzzzzz" => 'double float (missing byte)', 1 ],
);

for my $t (@incompletes) {
    my ($cbor, $label, $lack) = @$t;

    throws_ok(
        sub { CBOR::Free::decode($cbor) },
        'CBOR::Free::X::Incomplete',
        "incomplete: $label (lack: $lack)",
    );

    like( $@->get_message(), qr<$lack>, "… and the error says “$lack”" );
}

done_testing;
