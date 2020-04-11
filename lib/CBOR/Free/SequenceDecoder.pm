package CBOR::Free::SequenceDecoder;

use strict;
use warnings;

use CBOR::Free;

sub new {
    my $cbor = q<>;
    my $decoder = _create_seqdecode($cbor);

    return bless [ $decoder, \$cbor ], shift;
}

sub give {
    _give( $_[0][0], $_[1] );

    return $_[0]->_parse_one_wrap();
}

sub get {
    return $_[0]->_parse_one_wrap();
}

#----------------------------------------------------------------------

sub _parse_one_wrap {
    my $got;

    my $ok = eval {
        $got = _parse_one( $_[0][0] );
        1;
    };

    if (!$ok) {
        my $err = $@;

        return undef if eval { $err->isa('CBOR::Free::X::Incomplete') };

        local $@ = $err;
        die;
    }

    return \$got;
}

sub DESTROY {
    my ($self) = @_;

    _free_seqdecode($self->[0]);
}

1;
