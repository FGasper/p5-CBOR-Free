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

#define STRING_ENCODE_MODE_OPT "string_encode_mode"
#define STRING_ENCODE_MODE_OPT_LEN (sizeof(STRING_ENCODE_MODE_OPT) - 1)

#define UNUSED(x) (void)(x)

const char* const cbf_string_encode_mode_options[] = {
    "sv",
    "encode_text",
    "as_text",
    "as_binary",
};

HV *cbf_stash = NULL;

SV* _seqdecode_get( pTHX_ seqdecode_ctx* seqdecode) {
    decode_ctx* decode_state = seqdecode->decode_state;

    decode_state->curbyte = decode_state->start;

    if (decode_state->flags & CBF_FLAG_PRESERVE_REFERENCES) {
        reset_reflist_if_needed(aTHX_ decode_state);
    }

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

bool _handle_flag_call( pTHX_ decode_ctx* decode_state, SV* new_setting, U8 flagval ) {
    if (new_setting == NULL || sv_true(new_setting)) {
        decode_state->flags |= flagval;
    }
    else {
        decode_state->flags ^= flagval;
    }

    return( !!(decode_state->flags & flagval) );
}

SV * _bless_to_sv( pTHX_ SV *class, void* ptr ) {
    SV *RETVAL = newSV(0);
    sv_setref_pv(RETVAL, SvPV_nolen(class), ptr);

    return RETVAL;
}

static inline void * sv_to_ptr( pTHX_ SV *self) {
    IV tmp = SvIV((SV*)SvRV(self));
    return INT2PTR(void*, tmp);
}

static inline SV* _set_string_decode( pTHX_ SV* self, enum cbf_string_decode_mode new_setting ) {
    decode_ctx* decode_state = (decode_ctx*) sv_to_ptr(aTHX_ self);
    decode_state->string_decode_mode = new_setting;

    return (GIMME_V == G_VOID) ? NULL : newSVsv(self);
}

static inline SV* _seq_set_string_decode( pTHX_ SV* self, enum cbf_string_decode_mode new_setting ) {
    seqdecode_ctx* seqdecode = (seqdecode_ctx*) sv_to_ptr(aTHX_ self);
    seqdecode->decode_state->string_decode_mode = new_setting;

    return (GIMME_V == G_VOID) ? NULL : newSVsv(self);
}

static inline bool _handle_preserve_references( pTHX_ decode_ctx* decode_state, SV* new_setting ) {
    bool RETVAL = _handle_flag_call( aTHX_ decode_state, new_setting, CBF_FLAG_PRESERVE_REFERENCES );

    if (RETVAL) {
        ensure_reflist_exists( aTHX_ decode_state );
    }
    else if (NULL != decode_state->reflist) {
        delete_reflist( aTHX_ decode_state );
    }

    return RETVAL;
}

static inline void _set_tag_handlers( pTHX_ decode_ctx* decode_state, UV items_len, SV** args ) {
    if (!(items_len % 2)) {
        croak("Odd key-value pair given!");
    }

    if (NULL == decode_state->tag_handler) {
        decode_state->tag_handler = newHV();
    }

    UV i;
    for (i=1; i<items_len; i += 2) {
        HV* tag_handler = decode_state->tag_handler;

        SV* tagnum_sv = args[i];
        UV tagnum = SvUV(tagnum_sv);

        i++;
        if (i<items_len) {
            SV* tagcb_sv = args[i];

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
}

//----------------------------------------------------------------------
//----------------------------------------------------------------------

MODULE = CBOR::Free           PACKAGE = CBOR::Free

PROTOTYPES: DISABLE

BOOT:
    cbf_stash = gv_stashpv(_PACKAGE, FALSE);
    newCONSTSUB(cbf_stash, "_MAX_RECURSION", newSVuv( MAX_ENCODE_RECURSE ));

## void
## mutate_utf8( SV *sv)
##     CODE:
##         SV *copy;
##         bool ok;
##         STRLEN len;
## 
##         fprintf(stderr, "original:\n");
##         sv_dump(sv);
##         //----------------------------------------------------------------------
## 
##         fprintf(stderr, "sv_utf8_decode\n");
##         copy = newSVsv(sv);
##         sv_2mortal(copy);
##         ok = sv_utf8_decode(copy);
##         fprintf(stderr, "\tOK? %d\n", ok);
##         if (ok) sv_dump(copy);
## 
##         if (ok) {
##             fprintf(stderr, "sv_utf8_decode, then sv_utf8_downgrade\n");
##             copy = newSVsv(copy);
##             sv_2mortal(copy);
##             ok = sv_utf8_downgrade(copy, 1);
##             fprintf(stderr, "\tOK? %d\n", ok);
##             if (ok) sv_dump(copy);
##         }
## 
##         //----------------------------------------------------------------------
##         fprintf(stderr, "sv_utf8_downgrade\n");
##         copy = newSVsv(sv);
##         sv_2mortal(copy);
##         ok = sv_utf8_downgrade(copy, 1);
##         fprintf(stderr, "\tOK? %d\n", ok);
##         if (ok) sv_dump(copy);
## 
##         //----------------------------------------------------------------------
##         fprintf(stderr, "sv_utf8_encode\n");
##         copy = newSVsv(sv);
##         sv_2mortal(copy);
##         sv_utf8_encode(copy);
##         if (ok) sv_dump(copy);
## 
##         //----------------------------------------------------------------------
##         fprintf(stderr, "sv_utf8_upgrade\n");
##         copy = newSVsv(sv);
##         sv_2mortal(copy);
##         len = sv_utf8_upgrade(copy);
##         fprintf(stderr, "\tlen: %d\n", len);
##         if (ok) sv_dump(copy);
## 
##         //----------------------------------------------------------------------
##         fprintf(stderr, "sv_utf8_upgrade_flags/SV_FORCE_UTF8_UPGRADE\n");
##         copy = newSVsv(sv);
##         sv_2mortal(copy);
##         len = sv_utf8_upgrade_flags(copy, SV_FORCE_UTF8_UPGRADE);
##         fprintf(stderr, "\tlen: %d\n", len);
##         if (ok) sv_dump(copy);

SV *
encode( SV * value, ... )
    CODE:
        uint8_t encode_state_flags = 0;
        enum cbf_string_encode_mode string_encode_mode = CBF_STRING_ENCODE_SV;

        U8 i;
        for (i=1; i<items; i++) {
            if (!(i % 2)) continue;

            if (strEQ( SvPV_nolen(ST(i)), CANONICAL_OPT)) {
                ++i;
                if (i<items && SvTRUE(ST(i))) {
                    encode_state_flags |= ENCODE_FLAG_CANONICAL;
                }
            }

            else if (strEQ( SvPV_nolen(ST(i)), TEXT_KEYS_OPT)) {
                ++i;
                if (i<items && SvTRUE(ST(i))) {
                    encode_state_flags |= ENCODE_FLAG_TEXT_KEYS;
                }
            }

            else if (strEQ( SvPV_nolen(ST(i)), PRESERVE_REFS_OPT)) {
                ++i;
                if (i<items && SvTRUE(ST(i))) {
                    encode_state_flags |= ENCODE_FLAG_PRESERVE_REFS;
                }
            }

            else if (strEQ( SvPV_nolen(ST(i)), SCALAR_REFS_OPT)) {
                ++i;
                if (i<items && SvTRUE(ST(i))) {
                    encode_state_flags |= ENCODE_FLAG_SCALAR_REFS;
                }
            }

            else if (strEQ( SvPV_nolen(ST(i)), STRING_ENCODE_MODE_OPT)) {
                ++i;

                if (i<items) {
                    SV* opt = ST(i);

                    if (SvOK(opt)) {
                        char* optstr = SvPV_nolen(opt);

                        U8 i;
                        for (i=0; i<CBF_STRING_ENCODE__LIMIT; i++) {
                            if (strEQ(optstr, cbf_string_encode_mode_options[i])) {
                                string_encode_mode = i;
                                break;
                            }
                        }

                        if (i == CBF_STRING_ENCODE__LIMIT) {
                            croak("Invalid " STRING_ENCODE_MODE_OPT ": %s", optstr);
                        }
                    }

                }
            }
        }

        encode_ctx encode_state = cbf_encode_ctx_create(encode_state_flags, string_encode_mode);

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

SV*
new(SV *class)
    CODE:
        decode_ctx* decode_state = create_decode_state( aTHX_ NULL, NULL, CBF_FLAG_SEQUENCE_MODE);

        RETVAL = _bless_to_sv( aTHX_ class, (void*)decode_state);

    OUTPUT:
        RETVAL

SV*
decode(decode_ctx* decode_state, SV* cbor)
    CODE:
        decode_state->curbyte = 0;
        renew_decode_state_buffer( aTHX_ decode_state, cbor );

        if (decode_state->flags & CBF_FLAG_PRESERVE_REFERENCES) {
            reset_reflist_if_needed(aTHX_ decode_state);
        }

        RETVAL = cbf_decode_document( aTHX_ decode_state );

    OUTPUT:
        RETVAL

bool
preserve_references(decode_ctx* decode_state, SV* new_setting = NULL)
    CODE:
        RETVAL = _handle_preserve_references( aTHX_ decode_state, new_setting );

    OUTPUT:
        RETVAL

bool
naive_utf8(decode_ctx* decode_state, SV* new_setting = NULL)
    CODE:
        RETVAL = _handle_flag_call( aTHX_ decode_state, new_setting, CBF_FLAG_NAIVE_UTF8 );

    OUTPUT:
        RETVAL

SV *
string_decode_cbor(SV* self)
    CODE:
        RETVAL = _set_string_decode( aTHX_ self, CBF_STRING_DECODE_CBOR );

    OUTPUT:
        RETVAL

SV *
string_decode_never(SV* self)
    CODE:
        RETVAL = _set_string_decode( aTHX_ self, CBF_STRING_DECODE_NEVER );

    OUTPUT:
        RETVAL

SV *
string_decode_always(SV* self)
    CODE:
        RETVAL = _set_string_decode( aTHX_ self, CBF_STRING_DECODE_ALWAYS );

    OUTPUT:
        RETVAL

void
_set_tag_handlers_backend(decode_ctx* decode_state, ...)
    CODE:
        _set_tag_handlers( aTHX_ decode_state, items, &ST(0) );


# ----------------------------------------------------------------------

MODULE = CBOR::Free     PACKAGE = CBOR::Free::SequenceDecoder

PROTOTYPES: DISABLE

SV *
new(SV *class)
    CODE:

        SV* cbor = newSVpvs("");

        decode_ctx* decode_state = create_decode_state( aTHX_ cbor, NULL, CBF_FLAG_SEQUENCE_MODE);

        seqdecode_ctx* seqdecode;

        Newx( seqdecode, 1, seqdecode_ctx );

        seqdecode->decode_state = decode_state;
        seqdecode->cbor = cbor;

        RETVAL = _bless_to_sv( aTHX_ class, (void*)seqdecode);

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

bool
preserve_references(seqdecode_ctx* seqdecode, SV* new_setting = NULL)
    CODE:
        RETVAL = _handle_preserve_references( aTHX_ seqdecode->decode_state, new_setting );

    OUTPUT:
        RETVAL

bool
naive_utf8(seqdecode_ctx* seqdecode, SV* new_setting = NULL)
    CODE:
        RETVAL = _handle_flag_call( aTHX_ seqdecode->decode_state, new_setting, CBF_FLAG_NAIVE_UTF8 );

    OUTPUT:
        RETVAL


SV *
string_decode_cbor(SV* self)
    CODE:
        RETVAL = _seq_set_string_decode( aTHX_ self, CBF_STRING_DECODE_CBOR );

    OUTPUT:
        RETVAL

SV *
string_decode_never(SV* self)
    CODE:
        RETVAL = _seq_set_string_decode( aTHX_ self, CBF_STRING_DECODE_NEVER );

    OUTPUT:
        RETVAL

SV *
string_decode_always(SV* self)
    CODE:
        RETVAL = _seq_set_string_decode( aTHX_ self, CBF_STRING_DECODE_ALWAYS );

    OUTPUT:
        RETVAL

void
_set_tag_handlers_backend(seqdecode_ctx* seqdecode, ...)
    CODE:
        _set_tag_handlers( aTHX_ seqdecode->decode_state, items, &ST(0) );

void
DESTROY(seqdecode_ctx* seqdecode)
    CODE:
        free_decode_state( aTHX_ seqdecode->decode_state);
        SvREFCNT_dec(seqdecode->cbor);

        Safefree(seqdecode);
