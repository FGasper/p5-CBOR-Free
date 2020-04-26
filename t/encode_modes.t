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
use constant UTF8_00FF => do { utf8::encode( my $v = xFF ); $v };
use constant U_00FF => do { utf8::upgrade( my $v = "\xff"); $v };

use constant UNICODE_A => do { utf8::upgrade( my $v = "A"); $v };
use constant UNICODE_FF => do { utf8::upgrade( my $v = "\xff"); $v };

use constant UTF8_0100 => do { utf8::encode( my $v = "\x{100}" ); $v };

__PACKAGE__->runtests() if !caller;

sub T16_test_given_unchanged {
    for my $mode ( qw( sv encode_text as_text as_binary ) ) {
        my $v = UTF8_00FF;
        my $utf8_flag = utf8::is_utf8($v);
        CBOR::Free::encode($v, string_encode_mode => $mode);
        is( $v, UTF8_00FF, "$mode: given undecoded scalar is unchanged" );
        is( utf8::is_utf8($v), $utf8_flag, "$mode: undecoded scalar internals are unchanged" );

        utf8::decode($v);
        my $v_copy = $v;
        $utf8_flag = utf8::is_utf8($v);
        CBOR::Free::encode($v, string_encode_mode => $mode);
        is( $v, $v_copy, "$mode: given decoded scalar is unchanged" );
        is( utf8::is_utf8($v), $utf8_flag, "$mode: decoded scalar internals are unchanged" );
    }
}

sub T15_test_encode_text {
    my @t = (
        [
            "\x{100}",
            "\x62" . UTF8_0100,
            'SvUTF8, wide character',
        ],
        [
            do { utf8::decode( my $v = xFF() ); $v },
            "\x62" . UTF8_00FF,
            'SvUTF8',
        ],
        [
            "\xff" => "\x62" . UTF8_00FF,
            '!SvUTF8',
        ],
        [
            { "\x{100}" => 0 },
            "\xa1\x62" . UTF8_0100 . "\0",
            'Hash key - wide character (literal key)',
        ],
        [
            { do { my $v = "\x{100}" } => 0 },
            "\xa1\x62" . UTF8_0100 . "\0",
            'Hash key - wide character (key from variable)',
        ],
        [
            { "\xff" => 0 },
            "\xa1\x62" . UTF8_00FF . "\0",
            'Hash key - non-wide, non-invariant character (stored single-byte)',
        ],
        [
            { U_00FF() => 0 },
            "\xa1\x62" . UTF8_00FF . "\0",
            'Hash key - non-wide, non-invariant character (stored UTF-8)',
        ],
        [
            { UNICODE_A() => 0 },
            "\xa1\x61A\0",
            'Hash key - invariant character (stored as UTF-8)',
        ],
        [
            { A => 0 },
            "\xa1\x61A\0",
            'Hash key - invariant character (not stored as UTF-8)',
        ],
    );

    for my $t_ar (@t) {
        my ($in, $expect, $label) = @$t_ar;

        my %in_copy;

        if ('HASH' eq ref $in) {
            %in_copy = %$in;
            CBOR::Free::_hash_keys_2_sv(\%in_copy);
        }

        my $got = CBOR::Free::encode($in, string_encode_mode => 'encode_text');

        is(
            sprintf('%v.02x', $got),
            sprintf('%v.02x', $expect),
            $label,
        );

        if (%in_copy) {
            $got = CBOR::Free::encode(\%in_copy, string_encode_mode => 'encode_text');

            is(
                sprintf('%v.02x', $got),
                sprintf('%v.02x', $expect),
                "SV keys: $label",
            );
        }
    }
}

sub T12_test_wide_character_errors {

    for my $mode ( qw( as_text  as_binary ) ) {
        my @t = (
            [
                "\0hello\x{100}there\xff.",
                'SvUTF8 with wide character',
            ],
            [
                { "\x{100}" => 1 },
                'Wide character in hash key (string)',
            ],
            [
                { do { my $v = "\x{100}" } => 1 },
                'Wide character in hash key (SV)',
            ],
        );

        for my $t_ar (@t) {
            my ($in, $label) = @$t_ar;

            throws_ok(
                sub { CBOR::Free::encode($in, string_encode_mode => $mode) },
                'CBOR::Free::X::WideCharacter',
                "$mode: wide character prompts appropriate exception",
            );

            my $str = $@->get_message();

            like(
                $str,
                qr<\\x\{100\}>x,
                "$mode: exception message is escaped as expected",
            );
        }
    }
}

sub T5_test_as_text__happy_path {
    my @t = (
        [
            do {
                my $v = "\xc3\xbf";
                utf8::encode($v);
                utf8::decode($v);
                $v;
            },
            "\x62" . UTF8_00FF,
            'SvUTF8 (but code points represent bytes)',
        ],
        [
            UTF8_00FF() => "\x62" . UTF8_00FF,
            '!SvUTF8',
        ],
        [
            { UTF8_0100() => 1 },
            "\xa1\x62" . UTF8_0100 . "\1",
            'hash reference with plain UTF8 code points (SV)',
        ],
        [
            {
                do {
                    my $v = "\x{100}";
                    utf8::encode($v);
                    $v;
                } => 1,
            },
            "\xa1\x62" . UTF8_0100 . "\1",
            'hash reference with plain UTF8 code points',
        ],
        [
            {
                do {
                    my $v = "\x{100}";
                    utf8::encode($v);
                    utf8::upgrade($v);
                    $v;
                } => 1,
            },
            "\xa1\x62" . UTF8_0100 . "\1",
            'hash reference with SvUTF8-encoded UTF8 code points',
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

sub T5_test_as_binary__happy_path {
    my @t = (
        [
            do {
                my $v = "\xc3\xbf";
                utf8::encode($v);
                utf8::decode($v);
                $v;
            },
            "\x42" . UTF8_00FF,
            'SvUTF8',
        ],
        [
            UTF8_00FF() => "\x42" . UTF8_00FF,
            '!SvUTF8',
        ],
        [
            { UTF8_0100() => 1 },
            "\xa1\x42" . UTF8_0100 . "\1",
            'hash reference with plain UTF8 code points (SV)',
        ],
        [
            {
                do {
                    my $v = "\x{100}";
                    utf8::encode($v);
                    $v;
                } => 1,
            },
            "\xa1\x42" . UTF8_0100 . "\1",
            'hash reference with plain UTF8 code points (SV)',
        ],
        [
            {
                do {
                    my $v = "\x{100}";
                    utf8::encode($v);
                    utf8::upgrade($v);
                    $v;
                } => 1,
            },
            "\xa1\x42" . UTF8_0100 . "\1",
            'hash reference with SvUTF8-encoded UTF8 code points',
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
