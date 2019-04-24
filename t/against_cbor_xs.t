#!/usr/bin/env perl

use Test::More;

use Data::Dumper;

use CBOR::Free;

my $is_64bit = eval { pack 'Q' };

SKIP: {
    skip "CBOR::XS didn’t load: $@" if !eval { require CBOR::XS; 1 };
    skip "Types::Serialiser didn’t load: $@" if !eval { require Types::Serialiser; 1 };

    my @tests = (
        q<>,
        0,
        1,
        1.1,
        -1,
        -24,
        -25,
        -254,
        -255,
        -256,
        -257,
        -65534,
        -65535,
        -65536,
        -65537,
        "\x00",
        "\xff",
        undef,
        Types::Serialiser::true(),
        Types::Serialiser::false(),
        [],
        {},
        [ 0 ],
        [ 0xffffffff ],
        [ (undef) x 65535 ],
        [ (undef) x 65536 ],
        { map { ($_ => undef) } 1 .. 65535 },
        { map { ($_ => undef) } 1 .. 65536 },
        [
            123,
            q<>,
            {
                tiny => 'x',
                tiny2 => ('x' x 23),

                short => ('x' x 24),
                short2 => ('x' x 255),

                medium => ('x' x 256),
                medium2 => ('x' x 65535),

                large => ('x' x 65536),
            },

            [ (undef) x 1 ],
            [ (undef) x 23],
            [ (undef) x 24],
            [ (undef) x 255 ],
            [ (undef) x 256 ],

            { map { ($_ => undef) } 1 .. 1 },
            { map { ($_ => undef) } 1 .. 23},
            { map { ($_ => undef) } 1 .. 24},
            { map { ($_ => undef) } 1 .. 255 },
            { map { ($_ => undef) } 1 .. 256 },
        ],
    );

    for my $item ( @tests ) {
        my ($cbor, $decoded);

        $cbor = CBOR::XS::encode_cbor($item);
        $decoded = CBOR::Free::decode($cbor);

        my $item_q = ref($item) ? "$item" : do {
            local $Data::Dumper::Useqq = 1;
            local $Data::Dumper::Terse = 1;
            local $Data::Dumper::Indent = 0;

            Data::Dumper::Dumper($item);
        };

        is_deeply(
            $decoded,
            $item,
            "we decode what CBOR::XS encoded ($item_q)",
        );

        $cbor = CBOR::Free::encode($item) or die "failed to encode($item)?";
        $decoded = CBOR::XS::decode_cbor($cbor);

        is_deeply(
            $decoded,
            $item,
            sprintf( "CBOR::XS decodes what we encoded (%d bytes)", length $cbor),
        ) or diag sprintf('%v.02x', $cbor);
    }
}

done_testing;
