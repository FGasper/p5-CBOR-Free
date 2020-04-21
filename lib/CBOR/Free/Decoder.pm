package CBOR::Free::Decoder;

=encoding utf8

=head1 NAME

CBOR::Free::Decoder

=head1 SYNOPSIS

    my $decoder = CBOR::Free::Decoder->new()->set_tag_handlers(
        2 => sub { DateTime->from_epoch( epoch => shift() ) },
    );

    # Enable shared/circular references:
    $decoder->preserve_references();

=head1 DESCRIPTION

This class provides an object-oriented interface to L<CBOR::Free>’s
decoder. This interface allows interpretation of tagged values.

=cut

#----------------------------------------------------------------------

use CBOR::Free ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Creates a new CBOR decoder object.

=cut

#----------------------------------------------------------------------

=head2 $data = I<OBJ>->decode( $CBOR )

Same as L<CBOR::Free>’s static function of the same name but applies
any tag handlers configured in C<set_tag_handlers()>.

As in L<CBOR::Free>, any unrecognized tags prompt a warning but are
otherwise ignored.

=cut

#----------------------------------------------------------------------

=head2 $enabled_yn = I<OBJ>->preserve_references( [$ENABLE] )

Enables/disables recognition of CBOR’s shared references. (If no
argument is given, shared references will be enabled.)

B<HANDLE WITH CARE.> This option can cause CBOR::Free to create circular
references, which can cause memory leaks if not handled properly.

=cut

#----------------------------------------------------------------------

=head2 $enabled_yn = I<OBJ>->naive_utf8( [$ENABLE] )

Same interface as C<preserve_references()>, but this option tells I<OBJ>
to forgo UTF-8 validation of CBOR text strings when enabled. This speeds up
decoding of text strings but may confuse Perl if invalid UTF-8 is given in
a CBOR text string. That may or may not break your application.

This I<should> be safe in contexts—such as IPC—where you control the CBOR
serialization and can thus ensure validity of the encoded text.

If in doubt, leave this off.

=cut

#----------------------------------------------------------------------

=head2 I<OBJ>->set_tag_handlers( %TAG_CALLBACK )

Takes a list of key/value pairs where each key is a tag (i.e., number)
and each value is a coderef that CBOR::Free will run when that tag is
seen during a decode operation. The coderef will receive the tagged value,
and its (scalar) return will be inserted into the decoded data structure.

To unset a tag handler, assign undef to it.

This returns the I<OBJ>.

B<NOTE:> Handlers assigned here will only fire if CBOR::Free itself
doesn’t decode the tag. For example, a handler for the “indirection” tag
here will be ignored.

=cut

1;
