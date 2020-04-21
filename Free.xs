#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "cbor_free_common.h"

#include "cbor_free_boolean.h"
#include "cbor_free_encode.h"
#include "cbor_free_decode.h"

#define _PACKAGE "CBOR::Free"

#define CANONICAL_OPT "canonical"
#define CANONICAL_OPT_LEN (sizeof(CANONICAL_OPT) - 1)

#define PRESERVE_REFS_OPT "preserve_references"
#define PRESERVE_REFS_OPT_LEN (sizeof(PRESERVE_REFS_OPT) - 1)

#define SCALAR_REFS_OPT "scalar_references"
#define SCALAR_REFS_OPT_LEN (sizeof(SCALAR_REFS_OPT) - 1)

#define TEXT_KEYS_OPT "text_keys"
#define TEXT_KEYS_OPT_LEN (sizeof(TEXT_KEYS_OPT) - 1)

#define UNUSED(x) (void)(x)

HV *cbf_stash = NULL;

SV* _seqdecode_get( pTHX_ seqdecode_ctx* seqdecode) {
    decode_ctx* decode_state = seqdecode->decode_state;

    decode_state->curbyte = decode_state->start;

    SV *referent = cbf_decode_one( aTHX_ seqdecode->decode_state );

    if (seqdecode->decode_state->incomplete_by) {
        seqdecode->decode_state->incomplete_by = 0;
        return &PL_sv_undef;
    }

    // TODO: Once the lead offset gets big enough,
    // recreate this buffer.
    sv_chop( seqdecode->cbor, decode_state->curbyte );

    advance_decode_state_buffer( aTHX_ decode_state );

    return newRV_noinc(referent);
}

bool
_handle_flag_call( pTHX_ decode_ctx* decode_state, SV* new_setting, U8 flagval ) {
    if (new_setting == NULL || sv_true(new_setting)) {
        decode_state->flags |= flagval;
    }
    else {
        decode_state->flags ^= flagval;
    }

    return( (bool) decode_state->flags & flagval );
}

//----------------------------------------------------------------------

MODULE = CBOR::Free           PACKAGE = CBOR::Free

PROTOTYPES: DISABLE

BOOT:
    cbf_stash = gv_stashpv(_PACKAGE, FALSE);
    newCONSTSUB(cbf_stash, "_MAX_RECURSION", newSVuv( MAX_ENCODE_RECURSE ));


SV *
encode( SV * value, ... )
    CODE:
        uint8_t encode_state_flags = 0;

        U8 i;
        for (i=1; i<items; i++) {
            if (!(i % 2)) continue;

            if ((SvCUR(ST(i)) == CANONICAL_OPT_LEN) && memEQ( SvPV_nolen(ST(i)), CANONICAL_OPT, CANONICAL_OPT_LEN)) {
                ++i;
                if (i<items && SvTRUE(ST(i))) {
                    encode_state_flags |= ENCODE_FLAG_CANONICAL;
                }
            }

            else if ((SvCUR(ST(i)) == TEXT_KEYS_OPT_LEN) && memEQ( SvPV_nolen(ST(i)), TEXT_KEYS_OPT, TEXT_KEYS_OPT_LEN)) {
                ++i;
                if (i<items && SvTRUE(ST(i))) {
                    encode_state_flags |= ENCODE_FLAG_TEXT_KEYS;
                }
            }

            else if ((SvCUR(ST(i)) == PRESERVE_REFS_OPT_LEN) && memEQ( SvPV_nolen(ST(i)), PRESERVE_REFS_OPT, PRESERVE_REFS_OPT_LEN)) {
                ++i;
                if (i<items && SvTRUE(ST(i))) {
                    encode_state_flags |= ENCODE_FLAG_PRESERVE_REFS;
                }
            }

            else if ((SvCUR(ST(i)) == SCALAR_REFS_OPT_LEN) && memEQ( SvPV_nolen(ST(i)), SCALAR_REFS_OPT, SCALAR_REFS_OPT_LEN)) {
                ++i;
                if (i<items && SvTRUE(ST(i))) {
                    encode_state_flags |= ENCODE_FLAG_SCALAR_REFS;
                }
            }
        }

        encode_ctx encode_state = cbf_encode_ctx_create(encode_state_flags);

        RETVAL = newSV(0);

        cbf_encode(aTHX_ value, &encode_state, RETVAL);

        cbf_encode_ctx_free_reftracker( &encode_state );

        // Don’t use newSVpvn here because that will copy the string.
        // Instead, create a new SV and manually assign its pieces.
        // This follows the example from ext/POSIX/POSIX.xs:

        SvUPGRADE(RETVAL, SVt_PV);
        SvPV_set(RETVAL, encode_state.buffer);
        SvPOK_on(RETVAL);
        SvCUR_set(RETVAL, encode_state.len - 1);
        SvLEN_set(RETVAL, encode_state.buflen);

    OUTPUT:
        RETVAL


SV *
decode( SV *cbor )
    CODE:
        RETVAL = cbf_decode( aTHX_ cbor, NULL, false );

    OUTPUT:
        RETVAL

# ----------------------------------------------------------------------

MODULE = CBOR::Free     PACKAGE = CBOR::Free::Decoder

PROTOTYPES: DISABLE

decode_ctx*
new(...)
    CODE:
        RETVAL = create_decode_state( aTHX_ NULL, NULL, CBF_FLAG_SEQUENCE_MODE);

    OUTPUT:
        RETVAL

SV*
decode(decode_ctx* decode_state, SV* cbor)
    CODE:
        renew_decode_state_buffer( aTHX_ decode_state, cbor );
        fprintf(stderr, "decoding; preserve refs? %d\n", decode_state->flags & CBF_FLAG_PRESERVE_REFERENCES);

        RETVAL = cbf_decode_document( aTHX_ decode_state );

    OUTPUT:
        RETVAL

bool
preserve_references(decode_ctx* decode_state, SV* new_setting = NULL)
    CODE:
        RETVAL = _handle_flag_call( aTHX_ decode_state, new_setting, CBF_FLAG_PRESERVE_REFERENCES );

    OUTPUT:
        RETVAL

bool
naive_utf8(decode_ctx* decode_state, SV* new_setting = NULL)
    CODE:
        RETVAL = _handle_flag_call( aTHX_ decode_state, new_setting, CBF_FLAG_NAIVE_UTF8 );

    OUTPUT:
        RETVAL

decode_ctx*
set_tag_handlers(decode_ctx* decode_state, ...)
    CODE:
        if (NULL == decode_state->tag_handler) {
            decode_state->tag_handler = newHV();
        }

        if (!(items % 2)) {
            croak("Odd key-value pair given!");
        }

        UV i;
        for (i=1; i<items; i += 2) {
            HV* tag_handler = decode_state->tag_handler;

            SV* tagnum_sv = ST(i);
            UV tagnum = SvUV(tagnum_sv);

            i++;
            if (i<items) {
                SV* tagcb_sv = ST(i);

                hv_store(
                    tag_handler,
                    (const char *) &tagnum,
                    sizeof(UV),
                    tagcb_sv,
                    0
                );

                SvREFCNT_inc(tagcb_sv);
            }
        }

        RETVAL = decode_state;

    OUTPUT:
        RETVAL

# ----------------------------------------------------------------------

MODULE = CBOR::Free     PACKAGE = CBOR::Free::SequenceDecoder

PROTOTYPES: DISABLE

seqdecode_ctx*
new(...)
    CODE:
        UNUSED(items);

        SV* cbor = newSVpvs("");

        decode_ctx* decode_state = create_decode_state( aTHX_ cbor, NULL, CBF_FLAG_SEQUENCE_MODE);

        seqdecode_ctx* seqdecode;

        Newx( seqdecode, 1, seqdecode_ctx );

        seqdecode->decode_state = decode_state;
        seqdecode->cbor = cbor;

        RETVAL = seqdecode;

    OUTPUT:
        RETVAL

SV *
give(seqdecode_ctx* seqdecode, SV* addend)
    CODE:
        sv_catsv( seqdecode->cbor, addend );

        renew_decode_state_buffer( aTHX_ seqdecode->decode_state, seqdecode->cbor );

        RETVAL = _seqdecode_get( aTHX_ seqdecode);

    OUTPUT:
        RETVAL

SV *
get(seqdecode_ctx* seqdecode)
    CODE:
        RETVAL = _seqdecode_get( aTHX_ seqdecode);

    OUTPUT:
        RETVAL

void
DESTROY(seqdecode_ctx* seqdecode)
    CODE:
        free_decode_state( aTHX_ seqdecode->decode_state);
        SvREFCNT_dec(seqdecode->cbor);

        Safefree(seqdecode);
