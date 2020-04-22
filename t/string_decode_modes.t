#!/usr/bin/env perl

package t::string_decode_modes;

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;
use Test::Exception;

use parent qw( Test::Class::Tiny );

use Data::Dumper;

use CBOR::Free::Decoder;

__PACKAGE__->runtests() if !caller;

sub T11_modes {
    my $cbor_text = "\x62é";
    my $cbor_binary = "\x42é";

    my $decoder = CBOR::Free::Decoder->new();

    my $dec_text = $decoder->decode($cbor_text);
    my $dec_binary = $decoder->decode($cbor_binary);

    is( length($dec_text), 1, 'default: text -> decoded' );
    is( length($dec_binary), 2, 'default: binary -> non-decoded' );

    # ----------------------------------------------------------------------

    #my $ret = $decoder->string_decode_never();
    my $ret = CBOR::Free::Decoder::string_decode_never($decoder);
    is( $ret, $decoder, 'string_decode_never() returns object' );

    $dec_text = $decoder->decode($cbor_text);
    $dec_binary = $decoder->decode($cbor_binary);

    is( length($dec_text), 2, 'string_decode_never: text -> non-decoded' );
    is( length($dec_binary), 2, 'string_decode_never: binary -> non-decoded' );

    # ----------------------------------------------------------------------

    $ret = $decoder->string_decode_always();
    is( $ret, $decoder, 'string_decode_always() returns object' );

    $dec_text = $decoder->decode($cbor_text);
    $dec_binary = $decoder->decode($cbor_binary);

    is( length($dec_text), 1, 'string_decode_always: text -> decoded' );
    is( length($dec_binary), 1, 'string_decode_always: binary -> decoded' );

    #----------------------------------------------------------------------

    $ret = $decoder->string_decode_cbor();
    is( $ret, $decoder, 'string_decode_cbor() returns object' );

    $dec_text = $decoder->decode($cbor_text);
    $dec_binary = $decoder->decode($cbor_binary);

    is( length($dec_text), 1, 'string_decode_cbor: text -> decoded' );
    is( length($dec_binary), 2, 'string_decode_cbor: binary -> non-decoded' );

    return;
}

1;
