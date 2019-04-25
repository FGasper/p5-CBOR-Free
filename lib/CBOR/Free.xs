#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>

#define TYPE_UINT   0
#define TYPE_NEGINT 0x20
#define TYPE_BINARY 0x40
#define TYPE_UTF8   0x60
#define TYPE_ARRAY  0x80
#define TYPE_MAP    0xa0
#define TYPE_TAG    0xc0
#define TYPE_OTHER  0xe0

#define CBOR_HALF_FLOAT 0xf9
#define CBOR_FLOAT      0xfa
#define CBOR_DOUBLE     0xfb

#define CBOR_FALSE      0xf4
#define CBOR_TRUE       0xf5
#define CBOR_NULL       0xf6
#define CBOR_UNDEFINED  0xf7

#define BOOLEAN_CLASS   "Types::Serialiser::Boolean"
#define TAGGED_CLASS    "CBOR::Free::Tagged"

#define MAX_ENCODE_RECURSE 98

#define _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, len) \
    if (buffer) { \
        sv_catpvn( buffer, (char *) hdr, len ); \
    } \
    else { \
        buffer = newSVpvn( (char *) hdr, len ); \
    }

// populated in XS BOOT code below.
bool is_big_endian;

//----------------------------------------------------------------------
// Definitions

typedef struct {
    SV* cbor;
    STRLEN size;
    char* curbyte;
    char* end;
} decode_ctx;

enum enum_sizetype {
    //tiny = 0,
    small = 1,
    medium = 2,
    large = 4,
    huge = 8,
    indefinite = 255,
};

union anyint {
    uint8_t u8;
    uint16_t u16;
    uint32_t u32;
    uint64_t u64;
};

typedef struct {
    enum enum_sizetype sizetype;
    union anyint size;
} struct_sizeparse;

//----------------------------------------------------------------------
// Prototypes
// TODO: Be C99-compliant.

SV *_decode( pTHX_ decode_ctx* decstate );

//----------------------------------------------------------------------

void __croak_fn_args( pTHX_ const char argslen, SV **args ) {
    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 2);

    unsigned char a;
    for (a=0; a<argslen; a++) {
        PUSHs(args[a]);
    }

    PUTBACK;

    call_pv("CBOR::Free::_die", G_EVAL);

    FREETMPS;
    LEAVE;

    croak(NULL);
}

void _croak_unrecognized(pTHX_ SV *value) {
    SV *args[2] = { newSVpvs("Unrecognized"), value };

    __croak_fn_args( aTHX_ 2, args );
}

void _croak_incomplete( pTHX_ STRLEN lack ) {
    SV *args[2] = { newSVpvs("Incomplete"), newSVuv(lack) };

    __croak_fn_args( aTHX_ 2, args );
}

void _croak_invalid_control( pTHX_ decode_ctx* decstate ) {
    const unsigned char ord = (unsigned char) *(decstate->curbyte);
    STRLEN offset = decstate->curbyte - SvPV_nolen(decstate->cbor);

    SV *args[3] = { newSVpvs("InvalidControl"), newSVuv(ord), newSVuv(offset) };

    __croak_fn_args( aTHX_ 3, args );
}

void _croak_invalid_utf8( pTHX_ SV *string ) {
    SV *args[2] = { newSVpvs("InvalidUTF8"), string };
    __croak_fn_args( aTHX_ 2, args );
}

void _decode_check_for_overage( pTHX_ decode_ctx* decstate, STRLEN len) {
    if ((len + decstate->curbyte) > decstate->end) {
        STRLEN lack = (len + decstate->curbyte) - decstate->end;
        _croak_incomplete( aTHX_ lack);
    }
}

//----------------------------------------------------------------------

void _u16_to_buffer( UV num, unsigned char *buffer ) {
    *buffer       = num >> 8;
    *(1 + buffer) = num;
}

void _u32_to_buffer( UV num, unsigned char *buffer ) {
    *buffer       = num >> 24;
    *(1 + buffer) = num >> 16;
    *(2 + buffer) = num >> 8;
    *(3 + buffer) = num;
}

void _u64_to_buffer( UV num, unsigned char *buffer ) {
    *buffer = num >> 56;
    *(1 + buffer) = num >> 48;
    *(2 + buffer) = num >> 40;
    *(3 + buffer) = num >> 32;
    *(4 + buffer) = num >> 24;
    *(5 + buffer) = num >> 16;
    *(6 + buffer) = num >> 8;
    *(7 + buffer) = num;
}

SV *_init_length_buffer( pTHX_ UV num, const unsigned char type, SV *buffer ) {
    if ( num < 0x18 ) {
        unsigned char hdr[1] = { type + (unsigned char) num };

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 1);
    }
    else if ( num <= 0xff ) {
        unsigned char hdr[2] = { type + 0x18, (unsigned char) num };

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 2);
    }
    else if ( num <= 0xffff ) {
        unsigned char hdr[3] = { type + 0x19 };

        _u16_to_buffer( num, 1 + hdr );

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 3);
    }
    else if ( num <= 0xffffffff ) {
        unsigned char hdr[5] = { type + 0x1a };

        _u32_to_buffer( num, 1 + hdr );

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 5);
    }
    else {
        unsigned char hdr[9] = { type + 0x1b };

        _u64_to_buffer( num, 1 + hdr );

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 9);
    }

    return buffer;
}

SV *_init_length_buffer_negint( pTHX_ UV num, SV *buffer ) {
    if ( num > -0x19 ) {
        unsigned char hdr[1] = { TYPE_NEGINT + (unsigned char) (-1 - num) };

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 1);
    }
    else if ( num >= -0x100 ) {
        unsigned char hdr[2] = { TYPE_NEGINT + 0x18, (unsigned char) (-1 - num) };

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 2);
    }
    else if ( num >= -0x10000 ) {
        unsigned char hdr[3] = { TYPE_NEGINT + 0x19 };

        _u16_to_buffer( -1 - num, 1 + hdr );

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 3);
    }
    else if ( num >= -0x100000000 ) {
        unsigned char hdr[5] = { TYPE_NEGINT + 0x1a };

        _u32_to_buffer( -1 - num, 1 + hdr );

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 5);
    }
    else {
        unsigned char hdr[5] = { TYPE_NEGINT + 0x1b };

        _u64_to_buffer( -1 - num, 1 + hdr );

        _INIT_LENGTH_SETUP_BUFFER(buffer, hdr, 9);
    }

    return buffer;
}

uint8_t encode_recurse = 0;

SV *_encode( pTHX_ SV *value, SV *buffer ) {
    ++encode_recurse;
    if (encode_recurse > MAX_ENCODE_RECURSE) {
        encode_recurse = 0;
        call_pv("CBOR::Free::_die_recursion", G_EVAL);
        croak(NULL);
    }

    SV *RETVAL = NULL;

    if (!SvROK(value)) {

        if (!SvOK(value)) {
            char null = CBOR_NULL;
            _INIT_LENGTH_SETUP_BUFFER(buffer, &null, 1);

            RETVAL = buffer;
        }
        else if (SvIOK(value)) {
            IV val = SvIVX(value);

            // In testing, Perl’s (0 + ~0) evaluated as < 0 here,
            // but the SvUOK() check fixes that.
            if (val < 0 && !SvUOK(value)) {
                RETVAL = _init_length_buffer_negint( aTHX_ val, buffer );
            }
            else {
                // NB: SvUOK doesn’t work to identify nonnegatives … ?
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
        else {
            STRLEN len = SvCUR(value);

            char *val = SvPV_nolen(value);

            bool encode_as_text = !!SvUTF8(value);

            /*
            if (!encode_as_text) {
                STRLEN i;
                for (i=0; i<len; i++) {
                    if (val[i] & 0x80) break;
                }

                // Encode as text if there were no high-bit octets.
                encode_as_text = (i == len);
            }
            */

            RETVAL = _init_length_buffer( aTHX_
                len,
                (encode_as_text ? TYPE_UTF8 : TYPE_BINARY),
                buffer
            );

            sv_catpvn( RETVAL, val, len );
        }
    }
    else if (sv_isobject(value)) {
        if (sv_derived_from(value, BOOLEAN_CLASS)) {
            char newbyte = SvIV(SvRV(value)) ? CBOR_TRUE : CBOR_FALSE;

            if (buffer) {
                sv_catpvn( buffer, &newbyte, 1 );
                RETVAL = buffer;
            }
            else {
                RETVAL = newSVpvn(&newbyte, 1);
            }
        }
        else if (sv_derived_from(value, TAGGED_CLASS)) {
            AV *array = (AV *)SvRV(value);
            SV **tag = av_fetch(array, 0, 0);
            IV tagnum = SvIV(*tag);

            RETVAL = _init_length_buffer( aTHX_ tagnum, TYPE_TAG, buffer );
            _encode( aTHX_ *(av_fetch(array, 1, 0)), RETVAL );
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

            SV **cur;
            for (i=0; i<len; i++) {
                cur = av_fetch(array, i, 0);
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
                sv_catpvn( RETVAL, key, key_length );

                _encode( aTHX_ cur, RETVAL );
            }
        }
        else {
            _croak_unrecognized(aTHX_ value);
        }
    }

    --encode_recurse;

    return RETVAL;
}

//----------------------------------------------------------------------

// NB: We already checked that curbyte is safe to read!
struct_sizeparse _parse_for_uint_len( pTHX_ decode_ctx* decstate ) {
    struct_sizeparse ret;

    switch (*(decstate->curbyte) & 0x1f) {  // 0x1f == 0b00011111
        case 0x18:

            //num = 2 * (num - 0x17)
            //_decode_check_for_overage( aTHX_ decstate, 1 + num);
            //return num

            _decode_check_for_overage( aTHX_ decstate, 2);

            ++decstate->curbyte;

            ret.sizetype = small;
            ret.size.u8 = *decstate->curbyte;

            ++decstate->curbyte;

            break;

        case 0x19:
            _decode_check_for_overage( aTHX_ decstate, 3);

            ++decstate->curbyte;

            ret.sizetype = medium;
            _u16_to_buffer( *((uint16_t *) decstate->curbyte), (unsigned char *) &(ret.size.u16) );

            decstate->curbyte += 2;

            break;

        case 0x1a:
            _decode_check_for_overage( aTHX_ decstate, 5);

            ++decstate->curbyte;

            ret.sizetype = large;
            _u32_to_buffer( *((uint32_t *) decstate->curbyte), (unsigned char *) &(ret.size.u32) );

            decstate->curbyte += 4;

            break;

        case 0x1b:
            _decode_check_for_overage( aTHX_ decstate, 9);

            ++decstate->curbyte;

            ret.sizetype = huge;
            _u64_to_buffer( *((uint64_t *) decstate->curbyte), (unsigned char *) &(ret.size.u64) );

            decstate->curbyte += 8;

            break;

        case 0x1c:
        case 0x1d:
        case 0x1e:
            _croak_invalid_control( aTHX_ decstate );
            break;

        case 0x1f:
            // ++decstate->curbyte;
            // NOTE: We do NOT increment the pointer here
            // because callers need to distinguish for themselves
            // whether indefinite is a valid case.

            ret.sizetype = indefinite;

            break;

        default:
            ret.sizetype = small;
            ret.size.u8 = (uint8_t) (*(decstate->curbyte) & 0x1f);

            decstate->curbyte++;

            break;
    }

    return ret;
}

//----------------------------------------------------------------------

SV *_decode_array( pTHX_ decode_ctx* decstate ) {
    SSize_t array_length;

    AV *array = NULL;
    SV *cur = NULL;

    struct_sizeparse sizeparse = _parse_for_uint_len( aTHX_ decstate );

    switch (sizeparse.sizetype) {
        //case tiny:
        case small:
            array_length = sizeparse.size.u8;
            break;

        case medium:
            array_length = sizeparse.size.u16;
            break;

        case large:
            array_length = sizeparse.size.u32;
            break;

        case huge:
            array_length = sizeparse.size.u64;
            break;

        case indefinite:
            ++decstate->curbyte;

            array = newAV();

            while (*(decstate->curbyte) != '\xff') {

                cur = _decode( aTHX_ decstate );
                av_push(array, cur);
                //sv_2mortal(cur);
            }

            _decode_check_for_overage( aTHX_ decstate, 1 );

            ++decstate->curbyte;
    }

    if (!array) {
        array = newAV();

        if (array_length) {
            av_fill(array, array_length - 1);

            SSize_t i;
            for (i=0; i<array_length; i++) {
                cur = _decode( aTHX_ decstate );

                if (!av_store(array, i, cur)) {
                    croak("Failed to store item in array!");
                }
            }
        }
    }

    return newRV_noinc( (SV *) array);
}

//----------------------------------------------------------------------

void _decode_to_hash( pTHX_ decode_ctx* decstate, HV *hash ) {
    SV *curkey = _decode( aTHX_ decstate );
    SV *curval = _decode( aTHX_ decstate );

    char *keystr = SvPV_nolen(curkey);

    hv_store(hash, keystr, SvCUR(curkey), curval, 0);
    sv_2mortal(curkey);
}

SV *_decode_map( pTHX_ decode_ctx* decstate ) {
    SSize_t keycount = 0;

    HV *hash = newHV();

    struct_sizeparse sizeparse = _parse_for_uint_len( aTHX_ decstate );

    switch (sizeparse.sizetype) {
        //case tiny:
        case small:
            keycount = sizeparse.size.u8;
            break;

        case medium:
            keycount = sizeparse.size.u16;
            break;

        case large:
            keycount = sizeparse.size.u32;
            break;

        case huge:
            keycount = sizeparse.size.u64;
            break;

        case indefinite:
            ++decstate->curbyte;

            while (*(decstate->curbyte) != '\xff') {
                _decode_to_hash( aTHX_ decstate, hash );
            }

            _decode_check_for_overage( aTHX_ decstate, 1 );

            ++decstate->curbyte;
    }

    if (keycount) {
        while (keycount > 0) {
            _decode_to_hash( aTHX_ decstate, hash );
            --keycount;
        }
    }

    return newRV_noinc( (SV *) hash);
}

//----------------------------------------------------------------------

// Taken from RFC 7049:
double decode_half_float(unsigned char *halfp) {
    int half = (halfp[0] << 8) + halfp[1];
    int exp = (half >> 10) & 0x1f;
    int mant = half & 0x3ff;
    double val;
    if (exp == 0) val = ldexp(mant, -24);
    else if (exp != 31) val = ldexp(mant + 1024, exp - 25);
    else val = mant == 0 ? INFINITY : NAN;
    return half & 0x8000 ? -val : val;
}

float _decode_float_to_little_endian( unsigned char *ptr ) {
    uint32_t host_uint = (*ptr << 24) + (*(ptr + 1) << 16) + (*(ptr + 2) << 8) + *(ptr + 3);

    return( *( (float *) &host_uint ) );
}

double _decode_double_to_little_endian( unsigned char *ptr ) {
    // It doesn’t work to do these additions in one fell swoop;
    // the resulting host_uint ends up being all zeros.

    uint64_t host_uint = (*ptr << 24) + (*(ptr + 1) << 16) + (*(ptr + 2) << 8) + *(ptr + 3);

    host_uint <<= 32;

    // It doesn’t work to add these to host_uint all together.
    // In testing, when I started with (little-endian) bytes
    // 00.00.00.00.99.99.f1.3f then tried to add the following
    // directly, the leftmost 0x99 byte became 0x98. (wtf?!?)
    // For some reason, creating a separate number here solves that.
    uint32_t lower = (*(ptr + 4) << 24) + (*(ptr + 5) << 16) + (*(ptr + 6) << 8) + *(ptr + 7);

    host_uint += lower;

    return( *( (double *) &host_uint ) );
}

//----------------------------------------------------------------------

SV *_decode( pTHX_ decode_ctx* decstate ) {
    SV *ret = NULL;

    _decode_check_for_overage( aTHX_ decstate, 1);

    struct_sizeparse sizeparse;

    unsigned char major_type = *(decstate->curbyte) & 0xe0;

    switch (major_type) {
        case TYPE_UINT:
            sizeparse = _parse_for_uint_len( aTHX_ decstate );
            switch (sizeparse.sizetype) {
                //case tiny:
                case small:
                    ret = newSVuv( sizeparse.size.u8 );
                    break;

                case medium:
                    ret = newSVuv( sizeparse.size.u16 );
                    break;

                case large:
                    ret = newSVuv( sizeparse.size.u32 );
                    break;

                case huge:
                    ret = newSVuv( sizeparse.size.u64 );
                    break;

                default:
                    _croak_invalid_control( aTHX_ decstate );
                    break;

            }

            break;
        case TYPE_NEGINT:
            sizeparse = _parse_for_uint_len( aTHX_ decstate );

            switch (sizeparse.sizetype) {
                //case tiny:
                case small:
                    ret = newSViv( -1 - sizeparse.size.u8 );
                    break;

                case medium:
                    ret = newSViv( -1 - sizeparse.size.u16 );
                    break;

                case large:
                    ret = newSViv( ( (int64_t) sizeparse.size.u32 ) * -1 - 1 );
                    break;

                case huge:
                    ret = newSViv( ( (int64_t) sizeparse.size.u64 ) * -1 - 1 );
                    break;

                default:
                    _croak_invalid_control( aTHX_ decstate );
                    break;

            }

            break;
        case TYPE_BINARY:
        case TYPE_UTF8:
            sizeparse = _parse_for_uint_len( aTHX_ decstate );

            switch (sizeparse.sizetype) {
                //case tiny:
                case small:
                    _decode_check_for_overage( aTHX_ decstate, sizeparse.size.u8);
                    ret = newSVpvn( decstate->curbyte, sizeparse.size.u8 );
                    decstate->curbyte += sizeparse.size.u8;

                    break;

                case medium:
                    _decode_check_for_overage( aTHX_ decstate, sizeparse.size.u16);
                    ret = newSVpvn( decstate->curbyte, sizeparse.size.u16 );
                    decstate->curbyte += sizeparse.size.u16;

                    break;

                case large:
                    _decode_check_for_overage( aTHX_ decstate, sizeparse.size.u32);
                    ret = newSVpvn( decstate->curbyte, sizeparse.size.u32 );
                    decstate->curbyte += sizeparse.size.u32;

                    break;

                case huge:
                    _decode_check_for_overage( aTHX_ decstate, sizeparse.size.u64);
                    ret = newSVpvn( decstate->curbyte, sizeparse.size.u64 );
                    decstate->curbyte += sizeparse.size.u64;
                    break;

                case indefinite:
                    ++decstate->curbyte;

                    ret = newSVpvs("");

                    while (*(decstate->curbyte) != '\xff') {
                        //TODO: Require the same major type.

                        SV *cur = _decode( aTHX_ decstate );

                        sv_catsv(ret, cur);
                    }

                    _decode_check_for_overage( aTHX_ decstate, 1 );

                    ++decstate->curbyte;

                    break;

                default:

                    // This shouldn’t happen, but just in case.
                    croak("Unknown string length descriptor!");
            }

            // XXX: “perldoc perlapi” says this function is experimental.
            // Its use here is a calculated risk; the alternatives are
            // to invoke utf8::decode() via call_pv(), which is ugly,
            // or just to assume the UTF-8 is valid, which is wrong.
            //
            if (TYPE_UTF8 == major_type) {
                if ( !sv_utf8_decode(ret) ) {
                    _croak_invalid_utf8( aTHX_ ret );
                }
            }

            break;
        case TYPE_ARRAY:
            ret = _decode_array( aTHX_ decstate );

            break;
        case TYPE_MAP:
            ret = _decode_map( aTHX_ decstate );

            break;
        case TYPE_TAG:

            // For now, just throw this tag value away.
            sizeparse = _parse_for_uint_len( aTHX_ decstate );
            if (sizeparse.sizetype == indefinite) {
                _croak_invalid_control( aTHX_ decstate );
            }

            ret = _decode( aTHX_ decstate );

            break;
        case TYPE_OTHER:
            switch ((uint8_t) *(decstate->curbyte)) {
                case CBOR_FALSE:
                    ret = newSVsv( get_sv("CBOR::Free::false", 0) );
                    ++decstate->curbyte;
                    break;

                case CBOR_TRUE:
                    ret = newSVsv( get_sv("CBOR::Free::true", 0) );
                    ++decstate->curbyte;
                    break;

                case CBOR_NULL:
                case CBOR_UNDEFINED:
                    ret = newSVsv( &PL_sv_undef );
                    ++decstate->curbyte;
                    break;

                case CBOR_HALF_FLOAT:
                    _decode_check_for_overage( aTHX_ decstate, 3 );

                    ret = newSVnv( decode_half_float( (unsigned char *) (1 + decstate->curbyte) ) );

                    decstate->curbyte += 3;
                    break;

                case CBOR_FLOAT:
                    _decode_check_for_overage( aTHX_ decstate, 5 );

                    if (is_big_endian) {
                        ret = newSVnv( *( (float *) (1 + decstate->curbyte) ) );
                    }
                    else {
                        ret = newSVnv( _decode_float_to_little_endian( (unsigned char *) (1 + decstate->curbyte) ) );
                    }

                    decstate->curbyte += 5;
                    break;

                case CBOR_DOUBLE:
                    _decode_check_for_overage( aTHX_ decstate, 9 );

                    if (is_big_endian) {
                        ret = newSVnv( *( (double *) (1 + decstate->curbyte) ) );
                    }
                    else {
                        ret = newSVnv( _decode_double_to_little_endian( (unsigned char *) (1 + decstate->curbyte) ) );
                    }

                    decstate->curbyte += 9;
                    break;

                default:
                    _croak_invalid_control( aTHX_ decstate );
            }

            break;

        default:
            croak("Unknown type!");
    }

    return ret;
}

//----------------------------------------------------------------------

MODULE = CBOR::Free           PACKAGE = CBOR::Free

PROTOTYPES: DISABLE

BOOT:
    HV *stash = gv_stashpvn("CBOR::Free", 10, FALSE);
    newCONSTSUB(stash, "_MAX_RECURSION", newSVuv( MAX_ENCODE_RECURSE ));

    unsigned short testshort = 1;
    is_big_endian = !(bool) *((char *) &testshort);

SV *
fake_encode( SV * value )
    CODE:
        RETVAL = newSVpvn("\127", 1);

        sv_catpvn( RETVAL, "abcdefghijklmnopqrstuvw", 23 );
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
            SvPV_nolen(cbor),
            SvEND(cbor)
        };

        RETVAL = _decode( aTHX_ &decode_state );

        if (decode_state.curbyte != decode_state.end) {
            STRLEN bytes_count = decode_state.end - decode_state.curbyte;

            SV *leftover_count = (SV *) get_sv("CBOR::Free::_LEFTOVER_COUNT", 0);

            // TODO: Figure out how to “vivify” leftover_count when it’s
            // undef without getting a warning.

            SvUV(leftover_count);
            SvUV_set(leftover_count, bytes_count);

            call_pv("CBOR::Free::_warn_decode_leftover", 0);
        }

    OUTPUT:
        RETVAL
