#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <stdio.h>
#include <stdlib.h>

#include <arpa/inet.h>  // for byte order conversions
#include <string.h>

#define TYPE_UINT   0
#define TYPE_NEGINT 0x20
#define TYPE_BINARY 0x40
#define TYPE_UTF8   0x60
#define TYPE_ARRAY  0x80
#define TYPE_MAP    0xa0
#define TYPE_TAG    0xc0
#define TYPE_OTHER  0xe0

#define CBOR_FALSE  "\xf4"
#define CBOR_TRUE   "\xf5"
#define CBOR_NULL   "\xf6"

#define CBOR_DOUBLE 0xfb

#define BOOLEAN_CLASS   "Types::Serialiser::Boolean"

#define MAX_ENCODE_RECURSE 98

#define _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, len) \
    if (buffer) { \
        sv_catpvn_flags( buffer, hdr, len, SV_CATBYTES ); \
    } \
    else { \
        buffer = newSVpv( hdr, len ); \
    }

bool is_big_endian = (htons(256) == (uint16_t) 256);

void _croak_unrecognized(pTHX_ SV *value) {
    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 2);
    PUSHs( sv_2mortal(value) );
    PUTBACK;

    call_pv("CBOR::Free::_die_unrecognized", G_EVAL);

    FREETMPS;
    LEAVE;

    croak(NULL);
}

SV *_init_length_buffer( pTHX_ UV num, const char type, SV *buffer ) {
    if ( num < 0x18 ) {
        char hdr[1] = { type + (char) num };

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 1);
    }
    else if ( num <= 0xff ) {
        char hdr[2] = { type + 0x18, (char) num };

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 2);
    }
    else if ( num <= 0xffff ) {
        char hdr[3] = { type + 0x19 };

        uint16_t native = htons(num);

        memcpy( 1 + hdr, &native, 2 );

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 3);
    }
    else if ( num <= 0xffffffff ) {
        char hdr[5] = { type + 0x1a };

        uint32_t native = htonl(num);

        memcpy( 1 + hdr, &native, 4 );

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 5);
    }
    else {
        // TODO: 64-bit
    }

    return buffer;
}

SV *_init_length_buffer_negint( pTHX_ UV num, SV *buffer ) {
    if ( num > -0x19 ) {
        char hdr[1] = { TYPE_NEGINT + (char) (-1 - num) };

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 1);
    }
    else if ( num >= -0x100 ) {
        char hdr[2] = { TYPE_NEGINT + 0x18, (char) (-1 - num) };

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 2);
    }
    else if ( num >= -0x10000 ) {
        char hdr[3] = { TYPE_NEGINT + 0x19 };

        uint16_t native = htons(-1 - num);

        memcpy( 1 + hdr, &native, 2 );

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 3);
    }
    else if ( num >= -0x100000000 ) {
        char hdr[5] = { TYPE_NEGINT + 0x1a };

        uint32_t native = htonl(-1 - num);

        memcpy( 1 + hdr, &native, 4 );

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 5);
    }
    else {
        // TODO: 64-bit
    }

    return buffer;
}

char encode_recurse = 0;

SV *_encode( pTHX_ SV *value, SV *buffer ) {
    encode_recurse++;
    if (encode_recurse > MAX_ENCODE_RECURSE) {
        encode_recurse = 0;
        call_pv("CBOR::Free::_die_recursion", G_EVAL);
        croak(NULL);
    }

    SV *RETVAL;

    if (!SvROK(value)) {

        if (SVt_NULL == SvTYPE(value)) {
            _INIT_LENGTH_SETUP_BUFFER(buffer, CBOR_NULL, 1);

            RETVAL = buffer;
        }
        else if (SvIOK(value)) {
            IV val = SvIVX(value);

            if (val < 0) {
                RETVAL = _init_length_buffer_negint( aTHX_ val, buffer );
            }
            else {
                RETVAL = _init_length_buffer( aTHX_ val, TYPE_UINT, buffer );
            }
        }
        else if (SvNOK(value)) {

            // All Perl floats are stored as doubles … apparently?
            NV val = SvNV(value);

            char *valptr = (char *) &val;

            if (is_big_endian) {
                char bytes[9] = { CBOR_DOUBLE, valptr[0], valptr[1], valptr[2], valptr[3], valptr[4], valptr[5], valptr[6], valptr[7] };
                _INIT_LENGTH_SETUP_BUFFER(buffer, bytes, 9);
            }
            else {
                char bytes[9] = { CBOR_DOUBLE, valptr[7], valptr[6], valptr[5], valptr[4], valptr[3], valptr[2], valptr[1], valptr[0] };
                _INIT_LENGTH_SETUP_BUFFER(buffer, bytes, 9);
            }

            RETVAL = buffer;
        }
        else if (SvPOK(value)) {
            STRLEN len = SvCUR(value);

            char *val = SvPVX(value);

            bool encode_as_text = SvUTF8(value);
            if (!encode_as_text) {
                STRLEN i;
                for (i=0; i<len; i++) {
                    if (val[i] & 0x80) break;
                }

                // Encode as text if there were no high-bit octets.
                encode_as_text = (i == len);
            }

            RETVAL = _init_length_buffer( aTHX_
                len,
                (encode_as_text ? TYPE_UTF8 : TYPE_BINARY),
                buffer
            );

            sv_catpvn_flags( RETVAL, val, len, SV_CATBYTES );
        }
    }
    else if (sv_isobject(value)) {
        if (sv_derived_from(value, BOOLEAN_CLASS)) {
            char *newbyte = SvIV(SvRV(value)) ? CBOR_TRUE : CBOR_FALSE;

            if (buffer) {
                sv_catpvn_flags( buffer, newbyte, 1, SV_CATBYTES );
                RETVAL = buffer;
            }
            else {
                RETVAL = newSVpv(newbyte, 1);
            }
        }

        // TODO: Support TO_JSON() method?

        else {
            _croak_unrecognized(aTHX_ value);
        }
    }
    else {
        if (SVt_PVAV == SvTYPE(SvRV(value))) {
            AV *array = (AV *)SvRV(value);
            SSize_t len;
            len = 1 + av_len(array);

            RETVAL = _init_length_buffer( aTHX_ len, TYPE_ARRAY, buffer );

            SSize_t i;

            for (i=0; i<len; i++) {
                SV **cur = av_fetch(array, i, 0);
                _encode( aTHX_ *cur, RETVAL );
            }
        }
        else if (SVt_PVHV == SvTYPE(SvRV(value))) {
            HV *hash = (HV *)SvRV(value);

            char *key;
            I32 key_length;
            SV *cur;

            I32 keyscount = hv_iterinit(hash);

            RETVAL = _init_length_buffer( aTHX_ keyscount, TYPE_MAP, buffer );

            while ((cur = hv_iternextsv(hash, &key, &key_length))) {

                // Store the key.
                _init_length_buffer( aTHX_ key_length, TYPE_BINARY, RETVAL );
                sv_catpvn_flags( RETVAL, key, key_length, SV_CATBYTES );

                _encode( aTHX_ cur, RETVAL );
            }
        }
        else {
            _croak_unrecognized(aTHX_ value);
        }
    }

    return RETVAL;
}

//----------------------------------------------------------------------

typedef struct {
    SV* cbor;
    STRLEN size;
    char* curbyte;
    char* end;
} decode_ctx;

void _decode_check_for_overage( pTHX_ decode_ctx* decstate, STRLEN len) {
    if ((len + decstate->curbyte) > decstate->end) {
printf("excess: %ld\n", (len + decstate->curbyte) - decstate->end);
        croak("Excess!!!");
    }
}

SV *_decode( pTHX_ decode_ctx* decstate ) {
    SV *ret;

    _decode_check_for_overage( aTHX_ decstate, 1);

    switch ( *(decstate->curbyte) & 0xe0 ) {
        case TYPE_UINT:
            switch (*(decstate->curbyte)) {
                case 0x18:
                    _decode_check_for_overage( aTHX_ decstate, 2);

                    ret = newSVuv( (unsigned char) *(1 + decstate->curbyte) );
/*
                    ++decstate->curbyte;
                    ret = newSVpv( 1 + decstate->curbyte, *(decstat->curbyte) );
                    decstate->curbyte += 1 + *(decstate->curbyte);

                    _decode_check_for_overage(decstate);
*/

                    decstate->curbyte += 2;
                    break;

                case 0x19:
                    _decode_check_for_overage( aTHX_ decstate, 3);

                    do {
                        uint16_t *num;
                        num = (uint16_t *)(1 + decstate->curbyte);

                        ret = newSVuv(ntohs(*num));
                    } while (0);

                    decstate->curbyte += 3;
                    break;

                case 0x1a:
                    _decode_check_for_overage( aTHX_ decstate, 5);

                    do {
                        uint32_t *num;
                        num = (uint32_t *)(1 + decstate->curbyte);

                        ret = newSVuv(ntohl(*num));
                    } while (0);

                    decstate->curbyte += 5;
                    break;

                case 0x1b:
                    //TODO: 64-bit
                    break;

                case 0x1c:
                case 0x1d:
                case 0x1e:
                case 0x1f:
                    croak("Unrecognized uint byte!");   // TODO
                    break;

                default:
                    ret = newSVuv( *(decstate->curbyte) );
                    ++decstate->curbyte;
            }

            break;
        case TYPE_NEGINT:
            break;
        case TYPE_BINARY:
            break;
        case TYPE_UTF8:
            break;
        case TYPE_ARRAY:
            break;
        case TYPE_MAP:
            break;
        case TYPE_TAG:
            break;
        case TYPE_OTHER:
            break;
    }

    return ret;
}

//----------------------------------------------------------------------

MODULE = CBOR::Free           PACKAGE = CBOR::Free

PROTOTYPES: DISABLE

BOOT:
    HV *stash = gv_stashpvn("CBOR::Free", 10, FALSE);
    newCONSTSUB(stash, "_MAX_RECURSION", newSViv( MAX_ENCODE_RECURSE ));

SV *
fake_encode( SV * value )
    CODE:
        RETVAL = newSVpv("\127", 1);

        sv_catpvn_flags( RETVAL, "abcdefghijklmnopqrstuvw", 23, SV_CATBYTES );
    OUTPUT:
        RETVAL


SV *
encode( SV * value )
    CODE:
        RETVAL = _encode(aTHX_ value, NULL);
    OUTPUT:
        RETVAL


SV *
decode( SV *cbor )
    CODE:
        decode_ctx decode_state = {
            cbor,
            SvCUR(cbor),
            SvPVX(cbor),
            SvEND(cbor)
        };

        RETVAL = _decode( aTHX_ &decode_state );
    OUTPUT:
        RETVAL
