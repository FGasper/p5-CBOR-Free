#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Exception;

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

done_testing;
