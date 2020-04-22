#!/usr/bin/env perl

package t::encode_modes;

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;
use Test::Exception;

use parent qw( Test::Class::Tiny );

use Data::Dumper;

use CBOR::Free;

use constant xFF => "\xff";
use constant U_00FF => "\xc3\xbf";

__PACKAGE__->runtests() if !caller;

sub T16_test_given_unchanged {
    for my $mode ( qw( sv encode_text as_text as_binary ) ) {
        my $v = U_00FF;
        my $utf8_flag = utf8::is_utf8($v);
        CBOR::Free::encode($v, string_encode_mode => $mode);
        is( $v, U_00FF, "$mode: given undecoded scalar is unchanged" );
        is( utf8::is_utf8($v), $utf8_flag, "$mode: undecoded scalar internals are unchanged" );

        utf8::decode($v);
        my $v_copy = $v;
        $utf8_flag = utf8::is_utf8($v);
        CBOR::Free::encode($v, string_encode_mode => $mode);
        is( $v, $v_copy, "$mode: given decoded scalar is unchanged" );
        is( utf8::is_utf8($v), $utf8_flag, "$mode: decoded scalar internals are unchanged" );
    }
}

sub T3_test_encode_text {
    my @t = (
        [
            "\x{100}",
            "\x62" . do { utf8::encode( my $v = "\x{100}" ); $v },
            'SvUTF8, wide character',
        ],
        [
            do { utf8::decode( my $v = xFF ); $v },
            "\x62" . U_00FF,
            'SvUTF8',
        ],
        [
            "\xff" => "\x62" . U_00FF,
            '!SvUTF8',
        ],
    );

    for my $t_ar (@t) {
        my ($in, $expect, $label) = @$t_ar;

        my $got = CBOR::Free::encode($in, string_encode_mode => 'encode_text');

        is(
            sprintf('%v.02x', $got),
            sprintf('%v.02x', $expect),
            $label,
        );
    }
}

sub T4_test_wide_character_errors {

    for my $mode ( qw( as_text  as_binary ) ) {
        my @t = (
            [
                "\0hello\x{100}there\xff.",
                "\x62" . U_00FF,
                'SvUTF8 with wide character',
            ],
        );

        for my $t_ar (@t) {
            my ($in, $expect, $label) = @$t_ar;

            throws_ok(
                sub { CBOR::Free::encode($in, string_encode_mode => $mode) },
                'CBOR::Free::X::WideCharacter',
                "$mode: wide character prompts appropriate exception",
            );

            my $str = $@->get_message();

            like(
                $str,
                qr<\\x00 hello \\x\{100\} there \\xff \.>x,
                "$mode: exception message is escaped as expected",
            );
        }
    }
}

sub T2_test_as_text__happy_path {
    my @t = (
        [
            do {
                my $v = "\xc3\xbf";
                utf8::encode($v);
                utf8::decode($v);
                $v;
            },
            "\x62" . U_00FF,
            'SvUTF8',
        ],
        [
            U_00FF() => "\x62" . U_00FF,
            '!SvUTF8',
        ],
    );

    for my $t_ar (@t) {
        my ($in, $expect, $label) = @$t_ar;

        my $got = CBOR::Free::encode($in, string_encode_mode => 'as_text');

        is(
            sprintf('%v.02x', $got),
            sprintf('%v.02x', $expect),
            $label,
        );
    }
}

sub T2_test_as_binary__happy_path {
    my @t = (
        [
            do {
                my $v = "\xc3\xbf";
                utf8::encode($v);
                utf8::decode($v);
                $v;
            },
            "\x42" . U_00FF,
            'SvUTF8',
        ],
        [
            U_00FF() => "\x42" . U_00FF,
            '!SvUTF8',
        ],
    );

    for my $t_ar (@t) {
        my ($in, $expect, $label) = @$t_ar;

        my $got = CBOR::Free::encode($in, string_encode_mode => 'as_binary');

        is(
            sprintf('%v.02x', $got),
            sprintf('%v.02x', $expect),
            $label,
        );
    }
}

1;
