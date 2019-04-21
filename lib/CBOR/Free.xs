#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

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

SV *_init_length_buffer( UV num, const char type, SV *buffer ) {
    if ( num < 0x18 ) {
        char cnum = (char) num;
        cnum += type;

        if (buffer) {
            sv_catpvn_flags( buffer, &cnum, 1, SV_CATBYTES );
        }
        else {
            buffer = newSVpv( &cnum, 1);
        }
    }
    else if ( num <= 0xff ) {
        char hdr[2] = { type + 0x18, (char) num };

        if (buffer) {
            sv_catpvn_flags( buffer, hdr, 2, SV_CATBYTES );
        }
        else {
            buffer = newSVpv( hdr, 2 );
        }
    }
    else if ( num <= 0xffff ) {
        char hdr[3] = { type + 0x19 };

        uint16_t native = htons(num);

        memcpy( 1 + hdr, &native, 2 );

        if (buffer) {
            sv_catpvn_flags( buffer, hdr, 3, SV_CATBYTES );
        }
        else {
            buffer = newSVpv( hdr, 3 );
        }
    }
    else if ( num <= 0xffffffff ) {
        char hdr[5] = { type + 0x1a };

        uint32_t native = htonl(num);

        memcpy( 1 + hdr, &native, 4 );

        if (buffer) {
            sv_catpvn_flags( buffer, hdr, 5, SV_CATBYTES );
        }
        else {
            buffer = newSVpv( hdr, 5 );
        }
    }
    else {
        // TODO: 64-bit
    }

    return buffer;
}

SV *_encode( SV *value, SV *buffer ) {
    SV *RETVAL;

    if (!SvROK(value)) {

        if (SVt_NULL == SvTYPE(value)) {
            if (buffer) {
                sv_catpvn( buffer, "\xf6", 1 );
                RETVAL = buffer;
            }
            else {
                RETVAL = newSVpv("\xf6", 1);
            }
        }
        //else if (0 == SvCUR(value)) {
        //    RETVAL = newSVpv("\x40", 1);
        //}
        else if (SvIOK(value)) {
            IV val = SvIVX(value);

            if (val < 0) {
                // TODO: fix this for boundaries
                RETVAL = _init_length_buffer( 0 - val, TYPE_NEGINT, buffer );
            }
            else {
                RETVAL = _init_length_buffer( val, TYPE_UINT, buffer );
            }
        }
        else if (SvNOK(value)) {

            // All Perl floats are stored as doubles … apparently?
            NV val = SvNV(value);

            char *valptr = (char *) &val;

            char bytes[9] = { 0xfb, valptr[7], valptr[6], valptr[5], valptr[4], valptr[3], valptr[2], valptr[1], valptr[0] };

            if (buffer) {
                sv_catpvn( buffer, bytes, 9 );
                RETVAL = buffer;
            }
            else {
                RETVAL = newSVpv( bytes, 9 );
            }
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

            RETVAL = _init_length_buffer(
                len,
                (encode_as_text ? TYPE_UTF8 : TYPE_BINARY),
                buffer
            );

            //sv_catpvn( RETVAL, val, len );
            sv_catpvn_flags( RETVAL, val, len, SV_CATBYTES );
        }
    }
    else {
        if (SVt_PVAV == SvTYPE(SvRV(value))) {
            AV *array = (AV *)SvRV(value);
            SSize_t len;
            len = 1 + av_len(array);

            RETVAL = _init_length_buffer( len, TYPE_ARRAY, buffer );

            SSize_t i;

            for (i=0; i<len; i++) {
                SV **cur = av_fetch(array, i, 0);
                _encode( *cur, RETVAL );
            }
        }
        else if (SVt_PVHV == SvTYPE(SvRV(value))) {
            HV *hash = (HV *)SvRV(value);

            char *key;
            I32 key_length;
            SV *cur;

            I32 keyscount = hv_iterinit(hash);

            RETVAL = _init_length_buffer( keyscount, TYPE_MAP, buffer );

            while ((cur = hv_iternextsv(hash, &key, &key_length))) {

                // Store the key.
                _init_length_buffer( key_length, TYPE_BINARY, RETVAL );
                sv_catpvn_flags( RETVAL, key, key_length, SV_CATBYTES );

                _encode( cur, RETVAL );
            }
        }
        else {
            // TODO: fail unrecognized
        }
    }

    return RETVAL;
}

MODULE = CBOR::Free           PACKAGE = CBOR::Free

PROTOTYPES: DISABLE

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
        RETVAL = _encode(value, NULL);
    OUTPUT:
        RETVAL
